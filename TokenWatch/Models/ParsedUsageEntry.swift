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
    /// 数据源标识（用于将来跨 provider 合并视图区分来源）
    let provider: ProviderID
    /// opencode 的上游 provider 标识(如 "anthropic" / "huoshan-zijie");Claude/Codex 填 nil
    let upstreamProviderID: String?
    /// 数据源自带的单条 cost(USD)；Auto 模式下只要非 nil 就优先于本地计价。
    /// Claude 可传播显式 0；OpenCode adapter 只传播大于 0 的值。
    let upstreamCost: Double?

    /// 去重键
    /// - Claude:`messageId`(默认)或 `messageId:requestId`(`requestId` 存在时拼接)
    /// - Codex:`<sessionId>:<ISO8601 timestamp>`(无 message.id,Parser 合成)
    /// 两种格式可能都含冒号,但 dedup 在各 provider 自己的 `parseAllFiles` 内独立完成,
    /// 不跨 provider 共享 Set,因此即便字面碰撞也无影响。
    /// 若未来引入跨 provider 合并视图,需在 key 上加 provider 前缀以彻底隔离。
    var dedupKey: String {
        if let reqId = requestId, !reqId.isEmpty {
            return "\(messageId):\(reqId)"
        }
        return messageId
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(dedupKey)
    }

    static func == (lhs: ParsedUsageEntry, rhs: ParsedUsageEntry) -> Bool {
        lhs.dedupKey == rhs.dedupKey
    }
}
