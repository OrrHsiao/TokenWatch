import Foundation
import os.log

/// 与 ccusage loader 对齐的跨文件事件去重键；session ID 故意不参与。
struct CodexEventDedupKey: Hashable, Sendable {
    let timestampKey: String
    let model: String
    let rawInput: Int
    let cachedInput: Int
    let output: Int
    let reasoning: Int
    let total: Int
}

/// 保留展示 entry 与上游原始计数，避免 per-file cache 丢失去重信息。
struct CodexUsageCandidate: Sendable {
    let entry: ParsedUsageEntry
    let dedupKey: CodexEventDedupKey
}

/// replay 预检结果；`.pending` 为后续增量解析保留未决状态。
enum CodexReplayClassification: Sendable, Equatable {
    case notReplay
    case pending
    case replay(second: String)

    var replaySecond: String? {
        guard case .replay(let second) = self else { return nil }
        return second
    }
}

/// 解析 Codex rollout JSONL,提取 token_count 事件 → 统一 ParsedUsageEntry
///
/// 关键策略(参考 ccusage `adapter/codex/parser.rs` + TokenTracker `codex-rollout-parser.js`):
/// - `last_token_usage` 优先;缺失则 `delta = saturatingSub(total, prevTotal)`
/// - `previousTotals` 始终更新(包括跳过本条的情形),确保后续 delta 推导正确
/// - 4 维全 0 的事件视为 replay marker / 心跳,跳过(prevTotals 仍要更新)
/// - cached input 先夹到 nonnegative raw input，再拆 pure/cache_read，防止双计与负 pure
/// - `output_tokens` 已含 reasoning,直接进 PricingEngine,reasoning 不另计费
final class CodexRolloutParser: @unchecked Sendable {

    private let logger = Logger(subsystem: "com.xiaoao.TokenWatch", category: "CodexRolloutParser")
    // Parser 会被后台 task 复用;可变缓存统一由 cacheLock 保护。
    private let cacheLock = NSLock()
    private var cachedFiles: [String: CachedFile] = [:]
    private var cacheHitCount = 0

    var debugCachedFileCount: Int {
        withCacheLock { cachedFiles.count }
    }

    var debugCacheHitCount: Int {
        withCacheLock { cacheHitCount }
    }

    private struct FileSignature: Equatable {
        let size: Int
        let modificationDate: Date

        init(url: URL) throws {
            let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
            size = (attributes[.size] as? NSNumber)?.intValue ?? 0
            modificationDate = (attributes[.modificationDate] as? Date) ?? .distantPast
        }
    }

    private struct CachedFile {
        let signature: FileSignature
        let pricingSpeed: CodexPricingSpeed
        let candidates: [CodexUsageCandidate]
    }

    /// 解析单个 Codex rollout 文件。
    /// - Parameters:
    ///   - fileInfo: rollout 文件元数据。
    ///   - pricingSpeed: 写入 usage service tier 的计价速度，默认保持 standard 兼容。
    /// - Returns: 文件中的有效 token 事件。
    func parseFile(
        _ fileInfo: CodexRolloutFileInfo,
        pricingSpeed: CodexPricingSpeed = .standard
    ) throws -> [ParsedUsageEntry] {
        try parseCandidates(fileInfo, pricingSpeed: pricingSpeed).map(\.entry)
    }

