import Foundation

/// 总计页的完整数据快照,供 UI 直接渲染。
struct TotalStatsSnapshot: Sendable, Equatable {
    let totalTokens: Int
    let totalCost: Double
    let modelRows: [TotalStatsModelRow]
    let loadedProviderCount: Int
    let loadingProviderCount: Int
    let unauthorizedProviderCount: Int
    let errorMessages: [String]
}

/// 总计页中的单个模型用量行。
struct TotalStatsModelRow: Sendable, Equatable, Identifiable {
    let modelName: String
    let totalTokens: Int

    var id: String { modelName }
}

/// 将多 provider 状态构建为全量总计快照。
enum TotalStatsBuilder {
    /// 汇总所有已加载 provider 的全量 token、费用和模型 token。
    /// - Parameter states: 各 provider 的统计状态;没有 stats 的 provider 不参与用量求和。
    /// - Returns: 可直接渲染的总计页快照。
    static func build(states: [ProviderID: TokenStatsViewModel.ProviderState]) -> TotalStatsSnapshot {
        var totalTokens = 0
        var totalCost = 0.0
        var modelTotals: [String: Int] = [:]
        var loadedProviderCount = 0
        var loadingProviderCount = 0
        var unauthorizedProviderCount = 0
        var errorMessages: [String] = []

        for (_, state) in states {
            if state.isLoading {
                loadingProviderCount += 1
            }
            if state.needsAuthorization {
                unauthorizedProviderCount += 1
            }
            if let errorMessage = state.errorMessage {
                errorMessages.append(errorMessage)
            }
            guard let stats = state.stats else { continue }

            loadedProviderCount += 1
            totalTokens += stats.overall.totalTokens
            totalCost += stats.overall.cost
            for (model, summary) in stats.byModel {
                modelTotals[model, default: 0] += summary.totalTokens
            }
        }

        let modelRows = modelTotals
            .filter { $0.value > 0 }
            .sorted { lhs, rhs in
                if lhs.value != rhs.value {
                    return lhs.value > rhs.value
                }
                return lhs.key.localizedCaseInsensitiveCompare(rhs.key) == .orderedAscending
            }
            .map { TotalStatsModelRow(modelName: $0.key, totalTokens: $0.value) }

        return TotalStatsSnapshot(
            totalTokens: totalTokens,
            totalCost: totalCost,
            modelRows: modelRows,
            loadedProviderCount: loadedProviderCount,
            loadingProviderCount: loadingProviderCount,
            unauthorizedProviderCount: unauthorizedProviderCount,
            errorMessages: errorMessages
        )
    }
}
