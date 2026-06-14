import Foundation
import os.log

/// 逐行解析 JSONL 文件，提取 assistant 记录中的 usage 数据
/// 参考 ccusage 的解析逻辑 + TokenTracker 的复合键去重策略
final class JSONLParser: Sendable {

    private let logger = Logger(subsystem: "com.xiaoao.TokenWatch", category: "JSONLParser")

    /// 解析单个 JSONL 文件，提取所有包含 usage 的 assistant 记录
    /// - Parameters:
    ///   - fileInfo: 文件信息
    ///   - claudeDataRoot: ~/.claude 目录 URL（确保 Security-Scoped 访问有效）
    /// - Returns: 解析后的用量条目列表（已去重）
    nonisolated func parseJSONLFile(_ fileInfo: JSONLFileInfo, claudeDataRoot: URL) throws -> [ParsedUsageEntry] {
        let content = try String(contentsOf: fileInfo.url, encoding: .utf8)
        let lines = content.split(separator: "\n", omittingEmptySubsequences: true)

        var entries: [ParsedUsageEntry] = []
        let decoder = JSONDecoder()

        for line in lines {
            guard let data = String(line).data(using: .utf8) else { continue }

            guard let record = try? decoder.decode(ClaudeRecord.self, from: data),
                  record.hasUsageData,
                  let usage = record.message?.usage,
                  let model = record.message?.model
            else {
                continue
            }

            entries.append(ParsedUsageEntry(
                recordUUID: record.uuid,
                sessionID: record.sessionId,
                timestamp: record.timestamp,
                model: model,
                cwd: record.cwd,
                agentId: fileInfo.agentId,
                usage: usage,
                isSubagent: fileInfo.isSubagent
            ))
        }

        return entries
    }

    /// 批量解析所有 JSONL 文件并去重
    /// 去重策略参考 TokenTracker：
    ///   使用复合键 (sessionID + timestamp + model + inputTokens + outputTokens)
    ///   避免因 DeepSeek 等模型缺少 reqId 导致的 1.6-3.7x 多计
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

        // 使用 Set 按复合键去重
        let uniqueEntries = Array(Set(allEntries))

        let duplicateCount = allEntries.count - uniqueEntries.count
        if duplicateCount > 0 {
            logger.info("去重完成：移除 \(duplicateCount) 条重复记录，剩余 \(uniqueEntries.count) 条")
        }

        return uniqueEntries
    }
}
