import Foundation
import os.log

/// 流式解析 Claude direct / AgentProgress billing 行，并在批量入口统一执行 daily 去重。
final class ClaudeJSONLParser: @unchecked Sendable {

    private let logger = Logger(subsystem: "com.xiaoao.TokenWatch", category: "ClaudeJSONLParser")
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
        /// 尚未执行跨文件 global dedup 的 per-file candidates。
        let candidates: [ParsedUsageEntry]
    }

    /// 解析单个 JSONL 文件，返回尚未执行跨文件去重的 billing candidates。
    /// - Parameters:
    ///   - fileInfo: 文件信息
    ///   - claudeDataRoot: ~/.claude 目录 URL（确保 Security-Scoped 访问有效）
    /// - Returns: 解析后的用量条目列表（未去重，由 `parseAllFiles` 统一处理）
    func parseJSONLFile(_ fileInfo: ClaudeJSONLFileInfo, claudeDataRoot: URL) throws -> [ParsedUsageEntry] {
        // Claude Code 单个 session 文件可能达到数百 MB，使用 String(contentsOf:)
        // 全量读入会带来明显的内存峰值与 OOM 风险；改为 FileHandle 64KB 分块流式
        // 读取，按 '\n' 切分成行后逐行 JSON 解码，峰值内存仅与单行长度相关。
        let handle = try FileHandle(forReadingFrom: fileInfo.url)
        defer { try? handle.close() }

        var candidates: [ParsedUsageEntry] = []
        let decoder = JSONDecoder()
        let newline: UInt8 = 0x0A
        let fileKey = Self.cacheKey(for: fileInfo.url)

        // 跨块残段缓冲：每次读完一块后，最后一段未遇到 '\n' 的字节会拼接到下一块
        // 开头继续累积，确保跨 chunk 的长行能被完整还原。
        var buffer = Data()
        var bufferStartOffset: UInt64 = 0
        let chunkSize = 64 * 1024

        // 解析单行并保留其绝对 byte offset，供缺失 ID 时生成稳定的本地 identity。
        let processLine: (Data, UInt64) -> Void = { lineData, lineStartOffset in
            guard !lineData.isEmpty else { return }
            guard ClaudeUsageLine.passesRawPrefilter(lineData),
                  let usageLine = try? decoder.decode(ClaudeUsageLine.self, from: lineData),
                  let normalized = usageLine.normalized,
                  normalized.isValidDailyUsageRecord
            else {
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

        // 流式读取：每次最多读 chunkSize 字节，遇 EOF 时 read 返回空 Data
        while true {
            let chunk = try handle.read(upToCount: chunkSize) ?? Data()
            if chunk.isEmpty { break }
            buffer.append(chunk)

            // 在累积缓冲中按 '\n' 反复切分；剩余未遇到换行的尾段保留到下一轮
            var searchStart = buffer.startIndex
            while let nlIndex = buffer[searchStart..<buffer.endIndex].firstIndex(of: newline) {
                let lineData = buffer[searchStart..<nlIndex]
                let relativeOffset = buffer.distance(from: buffer.startIndex, to: searchStart)
                processLine(
                    Data(lineData),
                    bufferStartOffset + UInt64(relativeOffset)
                )
                searchStart = buffer.index(after: nlIndex)
            }

            // 丢弃已处理部分，仅保留最后一段未完成的行，避免缓冲区无限增长
            if searchStart > buffer.startIndex {
                let consumedByteCount = buffer.distance(
                    from: buffer.startIndex,
                    to: searchStart
                )
                buffer.removeSubrange(buffer.startIndex..<searchStart)
                bufferStartOffset += UInt64(consumedByteCount)
            }
        }

        // 处理文件末尾未以 '\n' 结尾的最后一行残段
        if !buffer.isEmpty {
            processLine(buffer, bufferStartOffset)
        }

        return candidates
    }

    /// 批量收集 per-file candidates，并执行一次 daily exact/sidechain 全局去重。
    /// - Parameters:
    ///   - files: 文件信息列表
    ///   - claudeDataRoot: ~/.claude 目录 URL
    /// - Returns: 去重后的用量条目列表
    func parseAllFiles(_ files: [ClaudeJSONLFileInfo], claudeDataRoot: URL) throws -> [ParsedUsageEntry] {
        var allCandidates: [ParsedUsageEntry] = []
        var currentCacheKeys: Set<String> = []

        for fileInfo in files {
            let cacheKey = Self.cacheKey(for: fileInfo.url)
            currentCacheKeys.insert(cacheKey)
            do {
                let candidates = try parseCachedJSONLFile(
                    fileInfo,
                    claudeDataRoot: claudeDataRoot,
                    cacheKey: cacheKey
                )
                allCandidates.append(contentsOf: candidates)
            } catch {
                logger.warning("Claude 文件解析失败: \(fileInfo.url.lastPathComponent) — \(error.localizedDescription)")
            }
        }
        pruneCache(keeping: currentCacheKeys)

        logger.info("解析完成：\(allCandidates.count) 条记录（去重前）")

        let uniqueEntries = ClaudeUsageDeduplicator.deduplicate(allCandidates)

        let duplicateCount = allCandidates.count - uniqueEntries.count
        if duplicateCount > 0 {
            logger.info("去重完成：移除 \(duplicateCount) 条重复记录，剩余 \(uniqueEntries.count) 条")
        }

        return uniqueEntries
    }

    private func parseCachedJSONLFile(
        _ fileInfo: ClaudeJSONLFileInfo,
        claudeDataRoot: URL,
        cacheKey: String
    ) throws -> [ParsedUsageEntry] {
        let signature = try FileSignature(url: fileInfo.url)
        if let cached = cachedFile(for: cacheKey, matching: signature) {
            return cached
        }

        let candidates = try parseJSONLFile(fileInfo, claudeDataRoot: claudeDataRoot)
        withCacheLock {
            cachedFiles[cacheKey] = CachedFile(
                signature: signature,
                candidates: candidates
            )
        }
        return candidates
    }

    private func cachedFile(for cacheKey: String, matching signature: FileSignature) -> [ParsedUsageEntry]? {
        withCacheLock {
            guard let cached = cachedFiles[cacheKey],
                  cached.signature == signature else {
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
