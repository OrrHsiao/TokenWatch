import Foundation
import os.log

/// 把 OpenCodeMessageRow 转成统一的 ParsedUsageEntry
///
/// 字段映射策略(见设计稿"opencode 字段映射"表):
/// - model = "{providerID}/{modelID}"(Q4=b,严格区分上游)
/// - tokens.cache.write → cacheCreationInputTokens 扁平字段(cacheCreation 保持 nil,
///   派生属性 totalCacheCreationTokens 自动 fall through 到扁平字段)
/// - data.cost → upstreamCost(USD,作 PricingEngine miss 的 fallback)
/// - 跳过条件:role != assistant / tokens 缺失 / 5 维全 0 placeholder
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

            // 双保险:query 已过滤 role=assistant
            guard parsed.role == "assistant" else {
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
                outputTokens: tokens.output,
                reasoningTokens: tokens.reasoning,
                serverToolUse: ServerToolUse(webSearchRequests: 0, webFetchRequests: 0),
                serviceTier: "",
                cacheCreation: nil,
                inferenceGeo: "",
                iterations: [],
                speed: ""
            )

            // model = "{providerID}/{modelID}",任一缺失则降级展示
            let modelKey: String
            switch (parsed.providerID, parsed.modelID) {
            case let (p?, m?): modelKey = "\(p)/\(m)"
            case (_, let m?):  modelKey = m
            case (let p?, _):  modelKey = p
            default:           modelKey = "unknown"
            }

            // cwd:优先 data.path.cwd,否则 session.directory
            let cwd = parsed.path?.cwd ?? row.directory

            // upstreamCost:0 视为缺省(opencode 算不出会写 0)
            let upstreamCost: Double? = parsed.cost.flatMap { $0 > 0 ? $0 : nil }

            entries.append(ParsedUsageEntry(
                recordUUID: row.id,
                messageId: row.id,
                requestId: nil,
                sessionID: row.sessionID,
                timestamp: Date(timeIntervalSince1970: TimeInterval(row.timeCreatedMs) / 1000.0),
                model: modelKey,
                cwd: cwd,
                agentId: nil,
                usage: usage,
                isSubagent: false,
                provider: .opencode,
                upstreamProviderID: parsed.providerID,
                upstreamCost: upstreamCost
            ))
        }

        if skippedNotAssistant + skippedMissingTokens + skippedAllZero + skippedDecodeFailed > 0 {
            logger.info("opencode 解析跳过 — notAssistant:\(skippedNotAssistant) missingTokens:\(skippedMissingTokens) allZero:\(skippedAllZero) decodeFailed:\(skippedDecodeFailed)")
        }
        return entries
    }
}
