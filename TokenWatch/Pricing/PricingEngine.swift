import Foundation
import os.log

/// 定价计算引擎
///
/// 参考 ccusage `cost.rs::calculate_cost_from_tokens`：
/// ```
/// cost = inputTokens          × inputPrice           / 1e6
///      + outputTokens         × outputPrice          / 1e6
///      + cacheCreate5mTokens  × cacheWritePrice      / 1e6     // 5m → write 价
///      + cacheCreate1hTokens  × inputPrice × 2       / 1e6     // 1h → input × 2
///      + cacheReadTokens      × cacheReadPrice       / 1e6
/// ```
///
/// `cache_creation_input_tokens` 与 `ephemeral_5m/1h_input_tokens` 是
/// 总分关系（同一信息的两种表达），通过 `TokenUsage.cacheCreate5mTokens` /
/// `cacheCreate1hTokens` 在数据层完成二选一，引擎只负责计费。
///
/// 简化前提（与 ccusage 当前实现的差异，未来按需扩展）：
/// - 不实现 200k tier 阶梯定价（input/output/cache 超过 200k token 后单价不同）
/// - 不实现 Speed::Fast 的 `fast_multiplier`
/// - 定价表为 per-1M token USD，故公式中需 `÷ 1_000_000`
struct PricingEngine: Sendable {

    /// 1h 缓存写入价格相对 input 的乘子（来自 ccusage `CACHE_CREATE_1H_INPUT_MULTIPLIER`）
    private static let cacheCreate1hInputMultiplier: Double = 2.0

    private let logger = Logger(subsystem: "com.xiaoao.TokenWatch", category: "PricingEngine")

    /// 根据已知定价计算单次 assistant 调用的成本
    /// - Parameters:
    ///   - usage: assistant 记录的 token 用量
    ///   - pricing: 对应的模型定价
    /// - Returns: USD 成本
    func calculateCost(usage: TokenUsage, pricing: ModelPricing) -> Double {
        let inputCost = Double(usage.inputTokens) * pricing.inputPrice / 1_000_000.0
        let outputCost = Double(usage.outputTokens) * pricing.outputPrice / 1_000_000.0
        let cache5mCost = Double(usage.cacheCreate5mTokens) * pricing.cacheWritePrice / 1_000_000.0
        let cache1hUnitPrice = pricing.inputPrice * Self.cacheCreate1hInputMultiplier
        let cache1hCost = Double(usage.cacheCreate1hTokens) * cache1hUnitPrice / 1_000_000.0
        let cacheReadCost = Double(usage.cacheReadInputTokens) * pricing.cacheReadPrice / 1_000_000.0

        return inputCost + outputCost + cache5mCost + cache1hCost + cacheReadCost
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
