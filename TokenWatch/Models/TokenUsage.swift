import Foundation

extension Int {
    /// 返回饱和加法结果；发生溢出时按溢出方向夹到 Int 的对应边界。
    func addingSaturated(_ other: Int) -> Int {
        let (sum, overflow) = addingReportingOverflow(other)
        guard overflow else { return sum }
        return other >= 0 ? .max : .min
    }
}

/// Claude Code JSONL 中 assistant 记录的 usage 对象完整字段映射
/// 参考 ccusage 的数据模型设计
struct TokenUsage: Decodable, Sendable {
    let inputTokens: Int
    let cacheCreationInputTokens: Int
    let cacheReadInputTokens: Int
    let outputTokens: Int
    let reasoningTokens: Int
    let serverToolUse: ServerToolUse
    let serviceTier: String
    let cacheCreation: CacheCreation?
    let inferenceGeo: String
    let iterations: [String]  // 实际数据中始终为空数组
    let speed: String

    enum CodingKeys: String, CodingKey {
        case inputTokens = "input_tokens"
        case cacheCreationInputTokens = "cache_creation_input_tokens"
        case cacheReadInputTokens = "cache_read_input_tokens"
        case outputTokens = "output_tokens"
        case reasoningTokens = "reasoning_tokens"
        case serverToolUse = "server_tool_use"
        case serviceTier = "service_tier"
        case cacheCreation = "cache_creation"
        case inferenceGeo = "inference_geo"
        case iterations
        case speed
    }

    /// 自定义解码：iterations 在真实数据中始终为空数组 []
    /// 周边元数据缺失（service_tier / inference_geo / speed 等）时降级为空字符串，
    /// 不阻断核心 token 字段的解析；core 字段（input/output_tokens 等）缺失才会失败。
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        inputTokens = try container.decode(Int.self, forKey: .inputTokens)
        cacheCreationInputTokens = try container.decodeIfPresent(Int.self, forKey: .cacheCreationInputTokens) ?? 0
        cacheReadInputTokens = try container.decodeIfPresent(Int.self, forKey: .cacheReadInputTokens) ?? 0
        outputTokens = try container.decode(Int.self, forKey: .outputTokens)
        reasoningTokens = try container.decodeIfPresent(Int.self, forKey: .reasoningTokens) ?? 0
        serverToolUse = try container.decodeIfPresent(ServerToolUse.self, forKey: .serverToolUse)
            ?? ServerToolUse(webSearchRequests: 0, webFetchRequests: 0)
        serviceTier = try container.decodeIfPresent(String.self, forKey: .serviceTier) ?? ""
        // 对象是否存在决定细分是否权威；缺失或 null 必须保留为 nil，供扁平字段回退。
        cacheCreation = try container.decodeIfPresent(CacheCreation.self, forKey: .cacheCreation)
        inferenceGeo = try container.decodeIfPresent(String.self, forKey: .inferenceGeo) ?? ""
        // iterations 始终为空数组，跳过实际解码避免类型不匹配
        iterations = []
        speed = try container.decodeIfPresent(String.self, forKey: .speed) ?? ""
    }

    /// 便捷初始化（用于测试）
    init(
        inputTokens: Int,
        cacheCreationInputTokens: Int,
        cacheReadInputTokens: Int,
        outputTokens: Int,
        reasoningTokens: Int = 0,
        serverToolUse: ServerToolUse,
        serviceTier: String,
        cacheCreation: CacheCreation?,
        inferenceGeo: String,
        iterations: [String],
        speed: String
    ) {
        self.inputTokens = inputTokens
        self.cacheCreationInputTokens = cacheCreationInputTokens
        self.cacheReadInputTokens = cacheReadInputTokens
        self.outputTokens = outputTokens
        self.reasoningTokens = reasoningTokens
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

    init(webSearchRequests: Int, webFetchRequests: Int) {
        self.webSearchRequests = webSearchRequests
        self.webFetchRequests = webFetchRequests
    }

    /// 宽容解码部分 server_tool_use 对象，缺失成员按 0 处理。
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        webSearchRequests = try container.decodeIfPresent(Int.self, forKey: .webSearchRequests) ?? 0
        webFetchRequests = try container.decodeIfPresent(Int.self, forKey: .webFetchRequests) ?? 0
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

    init(ephemeral1hInputTokens: Int, ephemeral5mInputTokens: Int) {
        self.ephemeral1hInputTokens = ephemeral1hInputTokens
        self.ephemeral5mInputTokens = ephemeral5mInputTokens
    }

    /// 宽容解码部分 cache_creation 对象；对象 presence 仍由 TokenUsage 保留。
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        ephemeral1hInputTokens = try container.decodeIfPresent(Int.self, forKey: .ephemeral1hInputTokens) ?? 0
        ephemeral5mInputTokens = try container.decodeIfPresent(Int.self, forKey: .ephemeral5mInputTokens) ?? 0
    }
}

// MARK: - Cache 派生属性
//
// `cache_creation_input_tokens` 与 `cache_creation.ephemeral_5m/1h` 是
// 同一信息的两种表达（总分关系，非并列），不能相加，否则会 double-count。
//
// 参考 ccusage `cost.rs::calculate_cost_from_tokens`：
// 当 `cache_creation` breakdown 存在时使用细分；否则把扁平字段当作 5m。
// 1h 缓存写入按 `inputPrice × 2` 计费，5m 才用 `cacheWritePrice`。

extension TokenUsage {
    /// 5 分钟缓存写入 token 数（按 `cacheWritePrice` 计费）
    var cacheCreate5mTokens: Int {
        guard let cacheCreation else { return cacheCreationInputTokens }
        return cacheCreation.ephemeral5mInputTokens
    }

    /// 1 小时缓存写入 token 数（按 `inputPrice × 2` 计费）
    var cacheCreate1hTokens: Int {
        cacheCreation?.ephemeral1hInputTokens ?? 0
    }

    /// cache 写入 token 总量（用于展示／聚合，不会重复计入扁平字段）
    var totalCacheCreationTokens: Int {
        cacheCreate5mTokens.addingSaturated(cacheCreate1hTokens)
    }

    /// ccusage 聚合口径下的非重复 token 总量。
    /// reasoning 是独立展示维度；Codex output 已包含它，不能再次相加。
    var aggregateTotalTokens: Int {
        [
            inputTokens,
            outputTokens,
            cacheReadInputTokens,
            totalCacheCreationTokens,
        ].reduce(0) { $0.addingSaturated($1) }
    }
}
