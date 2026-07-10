import Foundation
import os.log

/// 流式解析 Claude direct / AgentProgress billing 行，并在批量入口统一执行 daily 去重。
final class ClaudeJSONLParser: @unchecked Sendable {

    private let logger = Logger(subsystem: "com.xiaoao.TokenWatch", category: "ClaudeJSONLParser")
    private let fileReader: any JSONLFileReading
    private let cacheCoordinator: JSONLLastGoodCacheCoordinator<
        ParsedUsageEntry,
        JSONLUnscopedCacheScope
    >

    init(fileReader: any JSONLFileReading = SystemJSONLFileReader()) {
        self.fileReader = fileReader
        self.cacheCoordinator = JSONLLastGoodCacheCoordinator<
            ParsedUsageEntry,
            JSONLUnscopedCacheScope
        >(fileReader: fileReader)
    }

    var debugCachedFileCount: Int {
        cacheCoordinator.debugCachedFileCount
    }

    var debugCacheHitCount: Int {
        cacheCoordinator.debugCacheHitCount
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
        let allCandidates = cacheCoordinator.loadListedFiles(
            files,
            scope: .shared,
            cacheKey: { Self.cacheKey(for: $0.url) },
            urlForFile: { $0.url },
            parse: { [self] fileInfo, snapshot in
                try parseJSONLStream(
                    snapshot.stream,
                    fileInfo: fileInfo,
                    claudeDataRoot: claudeDataRoot
                )
            },
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
        let fileKey = Self.cacheKey(for: fileInfo.url)
        var buffer = Data()
        var bufferStartOffset: UInt64 = 0
        let chunkSize = 64 * 1024

        let processLine: (Data, UInt64) -> Void = { lineData, lineStartOffset in
            guard !lineData.isEmpty else { return }
            guard ClaudeUsageLine.passesRawPrefilter(lineData),
                  let usageLine = try? decoder.decode(ClaudeUsageLine.self, from: lineData),
                  let normalized = usageLine.normalized,
                  normalized.isValidDailyUsageRecord else {
                return
            }

            let recordUUID = normalized.recordUUID
                ?? "missing-record:\(fileKey):\(lineStartOffset)"
            let messageID = normalized.messageID
                ?? "missing-message:\(fileKey):\(lineStartOffset)"
            candidates.append(ParsedUsageEntry(
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
            ))
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

    private static func cacheKey(for url: URL) -> String {
        url.standardizedFileURL.path
    }
}
