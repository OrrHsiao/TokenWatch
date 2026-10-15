import Foundation
import os.log

/// 把 OpenCodeMessageRow 转成统一的 ParsedUsageEntry
///
/// 字段映射策略(见设计稿"opencode 字段映射"表):
/// - model = "{providerID}/{modelID}"(Q4=b,严格区分上游)
/// - upstreamModelID = 真实 modelID，不继承展示用 provider fallback
/// - modelID / providerID 兼容两种结构:旧版为顶层字段,2.0 为 data.model.{id,providerID}
/// - 角色由 Scanner 决定(row.role):2.0 取 session_message.type,旧版取 data.role
/// - tokens.cache.write → cacheCreationInputTokens 扁平字段(cacheCreation 保持 nil,
///   派生属性 totalCacheCreationTokens 自动 fall through 到扁平字段)
/// - tokens.total 中未被已知类别覆盖的余量 → outputTokens
/// - data.cost > 0 → authoritative upstreamCost；其余交给本地定价
/// - 跳过条件:role != assistant / tokens 缺失 / 可计费 token 全 0
final class OpenCodeMessageParser: Sendable {

    private let logger = Logger(subsystem: "com.xiaoao.TokenWatch", category: "OpenCodeMessageParser")

    /// 批量解析行 → 统一条目(messageId 由 SQLite PK 保证全局唯一,无需再去重)
    func parseAll(_ rows: [OpenCodeMessageRow]) -> [ParsedUsageEntry] {
        let decoder = JSONDecoder()
        var entries: [ParsedUsageEntry] = []
        var skippedNotAssistant = 0
        var skippedMissingTokens = 0
        var skippedAllZero = 0
        var skippedDecodeFailed = 0

        for row in rows {
            guard let dataBytes = row.dataJSON.data(using: .utf8) else {
                skippedDecodeFailed += 1
                continue
            }
            let parsed: OpenCodeMessageData
            do {
                parsed = try decoder.decode(OpenCodeMessageData.self, from: dataBytes)
            } catch {
                skippedDecodeFailed += 1
                continue
            }

            // 角色已由 Scanner 按行类型过滤,这里再守卫一次
            guard row.role == "assistant" else {
                skippedNotAssistant += 1
                continue
            }
            guard let tokens = parsed.tokens else {
                skippedMissingTokens += 1
                continue
            }
            guard !tokens.isAllZero else {
                skippedAllZero += 1
                continue
            }

            let usage = TokenUsage(
                inputTokens: tokens.input,
                cacheCreationInputTokens: tokens.cache.write,
                cacheReadInputTokens: tokens.cache.read,
                outputTokens: tokens.billableOutputTokens,
                reasoningTokens: tokens.reasoning,
                serverToolUse: ServerToolUse(webSearchRequests: 0, webFetchRequests: 0),
                serviceTier: "",
                cacheCreation: nil,
                inferenceGeo: "",
                iterations: [],
                speed: ""
            )

            // 2.0 把模型收进了 data.model 对象,旧版是顶层字段;优先顶层,保持旧数据的行为不变
            let providerID = parsed.providerID ?? parsed.model?.providerID
            let modelID = parsed.modelID ?? parsed.model?.id

            // model = "{providerID}/{modelID}",任一缺失则降级展示
            let modelKey: String
            switch (providerID, modelID) {
            case let (p?, m?): modelKey = "\(p)/\(m)"
            case (_, let m?):  modelKey = m
            case (let p?, _):  modelKey = p
            default:           modelKey = "unknown"
            }

            // cwd:优先 data.path.cwd,否则 session.directory
            let cwd = parsed.path?.cwd ?? row.directory

            // OpenCode provider-specific 规则：只有严格大于 0 的 cost 才 authoritative；
            // 0 与缺失都保持 nil，让 UsageCostResolver 尝试本地 token 计价。
            let upstreamCost: Double? = parsed.cost.flatMap { $0 > 0 ? $0 : nil }

            entries.append(ParsedUsageEntry(
                recordUUID: row.id,
                messageId: row.id,
                requestId: nil,
                sessionID: row.sessionID,
                timestamp: Date(timeIntervalSince1970: TimeInterval(row.timeCreatedMs) / 1000.0),
                model: modelKey,
                upstreamModelID: modelID,
                cwd: cwd,
                agentId: nil,
                usage: usage,
                isSubagent: false,
                provider: .opencode,
                upstreamProviderID: providerID,
                upstreamCost: upstreamCost
            ))
        }

        if skippedNotAssistant + skippedMissingTokens + skippedAllZero + skippedDecodeFailed > 0 {
            logger.info("opencode 解析跳过 — notAssistant:\(skippedNotAssistant) missingTokens:\(skippedMissingTokens) allZero:\(skippedAllZero) decodeFailed:\(skippedDecodeFailed)")
        }
        return entries
    }
}
