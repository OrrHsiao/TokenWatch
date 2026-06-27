import Foundation

/// 将主 App 内存中的 provider 状态转换为 Widget Extension 可读取的共享快照。
@MainActor
enum WidgetSnapshotBuilder {

    /// 构建小组件展示快照。
    /// - Parameters:
    ///   - states: 各 provider 的统计状态。
    ///   - now: 快照生成时间,同时作为热力图和今日折线窗口的当前时间。
    ///   - calendar: 用于稳定计算日期窗口、小时桶和当前日期的日历。
    ///   - language: 主 App 当前展示语言,Widget 会通过快照复用该语言。
    /// - Returns: 可写入 App Group 并由 Widget Extension 渲染的快照。
    static func build(
        states: [ProviderID: TokenStatsViewModel.ProviderState],
        now: Date,
        calendar: Calendar,
        language: AppLanguage
    ) -> TokenWatchWidgetSnapshot {
        let heatmapSnapshot = CalendarHeatmapBuilder.build(
            states: states,
            month: now,
            now: now,
            calendar: calendar,
            language: language
        )
        let todaySnapshot = MonthlyTokenChartBuilder.build(
            states: states,
            period: .today,
            now: now,
            calendar: calendar,
            language: language
        )
        let status = dataStatus(
            states: states,
            heatmapSnapshot: heatmapSnapshot,
            todaySnapshot: todaySnapshot
        )

        return TokenWatchWidgetSnapshot(
            generatedAt: now,
            languageIdentifier: language.rawValue,
            status: status,
            heatmap: TokenWatchWidgetHeatmapSnapshot(
                title: heatmapSnapshot.monthTitle,
                summary: TokenWatchWidgetHeatmapSummary(
                    monthTokens: heatmapSnapshot.summary.monthTokens,
                    weekTokens: heatmapSnapshot.summary.weekTokens,
                    todayTokens: heatmapSnapshot.summary.todayTokens,
                    averageDailyTokens: heatmapSnapshot.summary.averageDailyTokens
                ),
                cells: heatmapSnapshot.cells.map(widgetCell(_:)),
                maxDailyTokens: heatmapSnapshot.maxDailyTokens
            ),
            todayLine: TokenWatchWidgetTodayLineSnapshot(
                totalTokens: todaySnapshot.totalTokens,
                maxHourlyTokens: todaySnapshot.maxMonthlyTokens,
                currentHourKey: todaySnapshot.monthBuckets.first { $0.isCurrentMonth }?.monthKey,
                buckets: todaySnapshot.monthBuckets.map(widgetBucket(_:))
            )
        )
    }

    private static func dataStatus(
        states: [ProviderID: TokenStatsViewModel.ProviderState],
        heatmapSnapshot: CalendarHeatmapSnapshot,
        todaySnapshot: MonthlyTokenChartSnapshot
    ) -> TokenWatchWidgetDataStatus {
        if allKnownProvidersNeedAuthorization(states) {
            return .needsAuthorization
        }
        guard states.values.contains(where: { $0.stats != nil }) else {
            return .empty
        }
        guard heatmapSnapshot.monthTotalTokens > 0 || todaySnapshot.totalTokens > 0 else {
            return .empty
        }
        return .ready
    }

    private static func allKnownProvidersNeedAuthorization(
        _ states: [ProviderID: TokenStatsViewModel.ProviderState]
    ) -> Bool {
        guard !states.isEmpty else { return false }
        return ProviderID.allCases.allSatisfy { providerID in
            guard let state = states[providerID] else { return false }
            return state.needsAuthorization && state.stats == nil
        }
    }

    private static func widgetCell(_ cell: CalendarHeatmapCell) -> TokenWatchWidgetHeatmapCell {
        switch cell {
        case .placeholder(let id):
            return TokenWatchWidgetHeatmapCell(
                id: id,
                kind: .placeholder,
                dateKey: nil,
                totalTokens: 0,
                intensity: 0,
                isToday: false,
                isFuture: false
            )
        case .day(let day):
            return TokenWatchWidgetHeatmapCell(
                id: day.id,
                kind: .day,
                dateKey: day.dateKey,
                totalTokens: day.totalTokens,
                intensity: day.intensity,
                isToday: day.isToday,
                isFuture: day.isFuture
            )
        }
    }

    private static func widgetBucket(_ bucket: MonthlyTokenBucket) -> TokenWatchWidgetTodayLineBucket {
        TokenWatchWidgetTodayLineBucket(
            id: bucket.id,
            hourKey: bucket.monthKey,
            hourLabel: bucket.monthLabel,
            totalTokens: bucket.totalTokens,
            normalizedHeight: normalizedHeight(bucket.normalizedHeight),
            isCurrentHour: bucket.isCurrentMonth
        )
    }

    private static func normalizedHeight(_ value: Double) -> Double {
        guard value.isFinite else { return 0 }
        return min(1, max(0, value))
    }
}
