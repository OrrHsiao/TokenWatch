import Foundation

/// 编译时内置的模型定价表
/// 数据来源：LiteLLM model_prices_and_context_window.json
/// Mac App Store 分发不允许运行时网络获取定价，因此必须硬编码
/// 参考 ccusage 的 PricingMap 设计，支持精确匹配和前缀模糊匹配
struct PricingTable: Sendable {

    /// 内置定价表（每百万 token USD）
    /// key 为标准化模型 ID（小写+连字符）
    static let prices: [String: ModelPricing] = [
        // MARK: - Claude 系列

        // Opus 4 系列
        "claude-opus-4": ModelPricing(
            modelID: "claude-opus-4",
            displayName: "Claude Opus 4",
            inputPrice: 15.0, outputPrice: 75.0,
            cacheReadPrice: 1.50, cacheWritePrice: 18.75
        ),
        "claude-opus-4-1": ModelPricing(
            modelID: "claude-opus-4-1",
            displayName: "Claude Opus 4.1",
            inputPrice: 15.0, outputPrice: 75.0,
            cacheReadPrice: 1.50, cacheWritePrice: 18.75
        ),
        "claude-opus-4-5": ModelPricing(
            modelID: "claude-opus-4-5",
            displayName: "Claude Opus 4.5",
            inputPrice: 5.0, outputPrice: 25.0,
            cacheReadPrice: 0.50, cacheWritePrice: 6.25
        ),

        // Sonnet 4 系列
        "claude-sonnet-4": ModelPricing(
            modelID: "claude-sonnet-4",
            displayName: "Claude Sonnet 4",
            inputPrice: 3.0, outputPrice: 15.0,
            cacheReadPrice: 0.30, cacheWritePrice: 3.75
        ),
        "claude-sonnet-4-5": ModelPricing(
            modelID: "claude-sonnet-4-5",
            displayName: "Claude Sonnet 4.5",
            inputPrice: 3.0, outputPrice: 15.0,
            cacheReadPrice: 0.30, cacheWritePrice: 3.75
        ),

        // Haiku 4.5
        "claude-haiku-4-5": ModelPricing(
            modelID: "claude-haiku-4-5",
            displayName: "Claude Haiku 4.5",
            inputPrice: 1.0, outputPrice: 5.0,
            cacheReadPrice: 0.10, cacheWritePrice: 1.25
        ),

        // Fable 5
        "claude-fable-5": ModelPricing(
            modelID: "claude-fable-5",
            displayName: "Claude Fable 5",
            inputPrice: 10.0, outputPrice: 50.0,
            cacheReadPrice: 1.00, cacheWritePrice: 12.50
        ),

        // Claude 3.5 系列
        "claude-3.5-haiku": ModelPricing(
            modelID: "claude-3.5-haiku",
            displayName: "Claude 3.5 Haiku",
            inputPrice: 0.80, outputPrice: 4.0,
            cacheReadPrice: 0.08, cacheWritePrice: 1.00
        ),
        "claude-3.5-sonnet": ModelPricing(
            modelID: "claude-3.5-sonnet",
            displayName: "Claude 3.5 Sonnet",
            inputPrice: 3.0, outputPrice: 15.0,
            cacheReadPrice: 0.30, cacheWritePrice: 3.75
        ),

        // Claude 3.7 系列
        "claude-3.7-sonnet": ModelPricing(
            modelID: "claude-3.7-sonnet",
            displayName: "Claude 3.7 Sonnet",
            inputPrice: 3.0, outputPrice: 15.0,
            cacheReadPrice: 0.30, cacheWritePrice: 3.75
        ),

        // MARK: - DeepSeek 系列

        "deepseek-v4-pro": ModelPricing(
            modelID: "deepseek-v4-pro",
            displayName: "DeepSeek V4 Pro",
            inputPrice: 3.0, outputPrice: 15.0,
            cacheReadPrice: 0.30, cacheWritePrice: 3.75
        ),
        "deepseek-v4-flash": ModelPricing(
            modelID: "deepseek-v4-flash",
            displayName: "DeepSeek V4 Flash",
            inputPrice: 1.0, outputPrice: 5.0,
            cacheReadPrice: 0.10, cacheWritePrice: 1.25
        ),
    ]

    /// 模型名称别名映射
    /// 将非标准名称映射到标准化 key
    static let aliases: [String: String] = [:]

    /// 查找定价，支持多级匹配策略
    /// 1. 精确匹配
    /// 2. 别名匹配
    /// 3. 前缀模糊匹配（用于带日期后缀的模型名，如 "claude-opus-4-20250514"）
    /// - Parameter modelID: 从 JSONL 中读取的原始模型名称
    /// - Returns: 匹配的定价条目，未找到返回 nil
    static func pricing(for modelID: String) -> ModelPricing? {
        let normalized = modelID.lowercased()

        // 1. 精确匹配
        if let pricing = prices[normalized] {
            return pricing
        }

        // 2. 别名匹配
        if let canonical = aliases[normalized], let pricing = prices[canonical] {
            return pricing
        }

        // 3. 前缀模糊匹配
        // 用于匹配 "claude-opus-4-20250514" -> "claude-opus-4"
        for (key, pricing) in prices {
            if normalized.hasPrefix(key) {
                return pricing
            }
        }

        return nil
    }
}