    /// 流式解析单个 rollout，并保留 loader 去重所需的 source counts。
    private func parseCandidates(
        _ fileInfo: CodexRolloutFileInfo,
        pricingSpeed: CodexPricingSpeed
    ) throws -> [CodexUsageCandidate] {
        let decoder = JSONDecoder()
        let replayClassification = classifyReplay(fileInfo.url, decoder: decoder)
        let replaySecond = replayClassification.replaySecond

        var candidates: [CodexUsageCandidate] = []
        var currentModel: CodexModelState?
        var sessionCwd: String?
        var sessionID = fileInfo.sessionID
        var previousTotals: CodexTokenCounts?
        var skippingReplay = replaySecond != nil

        try Self.forEachLine(at: fileInfo.url) { lineData in
            guard let record = try? decoder.decode(CodexRecord.self, from: lineData) else {
                return true
            }

            switch record.payload {
            case .sessionMeta(let meta):
                sessionID = meta.id
                sessionCwd = meta.cwd

            case .turnContext(let context):
                if let model = context.preferredModel {
                    _ = CodexModelResolver.resolve(
                        parsedModel: model,
                        eventDate: record.timestamp,
                        current: &currentModel
                    )
                }

            case .eventMsg(let event):
                guard event.type == "token_count",
                      let timestamp = record.normalizedTimestamp else {
                    return true
                }

                if skippingReplay, let replaySecond {
                    if Self.timestampSecond(timestamp.key) == replaySecond {
                        if let total = event.info?.totalTokenUsage {
                            previousTotals = total
                        }
                        return true
                    }
                    skippingReplay = false
                }

                guard let info = event.info else { return true }
                let delta: CodexTokenCounts
                if let last = info.lastTokenUsage {
                    delta = last
                } else if let total = info.totalTokenUsage {
                    delta = total.subtracting(previousTotals ?? .zero)
                } else {
                    return true
                }
                if let total = info.totalTokenUsage {
                    previousTotals = total
                }
                guard !delta.isAllZero else { return true }

                let model = CodexModelResolver.resolve(
                    parsedModel: event.preferredModel ?? info.preferredModel,
                    eventDate: timestamp.date,
                    current: &currentModel
                )
                let normalized = delta.normalizedForBilling
                let usage = TokenUsage(
                    inputTokens: normalized.pureInput,
                    cacheCreationInputTokens: 0,
                    cacheReadInputTokens: normalized.cachedInput,
                    outputTokens: normalized.output,
                    reasoningTokens: normalized.reasoning,
                    serverToolUse: ServerToolUse(webSearchRequests: 0, webFetchRequests: 0),
                    serviceTier: pricingSpeed == .fast ? "fast" : "",
                    cacheCreation: nil,
                    inferenceGeo: "",
                    iterations: [],
                    speed: ""
                )
                let messageID = "\(sessionID):\(timestamp.key)"
                let entry = ParsedUsageEntry(
                    recordUUID: messageID,
                    messageId: messageID,
                    requestId: nil,
                    sessionID: sessionID,
                    timestamp: timestamp.date,
                    model: model,
                    cwd: sessionCwd,
                    agentId: nil,
                    usage: usage,
                    isSubagent: false,
                    provider: .codex,
                    upstreamProviderID: nil,
                    upstreamCost: nil
                )
                candidates.append(CodexUsageCandidate(
                    entry: entry,
                    dedupKey: CodexEventDedupKey(
                        timestampKey: timestamp.key,
                        model: model,
                        rawInput: normalized.rawInput,
                        cachedInput: normalized.cachedInput,
                        output: normalized.output,
                        reasoning: normalized.reasoning,
                        total: normalized.total
                    )
                ))

            case .unknown:
                break
            }
            return true
        }
        return candidates
    }

    /// 仅在前 16KiB 含 thread/fork marker 时比较前两条有效 usage 的规范化秒。
    private func classifyReplay(
        _ url: URL,
        decoder: JSONDecoder
    ) -> CodexReplayClassification {
        guard Self.hasReplayMarker(inPrefixOf: url) else { return .notReplay }

        var firstSecond: String?
        var result: CodexReplayClassification = .pending
        do {
            try Self.forEachLine(at: url) { lineData in
                guard let record = try? decoder.decode(CodexRecord.self, from: lineData),
                      case let .eventMsg(event) = record.payload,
                      event.type == "token_count",
                      event.info?.lastTokenUsage != nil || event.info?.totalTokenUsage != nil,
                      let timestamp = record.normalizedTimestamp,
                      let second = Self.timestampSecond(timestamp.key) else {
                    return true
                }
                guard let firstSecond else {
                    firstSecond = second
                    return true
                }
                result = firstSecond == second ? .replay(second: second) : .notReplay
                return false
            }
        } catch {
            return .pending
        }
        return result
    }

