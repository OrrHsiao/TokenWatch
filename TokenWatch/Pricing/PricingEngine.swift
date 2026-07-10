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

private enum CachedPricing: Sendable {
    case hit(ModelPricing)
    case miss

    var pricing: ModelPricing? {
        switch self {
        case .hit(let pricing):
            return pricing
        case .miss:
            return nil
        }
    }
}

private final class PricingLookupCache: @unchecked Sendable {
    private let lock = NSLock()
    private var values: [String: CachedPricing] = [:]

    var count: Int {
        lock.lock()
        defer { lock.unlock() }
        return values.count
    }

    func cachedValue(for normalizedModelID: String) -> CachedPricing? {
        lock.lock()
        defer { lock.unlock() }
        return values[normalizedModelID]
    }

    func store(_ pricing: ModelPricing?, for normalizedModelID: String) {
        lock.lock()
        defer { lock.unlock() }
        if let pricing {
            values[normalizedModelID] = .hit(pricing)
        } else {
            values[normalizedModelID] = .miss
        }
    }
}

/// 定价来源的请求语义；默认保持 Claude/通用 provider 的既有行为。
enum PricingSemantics: Sendable, Equatable {
    case standard
    case codex
}

/// 定价计算引擎。
///
/// `standard` 对无 whole-request 阈值的模型按 token 类别独立应用 200K
/// marginal tier；有 `longContextThreshold` 时，整条请求统一选择 base/long rate。
/// `codex` 在此基础上用 pure input + cache read 重建 raw input，并按 Codex 的
/// implicit cache-read 与 fast/priority 规则计费。
struct PricingEngine: Sendable {
    private static let marginalTierThreshold = 200_000
    private static let cacheCreate1hInputMultiplier = 2.0

    private let logger = Logger(
        subsystem: "com.xiaoao.TokenWatch",
        category: "PricingEngine"
    )
    private let missingPricingLogGate: MissingPricingLogOnceGate
    private let pricingTable: PricingTable
    private let pricingCache = PricingLookupCache()

    var debugCachedPricingCount: Int { pricingCache.count }

    init(
        pricingTable: PricingTable = .shared,
        missingPricingLogGate: MissingPricingLogOnceGate = .shared
    ) {
        self.pricingTable = pricingTable
        self.missingPricingLogGate = missingPricingLogGate
    }

