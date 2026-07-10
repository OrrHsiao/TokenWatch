import Foundation
import os.log

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
        let entries: [ParsedUsageEntry]
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
        let handle = try FileHandle(forReadingFrom: fileInfo.url)
        defer { try? handle.close() }

        let decoder = JSONDecoder()
        let newline: UInt8 = 0x0A

        var entries: [ParsedUsageEntry] = []
        var currentModel: CodexModelState?
        var sessionCwd: String? = nil
        var sessionID = fileInfo.sessionID    // 优先文件名,session_meta 出现时覆盖
        var previousTotals = CodexTokenCounts.zero

        // 流式 64KB 分块,与 Claude 解析保持一致
        var buffer = Data()
        let chunkSize = 64 * 1024

        let processLine: (Data) -> Void = { lineData in
            guard !lineData.isEmpty else { return }
            guard let record = try? decoder.decode(CodexRecord.self, from: lineData) else { return }

            switch record.payload {
            case .sessionMeta(let meta):
                sessionID = meta.id
                sessionCwd = meta.cwd

            case .turnContext(let context):
                if let model = context.model {
                    _ = CodexModelResolver.resolve(
                        parsedModel: model,
                        eventDate: record.timestamp,
                        current: &currentModel
                    )
                }

            case .eventMsg(let event):
                guard event.type == "token_count" else { return }
                guard let info = event.info else { return }     // info=null 心跳

                // 计算 delta:优先 last_token_usage,否则用 total 增量
                let delta: CodexTokenCounts
                if let last = info.lastTokenUsage {
                    delta = last
                } else if let total = info.totalTokenUsage {
                    delta = CodexTokenCounts(
                        inputTokens: max(0, total.inputTokens - previousTotals.inputTokens),
                        cachedInputTokens: max(0, total.cachedInputTokens - previousTotals.cachedInputTokens),
                        outputTokens: max(0, total.outputTokens - previousTotals.outputTokens),
                        reasoningOutputTokens: max(0, total.reasoningOutputTokens - previousTotals.reasoningOutputTokens),
                        totalTokens: max(0, total.totalTokens - previousTotals.totalTokens)
                    )
                } else {
                    return
                }

                // previousTotals 始终更新(即便后面跳过本条)— 否则 delta 推导会错位
                if let total = info.totalTokenUsage {
                    previousTotals = total
                }

                // replay marker / 静默事件 → 跳过 emit,但 prevTotal 已更新
                guard !delta.isAllZero else { return }

                let model = CodexModelResolver.resolve(
                    parsedModel: event.model ?? info.model,
                    eventDate: record.timestamp,
                    current: &currentModel
                )
                let rawInput = max(0, delta.inputTokens)
                // ccusage 先将 cached_input_tokens 夹到 raw input，再拆 pure/cached。
                let cachedInput = min(max(0, delta.cachedInputTokens), rawInput)
                let pureInput = rawInput - cachedInput

                let usage = TokenUsage(
                    inputTokens: pureInput,
                    cacheCreationInputTokens: 0,
                    cacheReadInputTokens: cachedInput,
                    outputTokens: delta.outputTokens,
                    serverToolUse: ServerToolUse(webSearchRequests: 0, webFetchRequests: 0),
                    serviceTier: pricingSpeed == .fast ? "fast" : "",
                    cacheCreation: nil,
                    inferenceGeo: "",
                    iterations: [],
                    speed: ""
                )

                // 合成 dedup key:sessionId + timestamp ISO8601(无 message.id)
                let tsKey = record.timestamp.map { Self.iso8601Key($0) } ?? "no-ts-\(UUID().uuidString)"
                let messageId = "\(sessionID):\(tsKey)"

                entries.append(ParsedUsageEntry(
                    recordUUID: messageId,
                    messageId: messageId,
                    requestId: nil,
                    sessionID: sessionID,
                    timestamp: record.timestamp,
                    model: model,
                    cwd: sessionCwd,
                    agentId: nil,
                    usage: usage,
                    isSubagent: false,
                    provider: .codex,
                    upstreamProviderID: nil,
                    upstreamCost: nil
                ))

            case .unknown:
                return
            }
        }

        while true {
            let chunk = try handle.read(upToCount: chunkSize) ?? Data()
            if chunk.isEmpty { break }
            buffer.append(chunk)

            var searchStart = buffer.startIndex
            while let nl = buffer[searchStart..<buffer.endIndex].firstIndex(of: newline) {
                processLine(Data(buffer[searchStart..<nl]))
                searchStart = buffer.index(after: nl)
            }
            if searchStart > buffer.startIndex {
                buffer.removeSubrange(buffer.startIndex..<searchStart)
            }
        }
        if !buffer.isEmpty {
            processLine(buffer)
        }

        return entries
    }

    /// 批量解析并按 dedupKey 取 magnitude 最大的条目。
    /// - Parameters:
    ///   - files: 待解析的 rollout 文件。
    ///   - pricingSpeed: 本批次统一使用的 Codex 计价速度。
    /// - Returns: 跨文件去重后的 usage 条目。
    func parseAllFiles(
        _ files: [CodexRolloutFileInfo],
        pricingSpeed: CodexPricingSpeed = .standard
    ) throws -> [ParsedUsageEntry] {
        var all: [ParsedUsageEntry] = []
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

        var bestByKey: [String: ParsedUsageEntry] = [:]
        bestByKey.reserveCapacity(all.count)
        for e in all {
            let key = e.dedupKey
            if let existing = bestByKey[key] {
                if Self.magnitude(e.usage) > Self.magnitude(existing.usage) {
                    bestByKey[key] = e
                }
            } else {
                bestByKey[key] = e
            }
        }
        return Array(bestByKey.values)
    }

    private static func magnitude(_ u: TokenUsage) -> Int {
        u.inputTokens + u.outputTokens + u.cacheReadInputTokens + u.totalCacheCreationTokens
    }

    /// 把 Date 转为稳定的字符串,作为 dedup key 的时间分量
    /// 设计原因:Date 的 hashValue 在不同平台/版本可能差异;ISO8601 字符串可读且稳定
    private static func iso8601Key(_ date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.string(from: date)
    }

    private func parseCachedFile(
        _ fileInfo: CodexRolloutFileInfo,
        cacheKey: String,
        pricingSpeed: CodexPricingSpeed
    ) throws -> [ParsedUsageEntry] {
        let signature = try FileSignature(url: fileInfo.url)
        if let cached = cachedFile(
            for: cacheKey,
            matching: signature,
            pricingSpeed: pricingSpeed
        ) {
            return cached
        }

        let entries = try parseFile(fileInfo, pricingSpeed: pricingSpeed)
        withCacheLock {
            cachedFiles[cacheKey] = CachedFile(
                signature: signature,
                pricingSpeed: pricingSpeed,
                entries: entries
            )
        }
        return entries
    }

    private func cachedFile(
        for cacheKey: String,
        matching signature: FileSignature,
        pricingSpeed: CodexPricingSpeed
    ) -> [ParsedUsageEntry]? {
        withCacheLock {
            guard let cached = cachedFiles[cacheKey],
                  cached.signature == signature,
                  cached.pricingSpeed == pricingSpeed else {
                return nil
            }
            cacheHitCount += 1
            return cached.entries
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
