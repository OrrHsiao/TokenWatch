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
    ///   - monthlyBudgetUSD: Optional user-selected USD limit for the budget pacing widget.
    /// - Returns: A validated-shape snapshot candidate, or `nil` only if no aggregate exists.
    static func build(
        states: [ProviderID: TokenStatsViewModel.ProviderState],
        now: Date,
        calendar: Calendar,
        language: AppLanguage,
        monthlyBudgetUSD: Double? = nil
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
        let monthlyBudgetCopy = MonthlyBudgetCopy.make(language: language)

        return WidgetUsageSnapshot(
            schemaVersion: WidgetSharedConfiguration.schemaVersion,
            generatedAt: now,
            localDayKey: localDayKey,
            localizedText: WidgetLocalizedText(
                heatmapTitle: AppStrings.text(.widgetHeatmapTitle, language: language),
                todayUsageTitle: AppStrings.text(.widgetTodayUsageTitle, language: language),
                datedUsageTitle: String(
                    format: AppStrings.text(.widgetDatedUsageTitleFormat, language: language),
                    dateText
                ),
                updatedThroughTitle: String(
                    format: AppStrings.text(.widgetUpdatedThroughTitleFormat, language: language),
                    dateText
                ),
                notReadyMessage: AppStrings.text(.widgetNotReadyMessage, language: language),
                monthlyBudgetTitle: monthlyBudgetCopy.title,
                monthlyBudgetUnconfiguredMessage: monthlyBudgetCopy.unconfiguredMessage,
                weeklySummaryTitle: UsageStatsPeriod.recent7Days.title(language: language),
                projectFocusTitle: AppStrings.text(.dashboardProjectUsageTitle, language: language),
                projectFocusNoDataMessage: AppStrings.text(.dashboardNoProjectData, language: language),
                modelFocusTitle: AppStrings.text(.dashboardPrimaryModel, language: language),
                modelFocusNoDataMessage: AppStrings.text(.totalEmptyModels, language: language)
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
            ),
            monthlyBudget: makeMonthlyBudget(
                states: states,
                now: now,
                calendar: calendar,
                copy: monthlyBudgetCopy,
                monthlyBudgetUSD: monthlyBudgetUSD
            ),
            projectFocus: makeProjectFocus(
                states: states,
                now: now,
                calendar: calendar,
                language: language
            ),
            modelFocus: makeModelFocus(
                states: states,
                now: now,
                calendar: calendar
            )
        )
    }

    private static func makeProjectFocus(
        states: [ProviderID: TokenStatsViewModel.ProviderState],
        now: Date,
        calendar: Calendar,
        language: AppLanguage
    ) -> WidgetProjectFocusSnapshot {
        let dates = sevenDayDates(now: now, calendar: calendar)
        let range = DashboardRangeSnapshot.build(
            states: states,
            range: .sevenDays,
            now: now,
            calendar: calendar,
            language: language
        )
        let leadingProject = range.summary.projects.first
        let windowTotalTokens = range.summary.totalTokens
        let leadingTokens = min(
            leadingProject?.tokens ?? 0,
            windowTotalTokens
        )

        return WidgetProjectFocusSnapshot(
            windowStartDayKey: dayKey(dates.first ?? now, calendar: calendar),
            windowEndDayKey: dayKey(dates.last ?? now, calendar: calendar),
            windowTotalTokens: windowTotalTokens,
            topProjectName: leadingTokens > 0 ? leadingProject?.name : nil,
            topProjectTokens: leadingTokens
        )
    }

    private static func makeModelFocus(
        states: [ProviderID: TokenStatsViewModel.ProviderState],
        now: Date,
        calendar: Calendar
    ) -> WidgetModelFocusSnapshot {
        let dates = sevenDayDates(now: now, calendar: calendar)
        var windowTotalTokens = 0
        var modelTotals: [ModelFocusKey: Int] = [:]

        for (providerID, state) in states {
            guard let stats = state.stats else { continue }
            for date in dates {
                guard let summary = stats.byDay[dayKey(date, calendar: calendar)] else {
                    continue
                }
                windowTotalTokens = windowTotalTokens.addingSaturated(summary.totalTokens)
                for (modelName, modelSummary) in summary.modelBreakdown {
                    let trimmedName = modelName.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !trimmedName.isEmpty, modelSummary.totalTokens > 0 else {
                        continue
                    }
                    let key = ModelFocusKey(
                        providerID: providerID,
                        modelName: trimmedName
                    )
                    modelTotals[key, default: 0] = modelTotals[key, default: 0]
                        .addingSaturated(modelSummary.totalTokens)
                }
            }
        }

        let leading = modelTotals
            .filter { $0.value > 0 }
            .sorted { lhs, rhs in
                if lhs.value != rhs.value {
                    return lhs.value > rhs.value
                }
                if lhs.key.providerID.rawValue != rhs.key.providerID.rawValue {
                    return lhs.key.providerID.rawValue < rhs.key.providerID.rawValue
                }
                return lhs.key.modelName < rhs.key.modelName
            }
            .first
        let modelTokens = min(leading?.value ?? 0, windowTotalTokens)

        return WidgetModelFocusSnapshot(
            windowStartDayKey: dayKey(dates.first ?? now, calendar: calendar),
            windowEndDayKey: dayKey(dates.last ?? now, calendar: calendar),
            windowTotalTokens: windowTotalTokens,
            providerName: modelTokens > 0 ? providerName(for: leading?.key.providerID) : nil,
            modelName: modelTokens > 0 ? leading?.key.modelName : nil,
            modelTokens: modelTokens
        )
    }

    private static func makeMonthlyBudget(
        states: [ProviderID: TokenStatsViewModel.ProviderState],
        now: Date,
        calendar: Calendar,
        copy: MonthlyBudgetCopy,
        monthlyBudgetUSD: Double?
    ) -> WidgetMonthlyBudgetSnapshot {
        let monthKey = monthKey(now, calendar: calendar)
        var spentUSD = 0.0
        for state in states.values {
            guard let cost = state.stats?.byMonth[monthKey]?.cost,
                  cost.isFinite,
                  cost >= 0 else {
                continue
            }
            let next = spentUSD + cost
            spentUSD = next.isFinite ? next : Double.greatestFiniteMagnitude
        }

        let elapsedDays = max(1, calendar.component(.day, from: now))
        let daysInMonth = max(
            elapsedDays,
            calendar.range(of: .day, in: .month, for: now)?.count ?? elapsedDays
        )
        let rawForecast = spentUSD / Double(elapsedDays) * Double(daysInMonth)
        let forecastUSD = rawForecast.isFinite
            ? rawForecast
            : Double.greatestFiniteMagnitude
        let budgetUSD = monthlyBudgetUSD.flatMap {
            $0.isFinite && $0 > 0 ? $0 : nil
        }
        return WidgetMonthlyBudgetSnapshot(
            monthKey: monthKey,
            spentUSD: spentUSD,
            budgetUSD: budgetUSD,
            forecastUSD: forecastUSD,
            title: copy.title,
            forecastTitle: copy.forecastTitle,
            unconfiguredMessage: copy.unconfiguredMessage,
            forecastOverBudgetMessage: copy.forecastOverBudgetMessage
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

    private static func sevenDayDates(now: Date, calendar: Calendar) -> [Date] {
        DashboardRange.sevenDays.bucketStarts(now: now, calendar: calendar)
    }

    private static func providerName(for providerID: ProviderID?) -> String? {
        guard let providerID else { return nil }
        return ProviderRegistry.provider(for: providerID)?.displayName ?? providerID.rawValue
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

    private static func monthKey(_ date: Date, calendar: Calendar) -> String {
        let components = calendar.dateComponents([.year, .month], from: date)
        return String(
            format: "%04d-%02d",
            components.year ?? 0,
            components.month ?? 0
        )
    }

    private struct ModelFocusKey: Hashable {
        let providerID: ProviderID
        let modelName: String
    }
}
