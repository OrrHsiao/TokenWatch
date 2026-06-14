import Foundation

/// Claude Code JSONL 中 assistant 记录的 usage 对象完整字段映射
/// 参考 ccusage 的数据模型设计
struct TokenUsage: Decodable, Sendable {
    let inputTokens: Int
    let cacheCreationInputTokens: Int
    let cacheReadInputTokens: Int
    let outputTokens: Int
    let serverToolUse: ServerToolUse
    let serviceTier: String
    let cacheCreation: CacheCreation
    let inferenceGeo: String
    let iterations: [String]  // 实际数据中始终为空数组
    let speed: String

    enum CodingKeys: String, CodingKey {
        case inputTokens = "input_tokens"
        case cacheCreationInputTokens = "cache_creation_input_tokens"
        case cacheReadInputTokens = "cache_read_input_tokens"
        case outputTokens = "output_tokens"
        case serverToolUse = "server_tool_use"
        case serviceTier = "service_tier"
        case cacheCreation = "cache_creation"
        case inferenceGeo = "inference_geo"
        case iterations
        case speed
    }

    /// 自定义解码：iterations 在真实数据中始终为空数组 []
    nonisolated init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        inputTokens = try container.decode(Int.self, forKey: .inputTokens)
        cacheCreationInputTokens = try container.decode(Int.self, forKey: .cacheCreationInputTokens)
        cacheReadInputTokens = try container.decode(Int.self, forKey: .cacheReadInputTokens)
        outputTokens = try container.decode(Int.self, forKey: .outputTokens)
        serverToolUse = try container.decode(ServerToolUse.self, forKey: .serverToolUse)
        serviceTier = try container.decode(String.self, forKey: .serviceTier)
        cacheCreation = try container.decode(CacheCreation.self, forKey: .cacheCreation)
        inferenceGeo = try container.decode(String.self, forKey: .inferenceGeo)
        // iterations 始终为空数组，跳过实际解码避免类型不匹配
        iterations = []
        speed = try container.decode(String.self, forKey: .speed)
    }

    /// 便捷初始化（用于测试）
    init(
        inputTokens: Int,
        cacheCreationInputTokens: Int,
        cacheReadInputTokens: Int,
        outputTokens: Int,
        serverToolUse: ServerToolUse,
        serviceTier: String,
        cacheCreation: CacheCreation,
        inferenceGeo: String,
        iterations: [String],
        speed: String
    ) {
        self.inputTokens = inputTokens
        self.cacheCreationInputTokens = cacheCreationInputTokens
        self.cacheReadInputTokens = cacheReadInputTokens
        self.outputTokens = outputTokens
        self.serverToolUse = serverToolUse
        self.serviceTier = serviceTier
        self.cacheCreation = cacheCreation
        self.inferenceGeo = inferenceGeo
        self.iterations = iterations
        self.speed = speed
    }
}

/// server_tool_use 子结构
struct ServerToolUse: Decodable, Sendable {
    let webSearchRequests: Int
    let webFetchRequests: Int

    enum CodingKeys: String, CodingKey {
        case webSearchRequests = "web_search_requests"
        case webFetchRequests = "web_fetch_requests"
    }
}

/// cache_creation 子结构
/// 包含 ephemeral 缓存分解，ccusage 中 5m 和 1h 使用不同价格计算
struct CacheCreation: Decodable, Sendable {
    let ephemeral1hInputTokens: Int
    let ephemeral5mInputTokens: Int

    enum CodingKeys: String, CodingKey {
        case ephemeral1hInputTokens = "ephemeral_1h_input_tokens"
        case ephemeral5mInputTokens = "ephemeral_5m_input_tokens"
    }
}
