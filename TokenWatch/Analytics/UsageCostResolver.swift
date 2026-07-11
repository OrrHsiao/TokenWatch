import Foundation

/// 以 ccusage 默认 Auto 模式解析单条记录成本。
struct UsageCostResolver: Sendable {
    private let pricingEngine: PricingEngine

    init(pricingEngine: PricingEngine = PricingEngine()) {
        self.pricingEngine = pricingEngine
    }

    /// 按 upstream-first 与 provider 语义返回单条记录的 USD 成本。
    /// - Parameter entry: 任一 provider 解析后的单条 assistant usage。
    /// - Returns: 非 nil upstream cost，或本地定价结果；未知模型返回 0。
    func resolvedCost(for entry: ParsedUsageEntry) -> Double {
        if let upstreamCost = entry.upstreamCost {
            return upstreamCost
        }
        if entry.provider == .opencode {
            for candidate in OpenCodePricingCandidateResolver.candidates(
                modelID: entry.upstreamModelID,
                providerID: entry.upstreamProviderID
            ) {
                let result = pricingEngine.calculateCost(
                    usage: entry.usage,
                    model: candidate,
                    semantics: .standard
                )
                if result.cost > 0 { return result.cost }
            }
            return 0
        }
        let semantics: PricingSemantics = entry.provider == .codex
            ? .codex
            : .standard
        return pricingEngine.calculateCost(
            usage: entry.usage,
            model: entry.model,
            semantics: semantics
        ).cost
    }
}
