import Foundation
import os.log

/// 流式解析 Claude direct / AgentProgress billing 行，并在批量入口统一执行 daily 去重。
final class ClaudeJSONLParser: @unchecked Sendable {

    private typealias ClaudeFileState = IncrementalJSONLFileState<
        ParsedUsageEntry,
        StatelessJSONLCheckpoint
    >

    private let logger = Logger(subsystem: "com.xiaoao.TokenWatch", category: "ClaudeJSONLParser")
    private let fileReader: any JSONLFileReading
    private let cacheCoordinator: JSONLLastGoodCacheCoordinator<
        ClaudeFileState,
        JSONLUnscopedCacheScope
    >

    init(fileReader: any JSONLFileReading = SystemJSONLFileReader()) {
        self.fileReader = fileReader
        self.cacheCoordinator = JSONLLastGoodCacheCoordinator<
            ClaudeFileState,
            JSONLUnscopedCacheScope
        >(fileReader: fileReader)
    }

    var debugCachedFileCount: Int {
        cacheCoordinator.debugCachedFileCount
    }

    var debugCacheHitCount: Int {
        cacheCoordinator.debugCacheHitCount
    }

    func debugCommittedOffset(for url: URL) -> UInt64? {
        cacheCoordinator.cachedState(
            for: Self.cacheKey(for: url),
            scope: .shared
        )?.committedOffset
    }

    func debugContinuityAnchor(for url: URL) -> JSONLContinuityAnchor? {
        cacheCoordinator.cachedState(
            for: Self.cacheKey(for: url),
            scope: .shared
        )?.continuityAnchor
    }

    /// 解析单个 JSONL 文件，返回尚未执行跨文件去重的 billing candidates。
    /// - Parameters:
    ///   - fileInfo: 文件信息。
    ///   - claudeDataRoot: ~/.claude 目录 URL（确保 Security-Scoped 访问有效）。
    /// - Returns: 解析后的用量条目列表（未去重，由 `parseAllFiles` 统一处理）。
    func parseJSONLFile(
        _ fileInfo: ClaudeJSONLFileInfo,
        claudeDataRoot: URL
    ) throws -> [ParsedUsageEntry] {
        let snapshot = try fileReader.openSnapshot(for: fileInfo.url)
        defer { snapshot.stream.close() }
        return try parseJSONLStream(
            snapshot.stream,
            fileInfo: fileInfo,
            claudeDataRoot: claudeDataRoot
        )
    }

