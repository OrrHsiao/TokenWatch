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

/// Claude daily adapter 只消费计价字段，避免 role/content 等无关坏类型否决 usage。
struct ClaudeBillingMessage: Decodable, Sendable {
    let id: String?
    let model: String?
    let usage: ClaudeBillingUsage

    private enum CodingKeys: String, CodingKey {
        case id, model, usage
    }
}

/// ccusage TokenUsageRaw 的窄 Swift 映射；所有 token 必须是非负 JSON 整数。
struct ClaudeBillingUsage: Decodable, Sendable {
    let inputTokens: Int
    let outputTokens: Int
    let cacheCreationInputTokens: Int
    let cacheReadInputTokens: Int
    let speed: String?
    let cacheCreation: ClaudeBillingCacheCreation?

    private enum CodingKeys: String, CodingKey {
        case inputTokens = "input_tokens"
        case outputTokens = "output_tokens"
        case cacheCreationInputTokens = "cache_creation_input_tokens"
        case cacheReadInputTokens = "cache_read_input_tokens"
        case speed
        case cacheCreation = "cache_creation"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        inputTokens = try Self.decodeNonNegative(.inputTokens, from: container)
        outputTokens = try Self.decodeNonNegative(.outputTokens, from: container)
        cacheCreationInputTokens = try Self.decodeNonNegativeIfPresent(
            .cacheCreationInputTokens,
            from: container
        )
        cacheReadInputTokens = try Self.decodeNonNegativeIfPresent(
            .cacheReadInputTokens,
            from: container
        )
        speed = try container.decodeIfPresent(String.self, forKey: .speed)
        if let speed, speed != "standard", speed != "fast" {
            throw DecodingError.dataCorruptedError(
                forKey: .speed,
                in: container,
                debugDescription: "Claude speed must be standard or fast"
            )
        }
        cacheCreation = try container.decodeIfPresent(
            ClaudeBillingCacheCreation.self,
            forKey: .cacheCreation
        )
    }

    /// 转换到应用统一 usage 模型，并保留 cache breakdown 的 presence 语义。
    var tokenUsage: TokenUsage {
        TokenUsage(
            inputTokens: inputTokens,
            cacheCreationInputTokens: cacheCreationInputTokens,
            cacheReadInputTokens: cacheReadInputTokens,
            outputTokens: outputTokens,
            serverToolUse: ServerToolUse(webSearchRequests: 0, webFetchRequests: 0),
            serviceTier: "",
            cacheCreation: cacheCreation.map {
                CacheCreation(
                    ephemeral1hInputTokens: $0.ephemeral1hInputTokens,
                    ephemeral5mInputTokens: $0.ephemeral5mInputTokens
                )
            },
            inferenceGeo: "",
            iterations: [],
            speed: speed ?? ""
        )
    }

    private static func decodeNonNegative(
        _ key: CodingKeys,
        from container: KeyedDecodingContainer<CodingKeys>
    ) throws -> Int {
        let value = try container.decode(Int.self, forKey: key)
        guard value >= 0 else {
            throw DecodingError.dataCorruptedError(
                forKey: key,
                in: container,
                debugDescription: "Claude token count must be non-negative"
            )
        }
        return value
    }

    private static func decodeNonNegativeIfPresent(
        _ key: CodingKeys,
        from container: KeyedDecodingContainer<CodingKeys>
    ) throws -> Int {
        guard container.contains(key) else { return 0 }
        return try decodeNonNegative(key, from: container)
    }
}

/// cache_creation 对象中的子字段；缺失默认零，显式 null 仍是无效类型。
struct ClaudeBillingCacheCreation: Decodable, Sendable {
    let ephemeral5mInputTokens: Int
    let ephemeral1hInputTokens: Int

    private enum CodingKeys: String, CodingKey {
        case ephemeral5mInputTokens = "ephemeral_5m_input_tokens"
        case ephemeral1hInputTokens = "ephemeral_1h_input_tokens"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        ephemeral5mInputTokens = try Self.decodeNonNegativeIfPresent(
            .ephemeral5mInputTokens,
            from: container
        )
        ephemeral1hInputTokens = try Self.decodeNonNegativeIfPresent(
            .ephemeral1hInputTokens,
            from: container
        )
    }

    private static func decodeNonNegativeIfPresent(
        _ key: CodingKeys,
        from container: KeyedDecodingContainer<CodingKeys>
    ) throws -> Int {
        guard container.contains(key) else { return 0 }
        let value = try container.decode(Int.self, forKey: key)
        guard value >= 0 else {
            throw DecodingError.dataCorruptedError(
                forKey: key,
                in: container,
                debugDescription: "Claude cache token count must be non-negative"
            )
        }
        return value
    }
}

/// 顶层 Claude iteration 中可单独计费的 advisor usage。
struct ClaudeAdvisorUsage: Sendable {
    let model: String
    let usage: ClaudeBillingUsage
}

/// 独立解码顶层 message.usage.iterations；失败时由调用方只忽略 advisors。
enum ClaudeAdvisorUsageDecoder {
    private static let marker = Data(#""advisor_message""#.utf8)

    static func decode(
        from lineData: Data,
        using decoder: JSONDecoder
    ) -> [ClaudeAdvisorUsage] {
        guard lineData.range(of: marker) != nil,
              let envelope = try? decoder.decode(
                  ClaudeAdvisorEnvelope.self,
                  from: lineData
              ) else {
            return []
        }
        return envelope.message.usage.iterations.compactMap(\.advisorUsage)
    }
}

private struct ClaudeAdvisorEnvelope: Decodable {
    let message: Message

    struct Message: Decodable {
        let usage: Usage
    }

    struct Usage: Decodable {
        let iterations: [Iteration]
    }

    struct Iteration: Decodable {
        let advisorUsage: ClaudeAdvisorUsage?

        private enum CodingKeys: String, CodingKey {
            case type, model
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            let type = try container.decode(String.self, forKey: .type)
            let model = try container.decodeIfPresent(String.self, forKey: .model)
            let usage = try ClaudeBillingUsage(from: decoder)
            guard type == "advisor_message",
                  let model,
                  !model.isEmpty else {
                advisorUsage = nil
                return
            }
            advisorUsage = ClaudeAdvisorUsage(
                model: model,
                usage: usage
            )
        }
    }
}
