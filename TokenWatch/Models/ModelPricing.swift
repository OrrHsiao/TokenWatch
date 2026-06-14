import Foundation

/// 模型定价条目
/// 所有价格均为每百万 token 的 USD 价格
/// 数据来源：LiteLLM model_prices_and_context_window.json
struct ModelPricing: Sendable {
    let modelID: String            // 标准化模型名称，如 "deepseek-v4-pro"
    let displayName: String        // 显示名称，如 "DeepSeek V4 Pro"
    let inputPrice: Double         // 每百万 input token USD
    let outputPrice: Double        // 每百万 output token USD
    let cacheReadPrice: Double     // 每百万 cache read token USD
    let cacheWritePrice: Double    // 每百万 cache write token USD
}
