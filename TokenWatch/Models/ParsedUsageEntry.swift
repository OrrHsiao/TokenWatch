import Foundation

/// 解析后展平的用量条目
/// 参考 ccusage 的 LoadedEntry 设计
///
/// 去重策略：复合键 = `messageId` 必填，`requestId` 可选拼接
/// 依据 Anthropic 协议，`message.id` 全局唯一可作 dedup key；
/// 旧版 ccusage / TokenTracker 强制要求 `requestId` 导致 DeepSeek/Kimi 等
/// 不返回 `request-id` HTTP header 的 provider 出现 1.6-3.7× 多计
/// （TokenTracker issue #64），因此这里 `requestId` 仅作可选拼接而非必要条件。
struct ParsedUsageEntry: Sendable, Hashable {
    let recordUUID: String
    let messageId: String          // assistant 消息全局唯一 ID（dedup 主键）
    let requestId: String?         // HTTP request-id，缺失不影响 dedup
    let sessionID: String
    let timestamp: Date?
    let model: String
    let cwd: String?
    let agentId: String?
    let usage: TokenUsage
    let isSubagent: Bool

    /// 去重键：`messageId` 或 `messageId:requestId`
    /// 两种格式可共存于同一 Set（messageId 不含冒号，无碰撞风险）
    var dedupKey: String {
        if let reqId = requestId, !reqId.isEmpty {
            return "\(messageId):\(reqId)"
        }
        return messageId
    }

    nonisolated func hash(into hasher: inout Hasher) {
        hasher.combine(dedupKey)
    }

    nonisolated static func == (lhs: ParsedUsageEntry, rhs: ParsedUsageEntry) -> Bool {
        lhs.dedupKey == rhs.dedupKey
    }
}
