import Foundation

/// Adapts the app's existing aggregate chart snapshots into the fixed widget wire format.
///
/// This producer does not rescan provider data or repeat token aggregation. It preserves
/// `UsageSummary.totalTokens` semantics, including reasoning tokens, by mapping results from
/// `CalendarHeatmapBuilder` and `MonthlyTokenChartBuilder(period: .today)` directly.
enum WidgetSnapshotBuilder {
    /// Builds render-ready widget content from the provider aggregates retained by the app.
    ///
    /// `nil` means every provider lacks a valid aggregate, allowing callers to retain a
    /// previously published snapshot. A present aggregate whose totals are all zero still
    /// produces the complete 22×7 heatmap and 24-hour line. Date keys, current-hour state,
    /// date copy, and hour labels all use the injected calendar/time zone and language rather
    /// than process defaults.
    /// - Parameters:
    ///   - states: Current provider states; entries without `stats` are ignored by the reused builders.
    ///   - now: Generation time and local wall-clock date used by both chart snapshots.
    ///   - calendar: Calendar carrying the caller-selected time zone and weekday ordering.
    ///   - language: Resolved app language used to freeze all widget render copy.
    /// - Returns: A validated-shape snapshot candidate, or `nil` only if no aggregate exists.
    static func build(
        states: [ProviderID: TokenStatsViewModel.ProviderState],
        now: Date,
        calendar: Calendar,
        language: AppLanguage
    ) -> WidgetUsageSnapshot? {
        guard states.values.contains(where: { $0.stats != nil }) else {
            return nil
        }

        let heatmap = CalendarHeatmapBuilder.build(
            states: states,
            month: now,
            now: now,
            calendar: calendar,
            language: language
        )
        let hourly = MonthlyTokenChartBuilder.build(
            states: states,
            period: .today,
            now: now,
            calendar: calendar,
            language: language
        )
        let dateText = localizedMonthDay(now, calendar: calendar, language: language)
        let localDayKey = dayKey(now, calendar: calendar)

        return WidgetUsageSnapshot(
            schemaVersion: WidgetSharedConfiguration.schemaVersion,
            generatedAt: now,
            localDayKey: localDayKey,
            localizedText: WidgetLocalizedText(
                heatmapTitle: heatmap.monthTitle,
                todayUsageTitle: AppStrings.text(.widgetTodayUsageTitle, language: language),
                datedUsageTitle: String(
                    format: AppStrings.text(.widgetDatedUsageTitleFormat, language: language),
                    dateText
                ),
                updatedThroughTitle: String(
                    format: AppStrings.text(.widgetUpdatedThroughTitleFormat, language: language),
                    dateText
                ),
                notReadyMessage: AppStrings.text(.widgetNotReadyMessage, language: language)
            ),
            heatmap: WidgetHeatmapSnapshot(
                totalTokens: heatmap.monthTotalTokens,
                maxDailyTokens: heatmap.maxDailyTokens,
                cells: heatmap.cells.map(mapHeatmapCell)
            ),
            hourlyLine: WidgetHourlyLineSnapshot(
                dayKey: localDayKey,
                totalTokens: hourly.totalTokens,
                maxHourlyTokens: hourly.maxMonthlyTokens,
                points: hourly.monthBuckets.enumerated().map { hour, bucket in
                    WidgetHourlyPoint(
                        hour: hour,
                        hourKey: bucket.monthKey,
                        hourLabel: bucket.monthLabel,
                        totalTokens: bucket.totalTokens,
                        isCurrentHour: bucket.isCurrentMonth
                    )
                }
            )
        )
    }

    private static func mapHeatmapCell(_ cell: CalendarHeatmapCell) -> WidgetHeatmapCell {
        switch cell {
        case .placeholder:
            return WidgetHeatmapCell(
                dateKey: nil,
                totalTokens: 0,
                intensity: 0,
                isPlaceholder: true
            )
        case .day(let day):
            return WidgetHeatmapCell(
                dateKey: day.dateKey,
                totalTokens: day.totalTokens,
                intensity: day.intensity,
                isPlaceholder: false
            )
        }
    }

    private static func localizedMonthDay(
        _ date: Date,
        calendar: Calendar,
        language: AppLanguage
    ) -> String {
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.locale = Locale(identifier: language.localeIdentifier)
        formatter.setLocalizedDateFormatFromTemplate("Md")
        return formatter.string(from: date)
    }

    private static func dayKey(_ date: Date, calendar: Calendar) -> String {
        let components = calendar.dateComponents([.year, .month, .day], from: date)
        return String(
            format: "%04d-%02d-%02d",
            components.year ?? 0,
            components.month ?? 0,
            components.day ?? 0
        )
    }
}
