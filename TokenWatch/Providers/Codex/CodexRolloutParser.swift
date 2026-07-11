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

    private typealias CodexFileState = IncrementalJSONLFileState<
        CodexUsageCandidate,
        CodexParserCheckpoint
    >

    private struct CodexIncrementalState: Sendable {
        let replayClassification: CodexReplayClassification
        let fileState: CodexFileState

        var returnedCandidates: [CodexUsageCandidate] {
            fileState.returnedCandidates
        }
    }

    private let logger = Logger(
        subsystem: "com.xiaoao.TokenWatch",
        category: "CodexRolloutParser"
    )
    private let fileReader: any JSONLFileReading
    private let cacheCoordinator: JSONLLastGoodCacheCoordinator<
        CodexIncrementalState,
        CodexPricingSpeed
    >

    init(fileReader: any JSONLFileReading = SystemJSONLFileReader()) {
        self.fileReader = fileReader
        self.cacheCoordinator = JSONLLastGoodCacheCoordinator<
            CodexIncrementalState,
            CodexPricingSpeed
        >(fileReader: fileReader)
    }

    var debugCachedFileCount: Int {
        cacheCoordinator.debugCachedFileCount
    }

    var debugCacheHitCount: Int {
        cacheCoordinator.debugCacheHitCount
    }

    func debugContinuityAnchor(
        for url: URL,
        pricingSpeed: CodexPricingSpeed = .standard
    ) -> JSONLContinuityAnchor? {
        cacheCoordinator.cachedState(
            for: Self.cacheKey(for: url),
            scope: pricingSpeed
        )?.fileState.continuityAnchor
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
        return try buildCodexState(
            fileInfo: fileInfo,
            snapshot: snapshot,
            previous: nil,
            pricingSpeed: pricingSpeed
        ).returnedCandidates.map(\.entry)
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
            build: { [self] fileInfo, snapshot, previous in
                try buildCodexState(
                    fileInfo: fileInfo,
                    snapshot: snapshot,
                    previous: previous,
                    pricingSpeed: pricingSpeed
                )
            },
            project: \.returnedCandidates,
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
        for candidate in allCandidates
        where seen.insert(candidate.dedupKey).inserted {
            entries.append(candidate.entry)
        }
        return entries
    }

    /// 根据 descriptor snapshot、replay 分类与同 scope previous 构建下一版状态。
    private func buildCodexState(
        fileInfo: CodexRolloutFileInfo,
        snapshot: JSONLFileSnapshot,
        previous: CodexIncrementalState?,
        pricingSpeed: CodexPricingSpeed
    ) throws -> CodexIncrementalState {
        let previousFileState = previous?.fileState
        let contentTransition = previousFileState.map {
            IncrementalJSONLTransition.decide(
                previous: $0,
                newMetadata: snapshot.metadata
            )
        } ?? .rebuild

        let anchorMatches: Bool
        if case .append = contentTransition, let previousFileState {
            let anchor = previousFileState.continuityAnchor
            let anchorCoversCommittedPrefix = anchor.offset == 0
                && UInt64(anchor.bytes.count)
                    == previousFileState.committedOffset
            if anchorCoversCommittedPrefix {
                anchorMatches = try anchor.matches(in: snapshot.stream)
            } else {
                anchorMatches = false
            }
        } else {
            anchorMatches = false
        }

        let contentCanReuseClassification: Bool
        switch contentTransition {
        case .reuse:
            contentCanReuseClassification = true
        case .append:
            contentCanReuseClassification = anchorMatches
        case .rebuild:
            contentCanReuseClassification = false
        }

        let replayClassification: CodexReplayClassification
        if let previous,
           contentCanReuseClassification,
           previous.replayClassification != .pending {
            replayClassification = previous.replayClassification
        } else {
            replayClassification = try CodexReplayDetector.classify(
                snapshot: snapshot
            )
        }
        let replaySecond = replayClassification.replaySecond

        let reusableFileState: CodexFileState?
        if let previousFileState,
           contentCanReuseClassification,
           previousFileState.checkpointAtCommittedOffset.replaySecond
                == replaySecond {
            reusableFileState = previousFileState
        } else {
            reusableFileState = nil
        }

        let effectiveTransition: IncrementalJSONLTransition =
            reusableFileState == nil ? .rebuild : contentTransition
        let fileState = try buildCodexFileState(
            fileInfo: fileInfo,
            snapshot: snapshot,
            previous: reusableFileState,
            transition: effectiveTransition,
            replaySecond: replaySecond,
            pricingSpeed: pricingSpeed
        )
        return CodexIncrementalState(
            replayClassification: replayClassification,
            fileState: fileState
        )
    }

    /// 选择复用 committed checkpoint、后缀读取，或从文件起点重建。
    private func buildCodexFileState(
        fileInfo: CodexRolloutFileInfo,
        snapshot: JSONLFileSnapshot,
        previous: CodexFileState?,
        transition: IncrementalJSONLTransition,
        replaySecond: String?,
        pricingSpeed: CodexPricingSpeed
    ) throws -> CodexFileState {
        switch transition {
        case .reuse:
            return previous!
        case .append(let startOffset):
            return try readState(
                snapshot: snapshot,
                startOffset: startOffset,
                stablePrefix: previous!.stableCandidates,
                checkpoint: previous!.checkpointAtCommittedOffset,
                previousAnchor: previous!.continuityAnchor,
                pricingSpeed: pricingSpeed
            )
        case .rebuild:
            return try readState(
                snapshot: snapshot,
                startOffset: 0,
                stablePrefix: [],
                checkpoint: .initial(
                    sessionID: fileInfo.sessionID,
                    replaySecond: replaySecond
                ),
                previousAnchor: .empty,
                pricingSpeed: pricingSpeed
            )
        }
    }

    /// 读取 metadata.size 内的字节；完整换行才推进 offset、anchor 与 checkpoint。
    /// EOF 尾段只使用 checkpoint 副本生成 provisional candidate。
    private func readState(
        snapshot: JSONLFileSnapshot,
        startOffset: UInt64,
        stablePrefix: [CodexUsageCandidate],
        checkpoint: CodexParserCheckpoint,
        previousAnchor: JSONLContinuityAnchor,
        pricingSpeed: CodexPricingSpeed
    ) throws -> CodexFileState {
        try snapshot.stream.seek(toOffset: startOffset)

        var stableCandidates = stablePrefix
        var committedCheckpoint = checkpoint
        var buffer = Data()
        var bufferStartOffset = startOffset
        var nextReadOffset = startOffset
        var continuityAnchor = previousAnchor
        let decoder = JSONDecoder()
        let newline: UInt8 = 0x0A
        let chunkSize = 64 * 1024

        while nextReadOffset < snapshot.metadata.size {
            let remainingByteCount = snapshot.metadata.size - nextReadOffset
            let count = Int(min(UInt64(chunkSize), remainingByteCount))
            let chunk = try snapshot.stream.read(upToCount: count)
            guard !chunk.isEmpty else {
                throw IncrementalJSONLReadError.unexpectedEOF
            }
            nextReadOffset += UInt64(chunk.count)
            buffer.append(chunk)

            var searchStart = buffer.startIndex
            while let newlineIndex = buffer[searchStart..<buffer.endIndex]
                .firstIndex(of: newline) {
                let relativeOffset = buffer.distance(
                    from: buffer.startIndex,
                    to: searchStart
                )
                if let record = parseRecord(
                    Data(buffer[searchStart..<newlineIndex]),
                    decoder: decoder
                ), let candidate = committedCheckpoint.consume(
                    record,
                    sourceOffset: bufferStartOffset + UInt64(relativeOffset),
                    pricingSpeed: pricingSpeed
                ) {
                    stableCandidates.append(candidate)
                }
                searchStart = buffer.index(after: newlineIndex)
            }

            if searchStart > buffer.startIndex {
                let consumedByteCount = buffer.distance(
                    from: buffer.startIndex,
                    to: searchStart
                )
                let newlyCommittedBytes = Data(buffer[..<searchStart])
                bufferStartOffset += UInt64(consumedByteCount)
                continuityAnchor = .make(
                    previous: continuityAnchor,
                    newlyCommittedBytes: newlyCommittedBytes,
                    committedOffset: bufferStartOffset
                )
                buffer.removeSubrange(buffer.startIndex..<searchStart)
            }
        }

        var provisionalCheckpoint = committedCheckpoint
        let provisionalCandidates = parseRecord(
            buffer,
            decoder: decoder
        ).flatMap {
            provisionalCheckpoint.consume(
                $0,
                sourceOffset: bufferStartOffset,
                pricingSpeed: pricingSpeed
            )
        }.map { [$0] } ?? []

        return CodexFileState(
            metadata: snapshot.metadata,
            committedOffset: bufferStartOffset,
            stableCandidates: stableCandidates,
            provisionalTail: buffer,
            provisionalCandidates: provisionalCandidates,
            continuityAnchor: continuityAnchor,
            checkpointAtCommittedOffset: committedCheckpoint
        )
    }

    /// 解码非空单行；无效行仍由读取循环作为 committed bytes 推进。
    private func parseRecord(
        _ lineData: Data,
        decoder: JSONDecoder
    ) -> CodexRecord? {
        guard !lineData.isEmpty else { return nil }
        return try? decoder.decode(CodexRecord.self, from: lineData)
    }

    private static func cacheKey(for url: URL) -> String {
        url.standardizedFileURL.path
    }
}