    /// 批量收集 per-file candidates，并执行一次 daily exact/sidechain 全局去重。
    /// - Parameters:
    ///   - files: 文件信息列表。
    ///   - claudeDataRoot: ~/.claude 目录 URL。
    /// - Returns: 去重后的用量条目列表。
    func parseAllFiles(
        _ files: [ClaudeJSONLFileInfo],
        claudeDataRoot: URL
    ) throws -> [ParsedUsageEntry] {
        let allCandidates: [ParsedUsageEntry] = cacheCoordinator.loadListedFiles(
            files,
            scope: .shared,
            cacheKey: { Self.cacheKey(for: $0.url) },
            urlForFile: { $0.url },
            build: { [self] fileInfo, snapshot, previous in
                try buildClaudeState(
                    fileInfo: fileInfo,
                    snapshot: snapshot,
                    previous: previous
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

        logger.info("解析完成：\(allCandidates.count) 条记录（去重前）")
        let uniqueEntries = ClaudeUsageDeduplicator.deduplicate(allCandidates)
        let duplicateCount = allCandidates.count - uniqueEntries.count
        if duplicateCount > 0 {
            logger.info("去重完成：移除 \(duplicateCount) 条重复记录，剩余 \(uniqueEntries.count) 条")
        }
        return uniqueEntries
    }

    /// 从已打开 stream 的起点分块解析完整文件，并保留每行绝对 byte offset。
    private func parseJSONLStream(
        _ stream: any JSONLByteStream,
        fileInfo: ClaudeJSONLFileInfo,
        claudeDataRoot: URL
    ) throws -> [ParsedUsageEntry] {
        // 访问权限由调用方以 data root 生命周期维持；参数保留公开 API 的授权边界。
        _ = claudeDataRoot
        try stream.seek(toOffset: 0)

        var candidates: [ParsedUsageEntry] = []
        let decoder = JSONDecoder()
        let newline: UInt8 = 0x0A
        var buffer = Data()
        var bufferStartOffset: UInt64 = 0
        let chunkSize = 64 * 1024

        let processLine: (Data, UInt64) -> Void = { [self] lineData, lineStartOffset in
            if let candidate = parseCandidate(
                lineData,
                fileInfo: fileInfo,
                sourceOffset: lineStartOffset,
                decoder: decoder
            ) {
                candidates.append(candidate)
            }
        }

        while true {
            let chunk = try stream.read(upToCount: chunkSize)
            if chunk.isEmpty { break }
            buffer.append(chunk)

            var searchStart = buffer.startIndex
            while let newlineIndex = buffer[searchStart..<buffer.endIndex].firstIndex(of: newline) {
                let relativeOffset = buffer.distance(
                    from: buffer.startIndex,
                    to: searchStart
                )
                processLine(
                    Data(buffer[searchStart..<newlineIndex]),
                    bufferStartOffset + UInt64(relativeOffset)
                )
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
            processLine(buffer, bufferStartOffset)
        }
        return candidates
    }

    /// 根据当前 descriptor snapshot 与同 scope previous state 构建下一版文件状态。
    /// append 只有在 continuity anchor 覆盖并匹配完整 committed prefix 后才复用。
    private func buildClaudeState(
        fileInfo: ClaudeJSONLFileInfo,
        snapshot: JSONLFileSnapshot,
        previous: ClaudeFileState?
    ) throws -> ClaudeFileState {
        func rebuild() throws -> ClaudeFileState {
            try readCandidates(
                from: fileInfo,
                snapshot: snapshot,
                startOffset: 0,
                stablePrefix: [],
                previousAnchor: .empty
            )
        }

        guard let previous else { return try rebuild() }
        switch IncrementalJSONLTransition.decide(
            previous: previous,
            newMetadata: snapshot.metadata
        ) {
        case .reuse:
            return previous
        case .append(let startOffset):
            let anchorCoversCommittedPrefix = previous.continuityAnchor.offset == 0
                && UInt64(previous.continuityAnchor.bytes.count)
                    == previous.committedOffset
            guard anchorCoversCommittedPrefix,
                  try previous.continuityAnchor.matches(in: snapshot.stream) else {
                return try rebuild()
            }
            return try readCandidates(
                from: fileInfo,
                snapshot: snapshot,
                startOffset: startOffset,
                stablePrefix: previous.stableCandidates,
                previousAnchor: previous.continuityAnchor
            )
        case .rebuild:
            return try rebuild()
        }
    }

    /// 读取 snapshot metadata.size 内的字节，只在完整换行后推进 committed state。
    /// EOF 尾段只生成 provisional candidate，下一次 append 会从 committed offset 重读。
    private func readCandidates(
        from fileInfo: ClaudeJSONLFileInfo,
        snapshot: JSONLFileSnapshot,
        startOffset: UInt64,
        stablePrefix: [ParsedUsageEntry],
        previousAnchor: JSONLContinuityAnchor
    ) throws -> ClaudeFileState {
        try snapshot.stream.seek(toOffset: startOffset)

        var stableCandidates = stablePrefix
        var committedOffset = startOffset
        var nextReadOffset = startOffset
        var buffer = Data()
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
                if let candidate = parseCandidate(
                    Data(buffer[searchStart..<newlineIndex]),
                    fileInfo: fileInfo,
                    sourceOffset: committedOffset + UInt64(relativeOffset),
                    decoder: decoder
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
                committedOffset += UInt64(consumedByteCount)
                continuityAnchor = .make(
                    previous: continuityAnchor,
                    newlyCommittedBytes: Data(buffer[..<searchStart]),
                    committedOffset: committedOffset
                )
                buffer.removeSubrange(buffer.startIndex..<searchStart)
            }
        }

        let provisionalCandidates = parseCandidate(
            buffer,
            fileInfo: fileInfo,
            sourceOffset: committedOffset,
            decoder: decoder
        ).map { [$0] } ?? []
        return ClaudeFileState(
            metadata: snapshot.metadata,
            committedOffset: committedOffset,
            stableCandidates: stableCandidates,
            provisionalTail: buffer,
            provisionalCandidates: provisionalCandidates,
            continuityAnchor: continuityAnchor,
            checkpointAtCommittedOffset: StatelessJSONLCheckpoint()
        )
    }

    /// 解析单条 Claude billing 行；缺失 source ID 时使用文件 key 与绝对 offset。
    private func parseCandidate(
        _ lineData: Data,
        fileInfo: ClaudeJSONLFileInfo,
        sourceOffset: UInt64,
        decoder: JSONDecoder
    ) -> ParsedUsageEntry? {
        guard !lineData.isEmpty,
              ClaudeUsageLine.passesRawPrefilter(lineData),
              let usageLine = try? decoder.decode(ClaudeUsageLine.self, from: lineData),
              let normalized = usageLine.normalized,
              normalized.isValidDailyUsageRecord else {
            return nil
        }

        let fileKey = Self.cacheKey(for: fileInfo.url)
        let recordUUID = normalized.recordUUID
            ?? "missing-record:\(fileKey):\(sourceOffset)"
        let messageID = normalized.messageID
            ?? "missing-message:\(fileKey):\(sourceOffset)"
        return ParsedUsageEntry(
            recordUUID: recordUUID,
            messageId: messageID,
            requestId: normalized.requestID,
            sessionID: normalized.sessionID ?? fileInfo.sessionID,
            timestamp: normalized.timestamp,
            model: normalized.model ?? "",
            cwd: normalized.cwd,
            agentId: fileInfo.agentId,
            usage: normalized.usage.tokenUsage,
            isSubagent: fileInfo.isSubagent,
            isSidechain: normalized.isSidechain,
            hasSourceMessageID: normalized.messageID != nil,
            provider: .claude,
            upstreamProviderID: nil,
            upstreamCost: normalized.costUSD
        )
    }

    private static func cacheKey(for url: URL) -> String {
        url.standardizedFileURL.path
    }
}
