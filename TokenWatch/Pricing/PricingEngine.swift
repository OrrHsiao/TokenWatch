import Foundation
import os.log

/// 记录未知模型定价日志的门控,避免长时间运行时同一 miss 持续刷屏。
final class MissingPricingLogOnceGate: @unchecked Sendable {
    static let shared = MissingPricingLogOnceGate()

    private let lock = NSLock()
    private var loggedModelIDs: Set<String> = []

    /// 返回当前模型 miss 是否应输出日志;同一标准化 modelID 仅首次返回 true。
    func shouldLogMiss(for modelID: String) -> Bool {
        let normalized = modelID.lowercased()

        lock.lock()
        defer { lock.unlock() }

        if loggedModelIDs.contains(normalized) {
            return false
        }
        loggedModelIDs.insert(normalized)
        return true
    }
}

/// 定价计算引擎
///
/// 参考 ccusage `cost.rs::calculate_cost_from_tokens` + `tiered_cost`：
/// ```
/// cost = ( tiered(inputTokens,        inputPrice,         inputPriceAbove200k)
///        + tiered(outputTokens,       outputPrice,        outputPriceAbove200k)
///        + tiered(cacheCreate5m,      cacheWritePrice,    cacheWritePriceAbove200k)
///        + tiered(cacheCreate1h,      inputPrice  × 2,    inputPriceAbove200k × 2)
///        + tiered(cacheRead,          cacheReadPrice,     cacheReadPriceAbove200k) )
///      × multiplier
/// 其中:
///   tiered(t, base, above) = 200_000 × base + (t - 200_000) × above   (above != nil 且 t > 200k)
///                          | t × base                                  (其他情形)
///   multiplier = pricing.fastMultiplier   (usage.speed == "fast")
///              | 1.0                       (其他情形)
/// ```
///
/// 关键约束：
/// - 每类 token 的 200k 阈值独立判断（input 跨阈不会让 output 也走 above）
/// - cache_create_1h 不读 LiteLLM 的 1h above 字段，而是 `input_above × 2.0`
/// - fastMultiplier 在所有 tiered_cost 之和上整体乘一次,不分类应用
/// - `cache_creation_input_tokens` 与 `cache_creation.ephemeral_5m/1h` 是
///   总分关系（同一信息的两种表达），通过 `TokenUsage.cacheCreate5mTokens` /
///   `cacheCreate1hTokens` 在数据层完成二选一，引擎只负责计费
///
/// 简化前提（与 ccusage 当前实现的差异，未来按需扩展）：
/// - 定价表为 per-1M token USD，故公式中需 `÷ 1_000_000`
struct PricingEngine: Sendable {

    /// 200k tier 阈值（来自 ccusage `cost.rs::tiered_cost::THRESHOLD`）
    private static let tierThreshold: Int = 200_000

    /// 1h 缓存写入价格相对 input 的乘子（来自 ccusage `CACHE_CREATE_1H_INPUT_MULTIPLIER`）
    private static let cacheCreate1hInputMultiplier: Double = 2.0

    /// 触发 fastMultiplier 的 speed 字段值(参考 ccusage `Speed` 枚举的
    /// `#[serde(rename_all = "lowercase")]`,Anthropic 协议使用小写 "fast")
    private static let fastSpeedValue: String = "fast"

    private let logger = Logger(subsystem: "com.xiaoao.TokenWatch", category: "PricingEngine")
    private let missingPricingLogGate: MissingPricingLogOnceGate

    init(missingPricingLogGate: MissingPricingLogOnceGate = .shared) {
        self.missingPricingLogGate = missingPricingLogGate
    }

    /// 阶梯计费：超过 200k 阈值的部分按 above 单价，否则全部按 base 单价
    /// 单价均为「每百万 token USD」，函数内部完成 ÷ 1e6
    private static func tieredCost(tokens: Int, base: Double, above: Double?) -> Double {
        guard tokens > 0 else { return 0.0 }
        if let above, tokens > tierThreshold {
            let baseCost = Double(tierThreshold) * base / 1_000_000.0
            let aboveCost = Double(tokens - tierThreshold) * above / 1_000_000.0
            return baseCost + aboveCost
        }
        return Double(tokens) * base / 1_000_000.0
    }

    /// 根据已知定价计算单次 assistant 调用的成本
    /// - Parameters:
    ///   - usage: assistant 记录的 token 用量(同时携带 speed 字段决定是否走 fast 倍率)
    ///   - pricing: 对应的模型定价
    /// - Returns: USD 成本
    func calculateCost(usage: TokenUsage, pricing: ModelPricing) -> Double {
        let inputCost = Self.tieredCost(
            tokens: usage.inputTokens,
            base: pricing.inputPrice,
            above: pricing.inputPriceAbove200k
        )
        let outputCost = Self.tieredCost(
            tokens: usage.outputTokens,
            base: pricing.outputPrice,
            above: pricing.outputPriceAbove200k
        )
        let cache5mCost = Self.tieredCost(
            tokens: usage.cacheCreate5mTokens,
            base: pricing.cacheWritePrice,
            above: pricing.cacheWritePriceAbove200k
        )
        // 1h 缓存：base = inputPrice × 2，above = inputPriceAbove200k × 2（无独立字段）
        let cache1hBase = pricing.inputPrice * Self.cacheCreate1hInputMultiplier
        let cache1hAbove = pricing.inputPriceAbove200k.map { $0 * Self.cacheCreate1hInputMultiplier }
        let cache1hCost = Self.tieredCost(
            tokens: usage.cacheCreate1hTokens,
            base: cache1hBase,
            above: cache1hAbove
        )
        let cacheReadCost = Self.tieredCost(
            tokens: usage.cacheReadInputTokens,
            base: pricing.cacheReadPrice,
            above: pricing.cacheReadPriceAbove200k
        )

        let subtotal = inputCost + outputCost + cache5mCost + cache1hCost + cacheReadCost

        // Speed::Fast 整体乘倍 — 必须放在所有 tiered_cost 之和上一次性应用,
        // 与 ccusage `cost.rs` 末尾 `* multiplier` 的语义对齐
        let multiplier = (usage.speed == Self.fastSpeedValue) ? pricing.fastMultiplier : 1.0
        return subtotal * multiplier
    }

    /// 为模型查找定价并计算成本
    /// - Parameters:
    ///   - usage: assistant 记录的 token 用量
    ///   - model: 模型名称（原始字符串）
    /// - Returns: (成本 USD, 匹配到的定价条目)
    ///   如果模型无定价信息，返回 (0.0, nil)
    func calculateCost(usage: TokenUsage, model: String) -> (cost: Double, pricing: ModelPricing?) {
        guard let pricing = PricingTable.pricing(for: model) else {
            if missingPricingLogGate.shouldLogMiss(for: model) {
                logger.warning("未找到模型定价: \(model)，费用计为 $0.00")
            }
            return (0.0, nil)
        }
        return (calculateCost(usage: usage, pricing: pricing), pricing)
    }
}
