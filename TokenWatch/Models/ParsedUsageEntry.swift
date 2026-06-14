import Foundation

/// 解析后展平的用量条目
/// 参考 ccusage 的 LoadedEntry 设计，增加去重所需字段
struct ParsedUsageEntry: Sendable, Hashable {
    let recordUUID: String
    let sessionID: String
    let timestamp: Date?
    let model: String
    let cwd: String?
    let agentId: String?
    let usage: TokenUsage
    let isSubagent: Bool

    /// 复合去重键：参考 TokenTracker 的去重策略
    nonisolated func hash(into hasher: inout Hasher) {
        hasher.combine(sessionID)
        hasher.combine(timestamp)
        hasher.combine(model)
        hasher.combine(usage.inputTokens)
        hasher.combine(usage.outputTokens)
    }

    nonisolated static func == (lhs: ParsedUsageEntry, rhs: ParsedUsageEntry) -> Bool {
        lhs.sessionID == rhs.sessionID
            && lhs.timestamp == rhs.timestamp
            && lhs.model == rhs.model
            && lhs.usage.inputTokens == rhs.usage.inputTokens
            && lhs.usage.outputTokens == rhs.usage.outputTokens
    }

    var dedupKey: String {
        let ts = timestamp.map { ISO8601DateFormatter().string(from: $0) } ?? "nil"
        return "\(sessionID)|\(ts)|\(model)|\(usage.inputTokens)|\(usage.outputTokens)"
    }
}
