import Foundation
import os.log

/// 逐行解析 JSONL 文件，提取 assistant 记录中的 usage 数据
///
/// 去重策略：参考 ccusage / TokenTracker 当前实现（TokenTracker rollout.js
/// `claudeMessageDedupKey`），使用 `message.id`（必填）+ `requestId`（可选）
/// 作为 dedup key。Anthropic 协议保证 `message.id` 全局唯一，`requestId`
/// 缺失（DeepSeek/Kimi/Mimo 等兼容端点不返回 `request-id` header）时不应短路。
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
        let entries: [ParsedUsageEntry]
    }

    /// 解析单个 JSONL 文件，提取所有包含 usage 的 assistant 记录
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

        var entries: [ParsedUsageEntry] = []
        var skippedNoMessageId = 0
        let decoder = JSONDecoder()
        let newline: UInt8 = 0x0A

        // 跨块残段缓冲：每次读完一块后，最后一段未遇到 '\n' 的字节会拼接到下一块
        // 开头继续累积，确保跨 chunk 的长行能被完整还原。
        var buffer = Data()
        let chunkSize = 64 * 1024

        // 闭包：解析单行 Data 并按需 append 到 entries（空行直接跳过）
        let processLine: (Data) -> Void = { lineData in
            guard !lineData.isEmpty else { return }

            guard let record = try? decoder.decode(ClaudeRecord.self, from: lineData),
                  record.hasUsageData,
                  let message = record.message,
                  let usage = message.usage,
                  let model = message.model
            else {
                return
            }

            // message.id 是 dedup 主键，缺失则无法可靠去重，直接丢弃
            // 真实 Claude Code 数据该字段必定存在；缺失通常意味着上游异常或非标准格式
            let messageId = message.id
            guard !messageId.isEmpty else {
                skippedNoMessageId += 1
                return
            }

            entries.append(ParsedUsageEntry(
                recordUUID: record.uuid,
                messageId: messageId,
                requestId: record.requestId,
                sessionID: record.sessionId,
                timestamp: record.timestamp,
                model: model,
                cwd: record.cwd,
                agentId: fileInfo.agentId,
                usage: usage,
                isSubagent: fileInfo.isSubagent,
                provider: .claude,
                upstreamProviderID: nil,
                upstreamCost: record.costUSD
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
                processLine(Data(lineData))
                searchStart = buffer.index(after: nlIndex)
            }

            // 丢弃已处理部分，仅保留最后一段未完成的行，避免缓冲区无限增长
            if searchStart > buffer.startIndex {
                buffer.removeSubrange(buffer.startIndex..<searchStart)
            }
        }

        // 处理文件末尾未以 '\n' 结尾的最后一行残段
        if !buffer.isEmpty {
            processLine(buffer)
        }

        if skippedNoMessageId > 0 {
            logger.warning("文件 \(fileInfo.url.lastPathComponent) 跳过 \(skippedNoMessageId) 条无 message.id 的记录")
        }
        return entries
    }

    /// 批量解析所有 JSONL 文件并按 `messageId[:requestId]` 去重
    /// - Parameters:
    ///   - files: 文件信息列表
    ///   - claudeDataRoot: ~/.claude 目录 URL
    /// - Returns: 去重后的用量条目列表
    func parseAllFiles(_ files: [ClaudeJSONLFileInfo], claudeDataRoot: URL) throws -> [ParsedUsageEntry] {
        var allEntries: [ParsedUsageEntry] = []
        var currentCacheKeys: Set<String> = []

        for fileInfo in files {
            let cacheKey = Self.cacheKey(for: fileInfo.url)
            currentCacheKeys.insert(cacheKey)
            do {
                let entries = try parseCachedJSONLFile(
                    fileInfo,
                    claudeDataRoot: claudeDataRoot,
                    cacheKey: cacheKey
                )
                allEntries.append(contentsOf: entries)
            } catch {
                logger.warning("Claude 文件解析失败: \(fileInfo.url.lastPathComponent) — \(error.localizedDescription)")
            }
        }
        pruneCache(keeping: currentCacheKeys)

        logger.info("解析完成：\(allEntries.count) 条记录（去重前）")

        // 同一 message.id 在 JSONL 中会出现多条记录:
        //   - streaming 过程中的中间 chunk → usage 字段全为 0
        //   - 最终一条 → 携带真实 usage
        //   - 跨文件镜像(subagent / resume)→ usage 完全相同的另一份
        // 旧实现用 Set.insert 保留首条,会先撞上 (0,0,0) 的 chunk 而丢掉真实 usage,
        // 与 ccusage 对比时今日 token 偏低。
        // 修正:同 dedupKey 中保留 token 总量(input + output + cache_read + cache_create)
        // 最大的那条 — 中间 chunk 总量为 0,镜像记录数值相同,均不会替换最完整那条。
        var bestByKey: [String: ParsedUsageEntry] = [:]
        bestByKey.reserveCapacity(allEntries.count)
        for entry in allEntries {
            let key = entry.dedupKey
            if let existing = bestByKey[key] {
                if Self.usageMagnitude(entry.usage) > Self.usageMagnitude(existing.usage) {
                    bestByKey[key] = entry
                }
            } else {
                bestByKey[key] = entry
            }
        }
        let uniqueEntries = Array(bestByKey.values)

        let duplicateCount = allEntries.count - uniqueEntries.count
        if duplicateCount > 0 {
            logger.info("去重完成：移除 \(duplicateCount) 条重复记录，剩余 \(uniqueEntries.count) 条")
        }

        return uniqueEntries
    }

    /// usage 总量,用于在多条同 messageId 记录中挑「最完整」的那条
    /// 流式 chunk 的 usage 全部为 0,真实 usage 必然 > 0,因此取最大即可
    private static func usageMagnitude(_ usage: TokenUsage) -> Int {
        usage.inputTokens
            + usage.outputTokens
            + usage.cacheReadInputTokens
            + usage.totalCacheCreationTokens
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

        let entries = try parseJSONLFile(fileInfo, claudeDataRoot: claudeDataRoot)
        withCacheLock {
            cachedFiles[cacheKey] = CachedFile(signature: signature, entries: entries)
        }
        return entries
    }

    private func cachedFile(for cacheKey: String, matching signature: FileSignature) -> [ParsedUsageEntry]? {
        withCacheLock {
            guard let cached = cachedFiles[cacheKey],
                  cached.signature == signature else {
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
