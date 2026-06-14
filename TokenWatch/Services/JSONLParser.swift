import Foundation
import os.log

/// 逐行解析 JSONL 文件，提取 assistant 记录中的 usage 数据
///
/// 去重策略：参考 ccusage / TokenTracker 当前实现（TokenTracker rollout.js
/// `claudeMessageDedupKey`），使用 `message.id`（必填）+ `requestId`（可选）
/// 作为 dedup key。Anthropic 协议保证 `message.id` 全局唯一，`requestId`
/// 缺失（DeepSeek/Kimi/Mimo 等兼容端点不返回 `request-id` header）时不应短路。
final class JSONLParser: Sendable {

    private let logger = Logger(subsystem: "com.xiaoao.TokenWatch", category: "JSONLParser")

    /// 解析单个 JSONL 文件，提取所有包含 usage 的 assistant 记录
    /// - Parameters:
    ///   - fileInfo: 文件信息
    ///   - claudeDataRoot: ~/.claude 目录 URL（确保 Security-Scoped 访问有效）
    /// - Returns: 解析后的用量条目列表（未去重，由 `parseAllFiles` 统一处理）
    nonisolated func parseJSONLFile(_ fileInfo: JSONLFileInfo, claudeDataRoot: URL) throws -> [ParsedUsageEntry] {
        let content = try String(contentsOf: fileInfo.url, encoding: .utf8)
        let lines = content.split(separator: "\n", omittingEmptySubsequences: true)

        var entries: [ParsedUsageEntry] = []
        var skippedNoMessageId = 0
        let decoder = JSONDecoder()

        for line in lines {
            guard let data = String(line).data(using: .utf8) else { continue }

            guard let record = try? decoder.decode(ClaudeRecord.self, from: data),
                  record.hasUsageData,
                  let message = record.message,
                  let usage = message.usage,
                  let model = message.model
            else {
                continue
            }

            // message.id 是 dedup 主键，缺失则无法可靠去重，直接丢弃
            // 真实 Claude Code 数据该字段必定存在；缺失通常意味着上游异常或非标准格式
            let messageId = message.id
            guard !messageId.isEmpty else {
                skippedNoMessageId += 1
                continue
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
                isSubagent: fileInfo.isSubagent
            ))
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
    nonisolated func parseAllFiles(_ files: [JSONLFileInfo], claudeDataRoot: URL) throws -> [ParsedUsageEntry] {
        var allEntries: [ParsedUsageEntry] = []

        for fileInfo in files {
            let entries = try parseJSONLFile(fileInfo, claudeDataRoot: claudeDataRoot)
            allEntries.append(contentsOf: entries)
        }

        logger.info("解析完成：\(allEntries.count) 条记录（去重前）")

        // 按 dedupKey 去重；同一 messageId 出现多次时保留首条
        var seen = Set<String>()
        var uniqueEntries: [ParsedUsageEntry] = []
        uniqueEntries.reserveCapacity(allEntries.count)
        for entry in allEntries where seen.insert(entry.dedupKey).inserted {
            uniqueEntries.append(entry)
        }

        let duplicateCount = allEntries.count - uniqueEntries.count
        if duplicateCount > 0 {
            logger.info("去重完成：移除 \(duplicateCount) 条重复记录，剩余 \(uniqueEntries.count) 条")
        }

        return uniqueEntries
    }
}
