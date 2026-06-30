import Foundation

/// Resolves a ParsedUsageEntry cost using the local pricing table, with provider-supplied
/// cost as fallback when a model is unknown.
struct UsageCostResolver: Sendable {
    private let pricingEngine = PricingEngine()

    /// Returns the USD cost for one parsed usage entry.
    /// - Parameter entry: A parsed assistant usage entry from any provider.
    /// - Returns: Local pricing cost, or positive upstream cost when local pricing is missing.
    func resolvedCost(for entry: ParsedUsageEntry) -> Double {
        let (engineCost, pricing) = pricingEngine.calculateCost(
            usage: entry.usage,
            model: entry.model
        )
        if pricing == nil, let upstream = entry.upstreamCost, upstream > 0 {
            return upstream
        }
        return engineCost
    }
}
