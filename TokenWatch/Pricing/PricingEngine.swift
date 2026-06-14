import Foundation
import os.log

/// 定价计算引擎
/// 完全参考 ccusage 的成本计算公式：
///   cost = inputTokens * inputPrice / 1e6
///        + outputTokens * outputPrice / 1e6
///        + cacheCreationInputTokens * cacheWritePrice / 1e6
///        + cacheReadInputTokens * cacheReadPrice / 1e6
///
/// 注意：cache_creation 的 ephemeral_5m 和 ephemeral_1h
/// 在 ccusage 中使用不同价格计算（1h 为 inputPrice * 2），
/// 但实际数据中这两个字段始终为 0，因此暂不单独计算。
struct PricingEngine: Sendable {

    private let logger = Logger(subsystem: "com.xiaoao.TokenWatch", category: "PricingEngine")

    /// 根据已知定价计算单次 assistant 调用的成本
    /// - Parameters:
    ///   - usage: assistant 记录的 token 用量
    ///   - pricing: 对应的模型定价
    /// - Returns: USD 成本
    func calculateCost(usage: TokenUsage, pricing: ModelPricing) -> Double {
        let inputCost = Double(usage.inputTokens) * pricing.inputPrice / 1_000_000.0
        let outputCost = Double(usage.outputTokens) * pricing.outputPrice / 1_000_000.0
        let cacheWriteCost = Double(usage.cacheCreationInputTokens) * pricing.cacheWritePrice / 1_000_000.0
        let cacheReadCost = Double(usage.cacheReadInputTokens) * pricing.cacheReadPrice / 1_000_000.0

        return inputCost + outputCost + cacheWriteCost + cacheReadCost
    }

    /// 为模型查找定价并计算成本
    /// - Parameters:
    ///   - usage: assistant 记录的 token 用量
    ///   - model: 模型名称（原始字符串）
    /// - Returns: (成本 USD, 匹配到的定价条目)
    ///   如果模型无定价信息，返回 (0.0, nil)
    func calculateCost(usage: TokenUsage, model: String) -> (cost: Double, pricing: ModelPricing?) {
        guard let pricing = PricingTable.pricing(for: model) else {
            logger.warning("未找到模型定价: \(model)，费用计为 $0.00")
            return (0.0, nil)
        }
        return (calculateCost(usage: usage, pricing: pricing), pricing)
    }
}