    private static func hasReplayMarker(inPrefixOf url: URL) -> Bool {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return false }
        defer { try? handle.close() }
        guard let prefix = try? handle.read(upToCount: 16 * 1024) else { return false }
        return prefix.range(of: Data("thread_spawn".utf8)) != nil
            || prefix.range(of: Data("forked_from_id".utf8)) != nil
    }

    private static func timestampSecond(_ key: String) -> String? {
        let prefix = key.utf8.prefix(19)
        guard prefix.count == 19 else { return nil }
        return String(decoding: prefix, as: UTF8.self)
    }

    /// 以 64KiB 分块遍历 JSONL；回调返回 false 时供 replay 预检提前结束。
    private static func forEachLine(
        at url: URL,
        _ body: (Data) -> Bool
    ) throws {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }

        let newline: UInt8 = 0x0A
        var buffer = Data()
        while true {
            let chunk = try handle.read(upToCount: 64 * 1024) ?? Data()
            if chunk.isEmpty { break }
            buffer.append(chunk)

            var searchStart = buffer.startIndex
            while let newlineIndex = buffer[searchStart..<buffer.endIndex].firstIndex(of: newline) {
                if newlineIndex > searchStart,
                   !body(Data(buffer[searchStart..<newlineIndex])) {
                    return
                }
                searchStart = buffer.index(after: newlineIndex)
            }
            if searchStart > buffer.startIndex {
                buffer.removeSubrange(buffer.startIndex..<searchStart)
            }
        }
        if !buffer.isEmpty {
            _ = body(buffer)
        }
    }

    /// 批量解析并按 upstream event key 保留输入顺序中的第一条。
    /// - Parameters:
    ///   - files: 待解析的 rollout 文件。
    ///   - pricingSpeed: 本批次统一使用的 Codex 计价速度。
    /// - Returns: 跨文件去重后的 usage 条目。
    func parseAllFiles(
        _ files: [CodexRolloutFileInfo],
        pricingSpeed: CodexPricingSpeed = .standard
    ) throws -> [ParsedUsageEntry] {
        var all: [CodexUsageCandidate] = []
        var currentCacheKeys: Set<String> = []
        for f in files {
            let cacheKey = Self.cacheKey(for: f.url)
            currentCacheKeys.insert(cacheKey)
            do {
                all.append(contentsOf: try parseCachedFile(
                    f,
                    cacheKey: cacheKey,
                    pricingSpeed: pricingSpeed
                ))
            } catch {
                logger.warning("Codex 文件解析失败: \(f.url.lastPathComponent) — \(error.localizedDescription)")
            }
        }
        pruneCache(keeping: currentCacheKeys)

        var seen: Set<CodexEventDedupKey> = []
        seen.reserveCapacity(all.count)
        var entries: [ParsedUsageEntry] = []
        entries.reserveCapacity(all.count)
        for candidate in all where seen.insert(candidate.dedupKey).inserted {
            entries.append(candidate.entry)
        }
        return entries
    }

    private func parseCachedFile(
        _ fileInfo: CodexRolloutFileInfo,
        cacheKey: String,
        pricingSpeed: CodexPricingSpeed
    ) throws -> [CodexUsageCandidate] {
        let signature = try FileSignature(url: fileInfo.url)
        if let cached = cachedFile(
            for: cacheKey,
            matching: signature,
            pricingSpeed: pricingSpeed
        ) {
            return cached
        }

        let candidates = try parseCandidates(fileInfo, pricingSpeed: pricingSpeed)
        withCacheLock {
            cachedFiles[cacheKey] = CachedFile(
                signature: signature,
                pricingSpeed: pricingSpeed,
                candidates: candidates
            )
        }
        return candidates
    }

    private func cachedFile(
        for cacheKey: String,
        matching signature: FileSignature,
        pricingSpeed: CodexPricingSpeed
    ) -> [CodexUsageCandidate]? {
        withCacheLock {
            guard let cached = cachedFiles[cacheKey],
                  cached.signature == signature,
                  cached.pricingSpeed == pricingSpeed else {
                return nil
            }
            cacheHitCount += 1
            return cached.candidates
        }
    }

    private func pruneCache(keeping currentKeys: Set<String>) {
        withCacheLock {
            cachedFiles = cachedFiles.filter { currentKeys.contains($0.key) }
        }
    }

    private static func cacheKey(for url: URL) -> String {
        url.standardizedFileURL.path
    }

    private func withCacheLock<T>(_ body: () throws -> T) rethrows -> T {
        cacheLock.lock()
        defer { cacheLock.unlock() }
        return try body()
    }
}
