import Foundation

/// JSONL 记录中的 message 子结构
/// 仅在 assistant 和 user 类型的记录中出现
struct ClaudeMessage: Decodable, Sendable {
    let id: String
    let role: String
    let model: String?
    let content: [MessageContent]?
    let stopReason: String?
    let stopSequence: String?
    let usage: TokenUsage?

    enum CodingKeys: String, CodingKey {
        case id, role, model, content
        case stopReason = "stop_reason"
        case stopSequence = "stop_sequence"
        case usage
    }
}

/// 消息内容块
struct MessageContent: Decodable, Sendable {
    let type: String
    let thinking: String?
    let text: String?
    let signature: String?
    let name: String?

    enum CodingKeys: String, CodingKey {
        case type, thinking, text, signature, name
    }
}
