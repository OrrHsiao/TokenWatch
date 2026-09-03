import Foundation
import os.log

/// 把 Antigravity 会话扫描结果转成统一的 ParsedUsageEntry
final class AntigravityMessageParser: Sendable {

    private let logger = Logger(subsystem: "com.xiaoao.TokenWatch", category: "AntigravityMessageParser")

    /// 批量解析多个会话的原始数据 → ParsedUsageEntry 列表（带去重）
    /// - Parameter scanResults: 从 SQLite 扫描出的各会话原始记录
    /// - Returns: 统一定价和聚合的 ParsedUsageEntry 列表
    func parseAll(_ scanResults: [AntigravityConversationScanResult]) -> [ParsedUsageEntry] {
        var entries: [ParsedUsageEntry] = []
        var seenDedupKeys = Set<String>()

        var totalGenerations = 0
        var skippedMissingPayload = 0
        var skippedMissingTokens = 0
        var skippedAllZero = 0
        var skippedDuplicates = 0

        for result in scanResults {
            for row in result.generations {
                totalGenerations += 1

                guard let payload = AntigravityProtoReader.decodeGenerationPayload(from: row.dataBlob) else {
                    skippedMissingPayload += 1
                    continue
                }

                guard let usageMeta = payload.usage else {
                    skippedMissingTokens += 1
                    continue
                }

                // 过滤 4 维全 0 条目（失败请求或占位记录）
                let isAllZero = usageMeta.promptTokens == 0 &&
                    usageMeta.cachedContentTokens == 0 &&
                    usageMeta.totalTokens == 0 &&
                    usageMeta.thoughtsTokens == 0

                guard !isAllZero else {
                    skippedAllZero += 1
                    continue
                }

                // 去重标识：优先 request_id，其次 botMessageId，最后由 trajectoryID + genIdx 合成
                let rawMessageId = payload.requestId
                    ?? usageMeta.botMessageId
                    ?? "\(row.trajectoryID):gen_\(row.genIdx)"

                // 会话与时间戳关联：
                // 1. 优先通过 lastStepIndex 查找对应的 steps 执行时间戳；
                // 2. 找不到 exact 时回退至该会话已知 step 的最近时间；
                // 3. 若 stepTimestamps 均缺失，回退至该数据库文件的修改时间。
                var timestamp: Date?
                if let stepIdx = payload.lastStepIndex, let stepDate = result.stepTimestamps[stepIdx] {
                    timestamp = stepDate
                } else if let maxStepDate = result.stepTimestamps.values.max() {
                    timestamp = maxStepDate
                } else {
                    timestamp = (try? result.databaseURL.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
                }

                let modelID = payload.modelID.trimmingCharacters(in: .whitespacesAndNewlines)
                let resolvedModel = modelID.isEmpty ? "gemini-3.8-flash" : modelID

                let usage = TokenUsage(
                    inputTokens: usageMeta.promptTokens,
                    cacheCreationInputTokens: 0,
                    cacheReadInputTokens: usageMeta.cachedContentTokens,
                    outputTokens: usageMeta.totalTokens,
                    reasoningTokens: usageMeta.thoughtsTokens,
                    serverToolUse: ServerToolUse(webSearchRequests: 0, webFetchRequests: 0),
                    serviceTier: "",
                    cacheCreation: nil,
                    inferenceGeo: "",
                    iterations: [],
                    speed: ""
                )

                let entry = ParsedUsageEntry(
                    recordUUID: UUID().uuidString,
                    messageId: rawMessageId,
                    requestId: payload.requestId,
                    sessionID: payload.trajectoryId ?? result.conversationID,
                    timestamp: timestamp,
                    model: resolvedModel,
                    upstreamModelID: nil,
                    cwd: result.workspacePath,
                    agentId: nil,
                    usage: usage,
                    isSubagent: false,
                    isSidechain: false,
                    hasSourceMessageID: payload.requestId != nil || usageMeta.botMessageId != nil,
                    provider: .antigravity,
                    upstreamProviderID: "google",
                    upstreamCost: nil
                )

                if seenDedupKeys.insert(entry.dedupKey).inserted {
                    entries.append(entry)
                } else {
                    skippedDuplicates += 1
                }
            }
        }

        if skippedMissingPayload + skippedMissingTokens + skippedAllZero + skippedDuplicates > 0 {
            logger.info("Antigravity 解析汇总 — 总生成数:\(totalGenerations), 成功:\(entries.count), 缺负载:\(skippedMissingPayload), 缺用量:\(skippedMissingTokens), 全零:\(skippedAllZero), 重复:\(skippedDuplicates)")
        }

        return entries
    }
}
