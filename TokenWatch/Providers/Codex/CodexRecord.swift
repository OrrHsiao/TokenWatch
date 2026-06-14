import Foundation

/// Codex JSONL(`~/.codex/sessions/.../rollout-*.jsonl`)中每一行的顶层结构
/// 仅解析 token 统计需要的 type:session_meta / turn_context / event_msg
/// 其余 type(response_item / function_call / 等)归为 .unknown 并跳过
struct CodexRecord: Decodable, Sendable {
    let timestamp: Date?
    let type: String
    let payload: CodexPayload

    enum CodingKeys: String, CodingKey {
        case timestamp, type, payload
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        type = try container.decode(String.self, forKey: .type)

        if let ts = try container.decodeIfPresent(String.self, forKey: .timestamp) {
            timestamp = ISO8601DateFormatterHelper.parse(ts)
        } else {
            timestamp = nil
        }

        // payload 形态由 type 决定 — 解码失败的子结构降级为 .unknown,
        // 保持单行损坏不阻断后续行(参考 Claude JSONL 的容错风格)
        switch type {
        case "session_meta":
            if let meta = try? container.decode(CodexSessionMeta.self, forKey: .payload) {
                payload = .sessionMeta(meta)
            } else {
                payload = .unknown
            }
        case "turn_context":
            if let ctx = try? container.decode(CodexTurnContext.self, forKey: .payload) {
                payload = .turnContext(ctx)
            } else {
                payload = .unknown
            }
        case "event_msg":
            if let evt = try? container.decode(CodexEventMsg.self, forKey: .payload) {
                payload = .eventMsg(evt)
            } else {
                payload = .unknown
            }
        default:
            payload = .unknown
        }
    }
}

/// 按 type 分发后的 payload
enum CodexPayload: Sendable {
    case sessionMeta(CodexSessionMeta)
    case turnContext(CodexTurnContext)
    case eventMsg(CodexEventMsg)
    case unknown
}

/// session_meta.payload — 整个 rollout 文件首行,提供 sessionId / cwd
struct CodexSessionMeta: Decodable, Sendable {
    let id: String
    let cwd: String?
    let modelProvider: String?

    enum CodingKeys: String, CodingKey {
        case id, cwd
        case modelProvider = "model_provider"
    }
}

/// turn_context.payload — 每轮对话开始,标明此后 token_count 归属的 model
struct CodexTurnContext: Decodable, Sendable {
    let model: String?
}

/// event_msg.payload — 包一层 type 才到我们关心的 token_count
struct CodexEventMsg: Decodable, Sendable {
    let type: String                 // 只关心 "token_count"
    let info: CodexTokenCountInfo?

    enum CodingKeys: String, CodingKey {
        case type, info
    }
}

/// token_count.info — 心跳事件该字段为 null
struct CodexTokenCountInfo: Decodable, Sendable {
    let lastTokenUsage: CodexTokenCounts?
    let totalTokenUsage: CodexTokenCounts?

    enum CodingKeys: String, CodingKey {
        case lastTokenUsage = "last_token_usage"
        case totalTokenUsage = "total_token_usage"
    }
}

/// 单次 token 计数四元组(+ total)
struct CodexTokenCounts: Decodable, Sendable, Equatable {
    let inputTokens: Int           // 注意:Codex 的 input 已包含 cached_input,计费时需扣减
    let cachedInputTokens: Int
    let outputTokens: Int          // 注意:已包含 reasoning_output_tokens,reasoning 不另行计费
    let reasoningOutputTokens: Int
    let totalTokens: Int

    enum CodingKeys: String, CodingKey {
        case inputTokens = "input_tokens"
        case cachedInputTokens = "cached_input_tokens"
        case outputTokens = "output_tokens"
        case reasoningOutputTokens = "reasoning_output_tokens"
        case totalTokens = "total_tokens"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        inputTokens = try c.decodeIfPresent(Int.self, forKey: .inputTokens) ?? 0
        cachedInputTokens = try c.decodeIfPresent(Int.self, forKey: .cachedInputTokens) ?? 0
        outputTokens = try c.decodeIfPresent(Int.self, forKey: .outputTokens) ?? 0
        reasoningOutputTokens = try c.decodeIfPresent(Int.self, forKey: .reasoningOutputTokens) ?? 0
        totalTokens = try c.decodeIfPresent(Int.self, forKey: .totalTokens) ?? 0
    }

    init(inputTokens: Int, cachedInputTokens: Int, outputTokens: Int,
         reasoningOutputTokens: Int, totalTokens: Int) {
        self.inputTokens = inputTokens
        self.cachedInputTokens = cachedInputTokens
        self.outputTokens = outputTokens
        self.reasoningOutputTokens = reasoningOutputTokens
        self.totalTokens = totalTokens
    }

    static let zero = CodexTokenCounts(
        inputTokens: 0, cachedInputTokens: 0,
        outputTokens: 0, reasoningOutputTokens: 0, totalTokens: 0
    )

    var isAllZero: Bool {
        inputTokens == 0 && cachedInputTokens == 0
            && outputTokens == 0 && reasoningOutputTokens == 0
    }
}