/// 在同一 descriptor snapshot 内执行 Codex replay 预检。
private enum CodexReplayDetector {
    /// 仅在前 16 KiB 含 thread/fork marker 时比较前两条有效 usage 的规范化秒。
    static func classify(
        snapshot: JSONLFileSnapshot
    ) throws -> CodexReplayClassification {
        guard try hasReplayMarker(snapshot: snapshot) else {
            return .notReplay
        }

        let decoder = JSONDecoder()
        var firstSecond: String?
        var result: CodexReplayClassification = .pending
        try forEachLine(in: snapshot) { lineData in
            guard let record = try? decoder.decode(
                CodexRecord.self,
                from: lineData
            ), case let .eventMsg(event) = record.payload,
              event.type == "token_count",
              event.info?.lastTokenUsage != nil
                || event.info?.totalTokenUsage != nil,
              let timestamp = record.normalizedTimestamp,
              let second = timestampSecond(timestamp.key) else {
                return true
            }
            guard let firstSecond else {
                firstSecond = second
                return true
            }
            result = firstSecond == second
                ? .replay(second: second)
                : .notReplay
            return false
        }
        return result
    }

    private static func hasReplayMarker(
        snapshot: JSONLFileSnapshot
    ) throws -> Bool {
        try snapshot.stream.seek(toOffset: 0)
        let limit = Int(min(UInt64(16 * 1024), snapshot.metadata.size))
        var prefix = Data()
        while prefix.count < limit {
            let chunk = try snapshot.stream.read(
                upToCount: limit - prefix.count
            )
            guard !chunk.isEmpty else {
                throw IncrementalJSONLReadError.unexpectedEOF
            }
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

    /// 在 snapshot metadata.size 范围内逐行遍历，允许 replay 判定提前结束。
    private static func forEachLine(
        in snapshot: JSONLFileSnapshot,
        _ body: (Data) -> Bool
    ) throws {
        try snapshot.stream.seek(toOffset: 0)

        let newline: UInt8 = 0x0A
        let chunkSize = 64 * 1024
        var nextReadOffset: UInt64 = 0
        var buffer = Data()
        while nextReadOffset < snapshot.metadata.size {
            let remainingByteCount = snapshot.metadata.size - nextReadOffset
            let count = Int(min(UInt64(chunkSize), remainingByteCount))
            let chunk = try snapshot.stream.read(upToCount: count)
            guard !chunk.isEmpty else {
                throw IncrementalJSONLReadError.unexpectedEOF
            }
            nextReadOffset += UInt64(chunk.count)
            buffer.append(chunk)

            var searchStart = buffer.startIndex
            while let newlineIndex = buffer[searchStart..<buffer.endIndex]
                .firstIndex(of: newline) {
                if !body(Data(buffer[searchStart..<newlineIndex])) {
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
}
