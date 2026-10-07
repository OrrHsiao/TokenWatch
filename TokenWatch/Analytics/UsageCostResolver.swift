import Foundation

/// 以 ccusage 默认 Auto 模式解析单条记录成本。
struct UsageCostResolver: Sendable {
    private let pricingEngine: PricingEngine
    private let deepSeekHarnessPriceCatalog: DeepSeekHarnessPriceCatalogStore

    init(
        pricingEngine: PricingEngine = PricingEngine(),
        deepSeekHarnessPriceCatalog: DeepSeekHarnessPriceCatalogStore = .shared
    ) {
        self.pricingEngine = pricingEngine
        self.deepSeekHarnessPriceCatalog = deepSeekHarnessPriceCatalog
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
        if entry.provider == .deepSeekHarness {
            return resolvedDeepSeekHarnessCost(for: entry)
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

    /// DSH 记录的本地计价。
    ///
    /// DSH 不在日志里记录费用，且内置定价表没有 DeepSeek 条目，因此优先使用
    /// DSH 自带 pi-ai 定价目录（按 route 精确、模型名兜底、次版本归并），
    /// 再回落到内置表；全部未命中时返回 0，并由 `PricingEngine` 记录一次
    /// 「未找到模型定价」告警。
    private func resolvedDeepSeekHarnessCost(for entry: ParsedUsageEntry) -> Double {
        let candidates = DeepSeekHarnessPricingCandidateResolver.candidates(
            modelID: entry.upstreamModelID ?? entry.model,
            providerID: entry.upstreamProviderID
        )
        for candidate in candidates {
            guard let pricing = deepSeekHarnessPriceCatalog.pricing(forKey: candidate) else {
                continue
            }
            return pricingEngine.calculateCost(usage: entry.usage, pricing: pricing)
        }
        for candidate in candidates {
            let result = pricingEngine.calculateCost(
                usage: entry.usage,
                model: candidate,
                semantics: .standard
            )
            if result.cost > 0 { return result.cost }
        }
        return 0
    }
}
