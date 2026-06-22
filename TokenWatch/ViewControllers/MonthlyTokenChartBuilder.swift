import Foundation

/// 过去 12 个月 token 柱状图的完整数据快照,供 UI 直接渲染。
struct MonthlyTokenChartSnapshot: Sendable, Equatable {
    let monthBuckets: [MonthlyTokenBucket]
    let totalTokens: Int
    let totalCost: Double
    let maxMonthlyTokens: Int
    let maxMonthlyCost: Double
    let toolShareSlices: [UsageShareSlice]
    let modelShareSlices: [UsageShareSlice]
    let loadedProviderCount: Int
    let loadingProviderCount: Int
    let unauthorizedProviderCount: Int
    let errorMessages: [String]
}

/// token 占比饼图的一块数据。
struct UsageShareSlice: Sendable, Equatable, Identifiable {
    let id: String
    let label: String
    let totalTokens: Int
    let percentage: Double
}

/// 单月 token 柱状图数据。
struct MonthlyTokenBucket: Sendable, Equatable, Identifiable {
    let id: String
    let monthKey: String
    let monthLabel: String
    let totalTokens: Int
    let totalCost: Double
    let normalizedHeight: Double
    let normalizedCostHeight: Double
    let isCurrentMonth: Bool
}

/// 将多 provider 状态构建为过去 12 个月的 token 柱状图快照。
enum MonthlyTokenChartBuilder {
    private static let monthCount = 12

    /// 构建以 `now` 所在月份为终点的过去 12 个月 token 快照。
    /// - Parameters:
    ///   - states: 各 provider 的统计状态;没有 stats 的 provider 不参与 token 求和。
    ///   - now: 当前日期,用于确定当前月和窗口终点。
    ///   - calendar: 调用方指定的日历配置,用于稳定测试和本地月份计算。
    /// - Returns: 可直接渲染的月度 token 图表快照。
    static func build(
        states: [ProviderID: TokenStatsViewModel.ProviderState],
        now: Date,
        calendar: Calendar
    ) -> MonthlyTokenChartSnapshot {
        let currentMonthStart = calendar.dateInterval(of: .month, for: now)?.start
            ?? calendar.startOfDay(for: now)
        let monthStarts = (0..<monthCount).reversed().compactMap { offset in
            calendar.date(byAdding: .month, value: -offset, to: currentMonthStart)
        }
        let monthKeys = monthStarts.map { monthKey(for: $0, calendar: calendar) }
        var totals = Dictionary(uniqueKeysWithValues: monthKeys.map { ($0, 0) })
        var costs = Dictionary(uniqueKeysWithValues: monthKeys.map { ($0, 0.0) })
        var toolTotals: [ProviderID: Int] = [:]
        var modelTotals: [String: Int] = [:]

        var loadedProviderCount = 0
        var loadingProviderCount = 0
        var unauthorizedProviderCount = 0
        var errorMessages: [String] = []

        for (providerID, state) in states {
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

            var providerVisibleTokens = 0
            for monthKey in monthKeys {
                let summary = stats.byMonth[monthKey]
                let monthTokens = summary?.totalTokens ?? 0
                providerVisibleTokens += monthTokens
                totals[monthKey, default: 0] += monthTokens
                costs[monthKey, default: 0] += summary?.cost ?? 0

                for (model, modelSummary) in summary?.modelBreakdown ?? [:] {
                    modelTotals[model, default: 0] += modelSummary.totalTokens
                }
            }
            if providerVisibleTokens > 0 {
                toolTotals[providerID, default: 0] += providerVisibleTokens
            }
        }

        let maxMonthlyTokens = totals.values.max() ?? 0
        let maxMonthlyCost = costs.values.max() ?? 0
        let buckets = monthStarts.map { monthStart in
            let key = monthKey(for: monthStart, calendar: calendar)
            let totalTokens = totals[key, default: 0]
            let totalCost = costs[key, default: 0]
            let normalizedHeight = maxMonthlyTokens > 0
                ? Double(totalTokens) / Double(maxMonthlyTokens)
                : 0
            let normalizedCostHeight = maxMonthlyCost > 0
                ? totalCost / maxMonthlyCost
                : 0
            return MonthlyTokenBucket(
                id: key,
                monthKey: key,
                monthLabel: monthLabel(for: monthStart, calendar: calendar),
                totalTokens: totalTokens,
                totalCost: totalCost,
                normalizedHeight: normalizedHeight,
                normalizedCostHeight: normalizedCostHeight,
                isCurrentMonth: key == monthKey(for: currentMonthStart, calendar: calendar)
            )
        }

        return MonthlyTokenChartSnapshot(
            monthBuckets: buckets,
            totalTokens: buckets.reduce(0) { $0 + $1.totalTokens },
            totalCost: buckets.reduce(0) { $0 + $1.totalCost },
            maxMonthlyTokens: maxMonthlyTokens,
            maxMonthlyCost: maxMonthlyCost,
            toolShareSlices: buildToolShareSlices(toolTotals),
            modelShareSlices: buildModelShareSlices(modelTotals),
            loadedProviderCount: loadedProviderCount,
            loadingProviderCount: loadingProviderCount,
            unauthorizedProviderCount: unauthorizedProviderCount,
            errorMessages: errorMessages
        )
    }

    private static func monthKey(for date: Date, calendar: Calendar) -> String {
        let components = calendar.dateComponents([.year, .month], from: date)
        return String(format: "%04d-%02d", components.year ?? 0, components.month ?? 0)
    }

    private static func monthLabel(for date: Date, calendar: Calendar) -> String {
        let month = calendar.component(.month, from: date)
        return "\(month)月"
    }

    private static func buildToolShareSlices(_ totals: [ProviderID: Int]) -> [UsageShareSlice] {
        let values = totals.map { providerID, totalTokens in
            (
                id: providerID.rawValue,
                label: ProviderRegistry.provider(for: providerID)?.displayName ?? providerID.rawValue,
                totalTokens: totalTokens
            )
        }
        return buildShareSlices(values)
    }

    private static func buildModelShareSlices(_ totals: [String: Int]) -> [UsageShareSlice] {
        let values = totals.map { model, totalTokens in
            (id: model, label: model, totalTokens: totalTokens)
        }
        return buildShareSlices(values)
    }

    private static func buildShareSlices(
        _ values: [(id: String, label: String, totalTokens: Int)]
    ) -> [UsageShareSlice] {
        let visibleValues = values.filter { $0.totalTokens > 0 }
        let grandTotal = visibleValues.reduce(0) { $0 + $1.totalTokens }
        guard grandTotal > 0 else { return [] }

        return visibleValues.sorted { lhs, rhs in
            if lhs.totalTokens != rhs.totalTokens {
                return lhs.totalTokens > rhs.totalTokens
            }
            return lhs.label.localizedCaseInsensitiveCompare(rhs.label) == .orderedAscending
        }.map { value in
            UsageShareSlice(
                id: value.id,
                label: value.label,
                totalTokens: value.totalTokens,
                percentage: Double(value.totalTokens) / Double(grandTotal)
            )
        }
    }
}