    /// 根据已知定价计算单次调用成本。
    /// - Parameters:
    ///   - usage: 单次调用的 token 用量与服务等级。
    ///   - pricing: 对应模型的每百万 token 定价。
    ///   - semantics: provider 的计价语义，默认 `.standard` 以兼容既有调用。
    /// - Returns: 本次调用的 USD 成本。
    func calculateCost(
        usage: TokenUsage,
        pricing: ModelPricing,
        semantics: PricingSemantics = .standard
    ) -> Double {
        let usesInputRatesForCacheRead = semantics == .codex
            && !pricing.cacheReadPriceIsExplicit
        let baseCacheRead = usesInputRatesForCacheRead
            ? pricing.inputPrice
            : pricing.cacheReadPrice
        let aboveCacheRead = usesInputRatesForCacheRead
            ? pricing.inputPriceAbove200k
            : pricing.cacheReadPriceAbove200k
        let cache1hBase = pricing.inputPrice * Self.cacheCreate1hInputMultiplier
        let cache1hAbove = pricing.inputPriceAbove200k.map {
            $0 * Self.cacheCreate1hInputMultiplier
        }

        let subtotal: Double
        if let threshold = pricing.longContextThreshold {
            // Codex 的 input_tokens 已扣除 cached_input_tokens，判断长上下文时需还原。
            // 对负数先归零，延续 marginal tier 对无效 token 数不计费的保护。
            let rawInput = semantics == .codex
                ? Double(max(0, usage.inputTokens))
                    + Double(max(0, usage.cacheReadInputTokens))
                : Double(max(0, usage.inputTokens))
            let isLong = rawInput > Double(threshold)
            let rate: (Double, Double?) -> Double = { base, above in
                isLong ? (above ?? base) : base
            }
            let inputRate = rate(pricing.inputPrice, pricing.inputPriceAbove200k)
            let outputRate = rate(pricing.outputPrice, pricing.outputPriceAbove200k)
            let cacheWriteRate = rate(
                pricing.cacheWritePrice,
                pricing.cacheWritePriceAbove200k
            )
            let cache1hRate = rate(cache1hBase, cache1hAbove)
            let cacheReadRate: Double
            if semantics == .codex && !pricing.cacheReadPriceIsExplicit {
                cacheReadRate = inputRate
            } else {
                cacheReadRate = rate(
                    baseCacheRead,
                    pricing.cacheReadPriceAbove200k
                )
            }
            subtotal = (
                Double(max(0, usage.inputTokens)) * inputRate
                + Double(max(0, usage.outputTokens)) * outputRate
                + Double(max(0, usage.cacheCreate5mTokens)) * cacheWriteRate
                + Double(max(0, usage.cacheCreate1hTokens)) * cache1hRate
                + Double(max(0, usage.cacheReadInputTokens)) * cacheReadRate
            ) / 1_000_000.0
        } else {
            subtotal = Self.tieredCost(
                tokens: usage.inputTokens,
                base: pricing.inputPrice,
                above: pricing.inputPriceAbove200k
            ) + Self.tieredCost(
                tokens: usage.outputTokens,
                base: pricing.outputPrice,
                above: pricing.outputPriceAbove200k
            ) + Self.tieredCost(
                tokens: usage.cacheCreate5mTokens,
                base: pricing.cacheWritePrice,
                above: pricing.cacheWritePriceAbove200k
            ) + Self.tieredCost(
                tokens: usage.cacheCreate1hTokens,
                base: cache1hBase,
                above: cache1hAbove
            ) + Self.tieredCost(
                tokens: usage.cacheReadInputTokens,
                base: baseCacheRead,
                above: aboveCacheRead
            )
        }
        return subtotal * multiplier(
            usage: usage,
            pricing: pricing,
            semantics: semantics
        )
    }

    /// 查找模型定价并计算单次调用成本。
    /// - Parameters:
    ///   - usage: 单次调用的 token 用量与服务等级。
    ///   - model: 原始模型名称，查找时不区分大小写。
    ///   - semantics: provider 的计价语义，默认 `.standard` 以兼容既有调用。
    /// - Returns: USD 成本与命中的定价；未知模型返回 `(0, nil)`。
    func calculateCost(
        usage: TokenUsage,
        model: String,
        semantics: PricingSemantics = .standard
    ) -> (cost: Double, pricing: ModelPricing?) {
        let normalized = model.lowercased()
        let pricing: ModelPricing?
        if let cached = pricingCache.cachedValue(for: normalized) {
            pricing = cached.pricing
        } else {
            pricing = pricingTable.pricing(for: normalized)
            pricingCache.store(pricing, for: normalized)
        }
        guard let pricing else {
            if missingPricingLogGate.shouldLogMiss(for: normalized) {
                logger.warning("未找到模型定价: \(model)，费用计为 $0.00")
            }
            return (0, nil)
        }
        return (
            calculateCost(usage: usage, pricing: pricing, semantics: semantics),
            pricing
        )
    }

    private static func tieredCost(
        tokens: Int,
        base: Double,
        above: Double?
    ) -> Double {
        guard tokens > 0 else { return 0 }
        if let above, tokens > marginalTierThreshold {
            return (
                Double(marginalTierThreshold) * base
                + Double(tokens - marginalTierThreshold) * above
            ) / 1_000_000.0
        }
        return Double(tokens) * base / 1_000_000.0
    }

    private func multiplier(
        usage: TokenUsage,
        pricing: ModelPricing,
        semantics: PricingSemantics
    ) -> Double {
        switch semantics {
        case .standard:
            return usage.speed == "fast" ? pricing.fastMultiplier : 1
        case .codex:
            guard usage.serviceTier == "fast" || usage.serviceTier == "priority" else {
                return 1
            }
            return pricing.fastMultiplier == 1 ? 2 : pricing.fastMultiplier
        }
    }
}
