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

/// 解析 Codex rollout JSONL，提取 token_count 事件为统一用量条目。
///
/// 关键策略参考 ccusage `adapter/codex/parser.rs`：
/// - `last_token_usage` 优先；缺失则 `delta = saturatingSub(total, previousTotals)`。
/// - `previousTotals` 始终更新，确保 replay 跳过与后续 delta 的 baseline 正确。
/// - cached input 夹到 raw input 后拆为 pure/cache-read，跨文件按 raw key first-wins。
final class CodexRolloutParser: @unchecked Sendable {

    private let logger = Logger(subsystem: "com.xiaoao.TokenWatch", category: "CodexRolloutParser")
    private let fileReader: any JSONLFileReading
    private let cacheCoordinator: JSONLLastGoodCacheCoordinator<
        [CodexUsageCandidate],
        CodexPricingSpeed
    >

    init(fileReader: any JSONLFileReading = SystemJSONLFileReader()) {
        self.fileReader = fileReader
        self.cacheCoordinator = JSONLLastGoodCacheCoordinator<
            [CodexUsageCandidate],
            CodexPricingSpeed
        >(fileReader: fileReader)
    }

    var debugCachedFileCount: Int {
        cacheCoordinator.debugCachedFileCount
    }

    var debugCacheHitCount: Int {
        cacheCoordinator.debugCacheHitCount
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
        let snapshot = try fileReader.openSnapshot(for: fileInfo.url)
        defer { snapshot.stream.close() }
        return try parseCandidates(
            snapshot.stream,
            metadata: snapshot.metadata,
            fileInfo: fileInfo,
            pricingSpeed: pricingSpeed
        ).map(\.entry)
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
        let allCandidates: [CodexUsageCandidate] = cacheCoordinator.loadListedFiles(
            files,
            scope: pricingSpeed,
            cacheKey: { Self.cacheKey(for: $0.url) },
            urlForFile: { $0.url },
            build: { [self] fileInfo, snapshot, _ in
                try parseCandidates(
                    snapshot.stream,
                    metadata: snapshot.metadata,
                    fileInfo: fileInfo,
                    pricingSpeed: pricingSpeed
                )
            },
            project: { $0 },
            onFailure: { [self] fileInfo, error, reusedLastGood in
                if reusedLastGood {
                    logger.warning(
                        "文件暂时不可读，复用上次成功结果: \(fileInfo.url.lastPathComponent) — \(error.localizedDescription)"
                    )
                } else {
                    logger.warning(
                        "文件首次读取失败，跳过: \(fileInfo.url.lastPathComponent) — \(error.localizedDescription)"
                    )
                }
            }
        )

        var seen: Set<CodexEventDedupKey> = []
        seen.reserveCapacity(allCandidates.count)
        var entries: [ParsedUsageEntry] = []
        entries.reserveCapacity(allCandidates.count)
        for candidate in allCandidates where seen.insert(candidate.dedupKey).inserted {
            entries.append(candidate.entry)
        }
        return entries
    }

    /// 在同一 descriptor stream 上完成 replay 预检与 provider-specific reducer。
    private func parseCandidates(
        _ stream: any JSONLByteStream,
        metadata: JSONLFileMetadata,
        fileInfo: CodexRolloutFileInfo,
        pricingSpeed: CodexPricingSpeed
    ) throws -> [CodexUsageCandidate] {
        // metadata 参数是下一阶段增量状态的固定入口；本阶段完整 parse 只消费 stream。
        _ = metadata
        let decoder = JSONDecoder()
        let replayClassification = try classifyReplay(stream, decoder: decoder)
        let replaySecond = replayClassification.replaySecond

        var candidates: [CodexUsageCandidate] = []
        var currentModel: CodexModelState?
        var sessionCwd: String?
        var sessionID = fileInfo.sessionID
        var previousTotals: CodexTokenCounts?
        var skippingReplay = replaySecond != nil

        try Self.forEachLine(in: stream) { lineData, _ in
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

    /// 仅在前 16 KiB 含 thread/fork marker 时比较前两条有效 usage 的规范化秒。
    /// I/O 错误必须上抛，使 coordinator 保留 last-good，而不是误分类为 pending。
    private func classifyReplay(
        _ stream: any JSONLByteStream,
        decoder: JSONDecoder
    ) throws -> CodexReplayClassification {
        guard try Self.hasReplayMarker(inPrefixOf: stream) else {
            return .notReplay
        }

        var firstSecond: String?
        var result: CodexReplayClassification = .pending
        try Self.forEachLine(in: stream) { lineData, _ in
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
        return result
    }

    private static func hasReplayMarker(
        inPrefixOf stream: any JSONLByteStream
    ) throws -> Bool {
        try stream.seek(toOffset: 0)
        var prefix = Data()
        let limit = 16 * 1024
        while prefix.count < limit {
            let chunk = try stream.read(upToCount: limit - prefix.count)
            if chunk.isEmpty { break }
            prefix.append(chunk)
        }
        return prefix.range(of: Data("thread_spawn".utf8)) != nil
            || prefix.range(of: Data("forked_from_id".utf8)) != nil
    }

    private static func timestampSecond(_ key: String) -> String? {
        let prefix = key.utf8.prefix(19)
        guard prefix.count == 19 else { return nil }
        return String(decoding: prefix, as: UTF8.self)
    }

    /// 从 stream 起点以 64 KiB 分块遍历 JSONL，并传递稳定的绝对行 offset。
    /// 回调返回 false 时供 replay 预检提前结束。
    private static func forEachLine(
        in stream: any JSONLByteStream,
        _ body: (Data, UInt64) -> Bool
    ) throws {
        try stream.seek(toOffset: 0)

        let newline: UInt8 = 0x0A
        var buffer = Data()
        var bufferStartOffset: UInt64 = 0
        while true {
            let chunk = try stream.read(upToCount: 64 * 1024)
            if chunk.isEmpty { break }
            buffer.append(chunk)

            var searchStart = buffer.startIndex
            while let newlineIndex = buffer[searchStart..<buffer.endIndex].firstIndex(of: newline) {
                if newlineIndex > searchStart {
                    let relativeOffset = buffer.distance(
                        from: buffer.startIndex,
                        to: searchStart
                    )
                    if !body(
                        Data(buffer[searchStart..<newlineIndex]),
                        bufferStartOffset + UInt64(relativeOffset)
                    ) {
                        return
                    }
                }
                searchStart = buffer.index(after: newlineIndex)
            }

            if searchStart > buffer.startIndex {
                let consumedByteCount = buffer.distance(
                    from: buffer.startIndex,
                    to: searchStart
                )
                buffer.removeSubrange(buffer.startIndex..<searchStart)
                bufferStartOffset += UInt64(consumedByteCount)
            }
        }

        if !buffer.isEmpty {
            _ = body(buffer, bufferStartOffset)
        }
    }

    private static func cacheKey(for url: URL) -> String {
        url.standardizedFileURL.path
    }
}
