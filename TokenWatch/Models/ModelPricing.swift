import Foundation

/// 模型定价条目
/// 所有价格均为每百万 token 的 USD 价格
/// 数据来源：LiteLLM model_prices_and_context_window.json
///
/// 200k tier 阶梯定价（参考 ccusage `cost.rs::tiered_cost`）：
/// 当某类 token 数超过 200_000 时，超出部分按 `*Above200k` 单价计费。
/// 仅 Claude Sonnet 家族（3.5 / 4 / 4.5）配置了 above_200k 单价；
/// Opus / Haiku / Fable / 3.7 Sonnet / DeepSeek 等保持 nil → 退化为单价。
/// 1h 缓存写入的 above 不读单独字段，由 `PricingEngine` 用 `inputPriceAbove200k × 2` 推导。
struct ModelPricing: Sendable {
    let modelID: String            // 标准化模型名称，如 "deepseek-v4-pro"
    let displayName: String        // 显示名称，如 "DeepSeek V4 Pro"
    let inputPrice: Double         // 每百万 input token USD
    let outputPrice: Double        // 每百万 output token USD
    let cacheReadPrice: Double     // 每百万 cache read token USD
    let cacheWritePrice: Double    // 每百万 cache write token USD

    /// 超过 200k token 部分的 input 单价（每百万 USD），nil 表示该模型无阶梯定价
    let inputPriceAbove200k: Double?
    /// 超过 200k token 部分的 output 单价（每百万 USD）
    let outputPriceAbove200k: Double?
    /// 超过 200k token 部分的 cache read 单价（每百万 USD）
    let cacheReadPriceAbove200k: Double?
    /// 超过 200k token 部分的 cache write (5m) 单价（每百万 USD）
    let cacheWritePriceAbove200k: Double?

    /// Speed::Fast 倍率(参考 ccusage `provider_specific_entry.fast`)
    /// 仅当 JSONL `usage.speed == "fast"` 时,整体成本乘以此倍率
    /// 默认 1.0(模型无 fast 配置 / 普通 standard 模式),不影响成本
    /// LiteLLM 上仅 Claude Opus 4.6 / 4.7 / 4.8 配置了非 1.0 值
    let fastMultiplier: Double

    init(
        modelID: String,
        displayName: String,
        inputPrice: Double,
        outputPrice: Double,
        cacheReadPrice: Double,
        cacheWritePrice: Double,
        inputPriceAbove200k: Double? = nil,
        outputPriceAbove200k: Double? = nil,
        cacheReadPriceAbove200k: Double? = nil,
        cacheWritePriceAbove200k: Double? = nil,
        fastMultiplier: Double = 1.0
    ) {
        self.modelID = modelID
        self.displayName = displayName
        self.inputPrice = inputPrice
        self.outputPrice = outputPrice
        self.cacheReadPrice = cacheReadPrice
        self.cacheWritePrice = cacheWritePrice
        self.inputPriceAbove200k = inputPriceAbove200k
        self.outputPriceAbove200k = outputPriceAbove200k
        self.cacheReadPriceAbove200k = cacheReadPriceAbove200k
        self.cacheWritePriceAbove200k = cacheWritePriceAbove200k
        self.fastMultiplier = fastMultiplier
    }
}
