import Foundation

/// Render-ready heatmap cell state without any SwiftUI or WidgetKit dependency.
struct WidgetHeatmapPresentationCell: Equatable, Sendable {
    let intensity: Int
    let isVisible: Bool
}

/// Render-ready heatmap content and aggregate accessibility copy.
struct WidgetHeatmapPresentation: Equatable, Sendable {
    let title: String
    let subtitle: String?
    let totalText: String
    let cells: [WidgetHeatmapPresentationCell]
    let message: String?
    let accessibilityLabel: String
}

/// Render-ready hourly line content and aggregate accessibility copy.
struct WidgetHourlyLinePresentation: Equatable, Sendable {
    let title: String
    let totalText: String
    let points: [WidgetHourlyPoint]
    let maximumY: Double
    let currentPoint: WidgetHourlyPoint?
    let message: String?
    let accessibilityLabel: String
}

/// One bar in the compact seven-day widget chart.
struct WidgetWeeklySummaryPoint: Equatable, Sendable, Identifiable {
    let id: String
    let position: Int
    let totalTokens: Int
    let isCurrentDay: Bool
}

/// Render-ready content for the seven-day usage summary widget.
struct WidgetWeeklySummaryPresentation: Equatable, Sendable {
    let title: String
    let subtitle: String?
    let totalText: String
    let points: [WidgetWeeklySummaryPoint]
    let maximumY: Double
    let message: String?
    let accessibilityLabel: String
}

/// Render-ready content for the monthly budget pacing widget.
struct WidgetMonthlyBudgetPresentation: Equatable, Sendable {
    let title: String
    let subtitle: String?
    let spentText: String
    let budgetText: String?
    let forecastText: String?
    let progress: Double?
    let isForecastOverBudget: Bool
    let message: String?
    let accessibilityLabel: String
}

/// One day in the compact comparison strip used by the today-usage check.
struct WidgetTodayAnomalyPoint: Equatable, Sendable, Identifiable {
    let id: String
    let position: Int
    let totalTokens: Int
    let isToday: Bool
}

/// Render-ready comparison of today's token usage against the preceding seven local days.
///
/// A comparable baseline requires at least three active days and a nonzero seven-day mean.
/// `isElevated` therefore means a conservative usage spike, not a generalized health score.
struct WidgetTodayAnomalyPresentation: Equatable, Sendable {
    let title: String
    let subtitle: String?
    let totalText: String
    let baselineText: String?
    let multiplierText: String?
    let points: [WidgetTodayAnomalyPoint]
    let maximumY: Double
    let hasComparableBaseline: Bool
    let isElevated: Bool
    let message: String?
    let accessibilityLabel: String
}

/// Render-ready seven-day project focus card.
struct WidgetProjectFocusPresentation: Equatable, Sendable {
    let title: String
    let subtitle: String?
    let projectName: String?
    let totalText: String
    let shareText: String?
    let progress: Double
    let message: String?
    let accessibilityLabel: String
}

/// Render-ready seven-day provider/model focus card.
struct WidgetModelFocusPresentation: Equatable, Sendable {
    let title: String
    let subtitle: String?
    let providerName: String?
    let modelName: String?
    let totalText: String
    let shareText: String?
    let progress: Double
    let message: String?
    let accessibilityLabel: String
}

/// Derives framework-neutral chart presentations from widget timeline states.
enum WidgetChartPresentationBuilder {
    /// Builds a fixed 22-by-7 heatmap presentation for the supplied entry state.
    static func heatmap(
        for state: WidgetUsageEntryState
    ) -> WidgetHeatmapPresentation {
        switch state {
        case .placeholder(let snapshot), .current(let snapshot):
            return heatmap(snapshot: snapshot, isStale: false)
        case .stale(let snapshot):
            return heatmap(snapshot: snapshot, isStale: true)
        case .notReady(let text):
            let totalText = WidgetChartNumberFormatter.compact(0)
            let cells = Array(
                repeating: WidgetHeatmapPresentationCell(
                    intensity: 0,
                    isVisible: true
                ),
                count: WidgetChartVisualStyle.heatmapColumns
                    * WidgetChartVisualStyle.heatmapRows
            )
            return WidgetHeatmapPresentation(
                title: text.heatmapTitle,
                subtitle: nil,
                totalText: totalText,
                cells: cells,
                message: text.notReadyMessage,
                accessibilityLabel: aggregateLabel([
                    text.heatmapTitle,
                    text.notReadyMessage,
                    totalText,
                ])
            )
        }
    }

    /// Builds a fixed 24-hour line presentation for the supplied entry state.
    static func hourlyLine(
        for state: WidgetUsageEntryState
    ) -> WidgetHourlyLinePresentation {
        switch state {
        case .placeholder(let snapshot), .current(let snapshot):
            return hourlyLine(snapshot: snapshot, isStale: false)
        case .stale(let snapshot):
            return hourlyLine(snapshot: snapshot, isStale: true)
        case .notReady(let text):
            let totalText = WidgetChartNumberFormatter.compact(0)
            let points = (0...23).map { hour in
                WidgetHourlyPoint(
                    hour: hour,
                    hourKey: "not-ready-hour-\(hour)",
                    hourLabel: "\(hour)",
                    totalTokens: 0,
                    isCurrentHour: false
                )
            }
            return WidgetHourlyLinePresentation(
                title: text.todayUsageTitle,
                totalText: totalText,
                points: points,
                maximumY: WidgetChartVisualStyle.hourlyMaximumY(
                    maxHourlyTokens: 0
                ),
                currentPoint: nil,
                message: text.notReadyMessage,
                accessibilityLabel: aggregateLabel([
                    text.todayUsageTitle,
                    text.notReadyMessage,
                    totalText,
                ])
            )
        }
    }

    /// Builds a seven-day bar presentation from the latest valid heatmap snapshot.
    static func weeklySummary(
        for state: WidgetUsageEntryState
    ) -> WidgetWeeklySummaryPresentation {
        switch state {
        case .placeholder(let snapshot), .current(let snapshot):
            return weeklySummary(snapshot: snapshot, isStale: false)
        case .stale(let snapshot):
            return weeklySummary(snapshot: snapshot, isStale: true)
        case .notReady(let text):
            let points = (0..<7).map {
                WidgetWeeklySummaryPoint(
                    id: "not-ready-weekly-\($0)",
                    position: $0,
                    totalTokens: 0,
                    isCurrentDay: false
                )
            }
            let totalText = WidgetChartNumberFormatter.compact(0)
            return WidgetWeeklySummaryPresentation(
                title: text.weeklySummaryTitle,
                subtitle: nil,
                totalText: totalText,
                points: points,
                maximumY: 1,
                message: text.notReadyMessage,
                accessibilityLabel: aggregateLabel([
                    text.weeklySummaryTitle,
                    text.notReadyMessage,
                    totalText,
                ])
            )
        }
    }

    /// Builds a monthly cost pacing presentation from the latest published budget snapshot.
    static func monthlyBudget(
        for state: WidgetUsageEntryState
    ) -> WidgetMonthlyBudgetPresentation {
        switch state {
        case .placeholder(let snapshot), .current(let snapshot):
            return monthlyBudget(snapshot: snapshot, isStale: false)
        case .stale(let snapshot):
            return monthlyBudget(snapshot: snapshot, isStale: true)
        case .notReady(let text):
            return WidgetMonthlyBudgetPresentation(
                title: "Monthly Budget",
                subtitle: nil,
                spentText: WidgetCostFormatter.usd(0),
                budgetText: nil,
                forecastText: nil,
                progress: nil,
                isForecastOverBudget: false,
                message: text.notReadyMessage,
                accessibilityLabel: aggregateLabel([
                    "Monthly Budget",
                    text.notReadyMessage,
                    WidgetCostFormatter.usd(0),
                ])
            )
        }
    }

    /// Builds a conservative usage-spike comparison from the heatmap's fixed chronology.
    static func todayAnomaly(
        for state: WidgetUsageEntryState
    ) -> WidgetTodayAnomalyPresentation {
        switch state {
        case .placeholder(let snapshot), .current(let snapshot):
            return todayAnomaly(snapshot: snapshot, isStale: false)
        case .stale(let snapshot):
            return todayAnomaly(snapshot: snapshot, isStale: true)
        case .notReady(let text):
            let points = (0..<8).map {
                WidgetTodayAnomalyPoint(
                    id: "not-ready-anomaly-\($0)",
                    position: $0,
                    totalTokens: 0,
                    isToday: false
                )
            }
            let totalText = WidgetChartNumberFormatter.compact(0)
            return WidgetTodayAnomalyPresentation(
                title: text.todayUsageTitle,
                subtitle: nil,
                totalText: totalText,
                baselineText: nil,
                multiplierText: nil,
                points: points,
                maximumY: 1,
                hasComparableBaseline: false,
                isElevated: false,
                message: text.notReadyMessage,
                accessibilityLabel: aggregateLabel([
                    text.todayUsageTitle,
                    text.notReadyMessage,
                    totalText,
                ])
            )
        }
    }

    /// Builds a privacy-preserving seven-day project focus card from a stored display name.
    static func projectFocus(
        for state: WidgetUsageEntryState
    ) -> WidgetProjectFocusPresentation {
        switch state {
        case .placeholder(let snapshot), .current(let snapshot):
            return projectFocus(snapshot: snapshot, isStale: false)
        case .stale(let snapshot):
            return projectFocus(snapshot: snapshot, isStale: true)
        case .notReady(let text):
            return WidgetProjectFocusPresentation(
                title: text.projectFocusTitle,
                subtitle: nil,
                projectName: nil,
                totalText: WidgetChartNumberFormatter.compact(0),
                shareText: nil,
                progress: 0,
                message: text.notReadyMessage,
                accessibilityLabel: aggregateLabel([
                    text.projectFocusTitle,
                    text.notReadyMessage,
                ])
            )
        }
    }

    /// Builds a provider-scoped seven-day model focus card without inferring model quality.
    static func modelFocus(
        for state: WidgetUsageEntryState
    ) -> WidgetModelFocusPresentation {
        switch state {
        case .placeholder(let snapshot), .current(let snapshot):
            return modelFocus(snapshot: snapshot, isStale: false)
        case .stale(let snapshot):
            return modelFocus(snapshot: snapshot, isStale: true)
        case .notReady(let text):
            return WidgetModelFocusPresentation(
                title: text.modelFocusTitle,
                subtitle: nil,
                providerName: nil,
                modelName: nil,
                totalText: WidgetChartNumberFormatter.compact(0),
                shareText: nil,
                progress: 0,
                message: text.notReadyMessage,
                accessibilityLabel: aggregateLabel([
                    text.modelFocusTitle,
                    text.notReadyMessage,
                ])
            )
        }
    }

    private static func heatmap(
        snapshot: WidgetUsageSnapshot,
        isStale: Bool
    ) -> WidgetHeatmapPresentation {
        let title = snapshot.localizedText.heatmapTitle
        let subtitle = isStale
            ? snapshot.localizedText.updatedThroughTitle
            : nil
        let totalText = WidgetChartNumberFormatter.compact(
            snapshot.heatmap.totalTokens
        )
        let cells = snapshot.heatmap.cells.map { cell in
            WidgetHeatmapPresentationCell(
                intensity: cell.intensity,
                isVisible: !cell.isPlaceholder
            )
        }
        return WidgetHeatmapPresentation(
            title: title,
            subtitle: subtitle,
            totalText: totalText,
            cells: cells,
            message: nil,
            accessibilityLabel: aggregateLabel([
                title,
                snapshot.localizedText.updatedThroughTitle,
                totalText,
            ])
        )
    }

    private static func hourlyLine(
        snapshot: WidgetUsageSnapshot,
        isStale: Bool
    ) -> WidgetHourlyLinePresentation {
        let title = isStale
            ? snapshot.localizedText.datedUsageTitle
            : snapshot.localizedText.todayUsageTitle
        let totalText = WidgetChartNumberFormatter.compact(
            snapshot.hourlyLine.totalTokens
        )
        let currentPoint = isStale
            ? nil
            : snapshot.hourlyLine.points.first(where: \.isCurrentHour)
        return WidgetHourlyLinePresentation(
            title: title,
            totalText: totalText,
            points: snapshot.hourlyLine.points,
            maximumY: WidgetChartVisualStyle.hourlyMaximumY(
                maxHourlyTokens: snapshot.hourlyLine.maxHourlyTokens
            ),
            currentPoint: currentPoint,
            message: nil,
            accessibilityLabel: aggregateLabel([
                title,
                isStale ? nil : snapshot.localizedText.datedUsageTitle,
                totalText,
            ])
        )
    }

    private static func weeklySummary(
        snapshot: WidgetUsageSnapshot,
        isStale: Bool
    ) -> WidgetWeeklySummaryPresentation {
        let recentCells = snapshot.heatmap.cells
            .compactMap { cell -> (key: String, totalTokens: Int)? in
                guard !cell.isPlaceholder, let key = cell.dateKey else { return nil }
                return (key, cell.totalTokens)
            }
            .suffix(7)
        let points = recentCells.enumerated().map { index, cell in
            WidgetWeeklySummaryPoint(
                id: cell.key,
                position: index,
                totalTokens: cell.totalTokens,
                isCurrentDay: !isStale && index == recentCells.count - 1
            )
        }
        let total = points.reduce(0) {
            saturatedTokenSum($0, $1.totalTokens)
        }
        let totalText = WidgetChartNumberFormatter.compact(total)
        let title = snapshot.localizedText.weeklySummaryTitle
        let subtitle = isStale ? snapshot.localizedText.updatedThroughTitle : nil
        return WidgetWeeklySummaryPresentation(
            title: title,
            subtitle: subtitle,
            totalText: totalText,
            points: points,
            maximumY: max(1, Double(points.map(\.totalTokens).max() ?? 0)),
            message: nil,
            accessibilityLabel: aggregateLabel([
                title,
                subtitle,
                totalText,
            ])
        )
    }

    private static func monthlyBudget(
        snapshot: WidgetUsageSnapshot,
        isStale: Bool
    ) -> WidgetMonthlyBudgetPresentation {
        guard let budgetSnapshot = snapshot.monthlyBudget else {
            return WidgetMonthlyBudgetPresentation(
                title: "Monthly Budget",
                subtitle: isStale ? snapshot.localizedText.updatedThroughTitle : nil,
                spentText: WidgetCostFormatter.usd(0),
                budgetText: nil,
                forecastText: nil,
                progress: nil,
                isForecastOverBudget: false,
                message: "Set a monthly budget in TokenWatch",
                accessibilityLabel: aggregateLabel([
                    "Monthly Budget",
                    WidgetCostFormatter.usd(0),
                    "Set a monthly budget in TokenWatch",
                ])
            )
        }

        let spentText = WidgetCostFormatter.usd(budgetSnapshot.spentUSD)
        let subtitle = isStale ? snapshot.localizedText.updatedThroughTitle : nil
        guard let budget = budgetSnapshot.budgetUSD else {
            return WidgetMonthlyBudgetPresentation(
                title: budgetSnapshot.title,
                subtitle: subtitle,
                spentText: spentText,
                budgetText: nil,
                forecastText: nil,
                progress: nil,
                isForecastOverBudget: false,
                message: budgetSnapshot.unconfiguredMessage,
                accessibilityLabel: aggregateLabel([
                    budgetSnapshot.title,
                    subtitle,
                    spentText,
                    budgetSnapshot.unconfiguredMessage,
                ])
            )
        }

        let forecastOverBudget = budgetSnapshot.forecastUSD > budget
        let forecastText = "\(budgetSnapshot.forecastTitle) \(WidgetCostFormatter.usd(budgetSnapshot.forecastUSD))"
        let message = forecastOverBudget
            ? budgetSnapshot.forecastOverBudgetMessage
            : nil
        return WidgetMonthlyBudgetPresentation(
            title: budgetSnapshot.title,
            subtitle: subtitle,
            spentText: spentText,
            budgetText: WidgetCostFormatter.usd(budget),
            forecastText: forecastText,
            progress: min(max(budgetSnapshot.spentUSD / budget, 0), 1),
            isForecastOverBudget: forecastOverBudget,
            message: message,
            accessibilityLabel: aggregateLabel([
                budgetSnapshot.title,
                subtitle,
                spentText,
                WidgetCostFormatter.usd(budget),
                forecastText,
                message,
            ])
        )
    }

    private static func todayAnomaly(
        snapshot: WidgetUsageSnapshot,
        isStale: Bool
    ) -> WidgetTodayAnomalyPresentation {
        let realCells = snapshot.heatmap.cells.compactMap { cell -> (key: String, totalTokens: Int)? in
            guard !cell.isPlaceholder, let key = cell.dateKey else { return nil }
            return (key, cell.totalTokens)
        }
        let comparisonCells = Array(realCells.suffix(8))
        let historyCells = Array(comparisonCells.dropLast())
        let currentCell = comparisonCells.last
        let historicalTotal = historyCells.reduce(0) {
            saturatedTokenSum($0, $1.totalTokens)
        }
        let baseline = historyCells.count == 7
            ? historicalTotal / 7
            : nil
        let activeDayCount = historyCells.filter { $0.totalTokens > 0 }.count
        let hasComparableBaseline = baseline.map {
            activeDayCount >= 3 && $0 > 0
        } ?? false
        let totalTokens = currentCell?.totalTokens ?? 0
        let multiplier = hasComparableBaseline && !isStale
            ? multiplierText(
                totalTokens: totalTokens,
                baselineTokens: baseline ?? 0
            )
            : nil
        let elevated = hasComparableBaseline
            && !isStale
            && isAtLeastTwice(totalTokens, baselineTokens: baseline ?? 0)
        let points = comparisonCells.enumerated().map { index, cell in
            WidgetTodayAnomalyPoint(
                id: cell.key,
                position: index,
                totalTokens: cell.totalTokens,
                isToday: !isStale && index == comparisonCells.count - 1
            )
        }
        let title = isStale
            ? snapshot.localizedText.datedUsageTitle
            : snapshot.localizedText.todayUsageTitle
        let subtitle = isStale
            ? snapshot.localizedText.updatedThroughTitle
            : snapshot.localizedText.weeklySummaryTitle
        let totalText = WidgetChartNumberFormatter.compact(totalTokens)
        let baselineText = baseline.map(WidgetChartNumberFormatter.compact)
        return WidgetTodayAnomalyPresentation(
            title: title,
            subtitle: subtitle,
            totalText: totalText,
            baselineText: baselineText,
            multiplierText: multiplier,
            points: points,
            maximumY: max(1, Double(points.map(\.totalTokens).max() ?? 0)),
            hasComparableBaseline: hasComparableBaseline && !isStale,
            isElevated: elevated,
            message: nil,
            accessibilityLabel: aggregateLabel([
                title,
                subtitle,
                totalText,
                multiplier,
                baselineText,
            ])
        )
    }

    private static func projectFocus(
        snapshot: WidgetUsageSnapshot,
        isStale: Bool
    ) -> WidgetProjectFocusPresentation {
        let focus = snapshot.projectFocus
        let share = share(
            selectedTokens: focus.topProjectTokens,
            totalTokens: focus.windowTotalTokens
        )
        let subtitle = isStale
            ? snapshot.localizedText.updatedThroughTitle
            : snapshot.localizedText.weeklySummaryTitle
        let hasProject = focus.topProjectName != nil && focus.topProjectTokens > 0
        let totalText = WidgetChartNumberFormatter.compact(
            hasProject ? focus.topProjectTokens : 0
        )
        let message = hasProject ? nil : snapshot.localizedText.projectFocusNoDataMessage
        return WidgetProjectFocusPresentation(
            title: snapshot.localizedText.projectFocusTitle,
            subtitle: subtitle,
            projectName: hasProject ? focus.topProjectName : nil,
            totalText: totalText,
            shareText: share.map(percentageText),
            progress: share ?? 0,
            message: message,
            accessibilityLabel: aggregateLabel([
                snapshot.localizedText.projectFocusTitle,
                subtitle,
                focus.topProjectName,
                totalText,
                share.map(percentageText),
                message,
            ])
        )
    }

    private static func modelFocus(
        snapshot: WidgetUsageSnapshot,
        isStale: Bool
    ) -> WidgetModelFocusPresentation {
        let focus = snapshot.modelFocus
        let share = share(
            selectedTokens: focus.modelTokens,
            totalTokens: focus.windowTotalTokens
        )
        let subtitle = isStale
            ? snapshot.localizedText.updatedThroughTitle
            : snapshot.localizedText.weeklySummaryTitle
        let hasModel = focus.providerName != nil
            && focus.modelName != nil
            && focus.modelTokens > 0
        let totalText = WidgetChartNumberFormatter.compact(
            hasModel ? focus.modelTokens : 0
        )
        let message = hasModel ? nil : snapshot.localizedText.modelFocusNoDataMessage
        return WidgetModelFocusPresentation(
            title: snapshot.localizedText.modelFocusTitle,
            subtitle: subtitle,
            providerName: hasModel ? focus.providerName : nil,
            modelName: hasModel ? focus.modelName : nil,
            totalText: totalText,
            shareText: share.map(percentageText),
            progress: share ?? 0,
            message: message,
            accessibilityLabel: aggregateLabel([
                snapshot.localizedText.modelFocusTitle,
                subtitle,
                focus.providerName,
                focus.modelName,
                totalText,
                share.map(percentageText),
                message,
            ])
        )
    }

    private static func multiplierText(
        totalTokens: Int,
        baselineTokens: Int
    ) -> String? {
        guard baselineTokens > 0 else { return nil }
        let multiplier = Double(totalTokens) / Double(baselineTokens)
        guard multiplier.isFinite else { return "10×+" }
        if multiplier >= 10 {
            return "10×+"
        }
        return String(
            format: "%.1f×",
            locale: Locale(identifier: "en_US_POSIX"),
            multiplier
        )
    }

    private static func isAtLeastTwice(
        _ totalTokens: Int,
        baselineTokens: Int
    ) -> Bool {
        guard baselineTokens > 0 else { return false }
        let threshold = baselineTokens.multipliedReportingOverflow(by: 2)
        return !threshold.overflow && totalTokens >= threshold.partialValue
    }

    private static func share(
        selectedTokens: Int,
        totalTokens: Int
    ) -> Double? {
        guard selectedTokens > 0, totalTokens > 0 else { return nil }
        return min(1, max(0, Double(selectedTokens) / Double(totalTokens)))
    }

    private static func percentageText(_ value: Double) -> String {
        String(
            format: "%.0f%%",
            locale: Locale(identifier: "en_US_POSIX"),
            min(1, max(0, value)) * 100
        )
    }

    private static func aggregateLabel(_ values: [String?]) -> String {
        values
            .compactMap { $0 }
            .filter { !$0.isEmpty }
            .joined(separator: ", ")
    }

    private static func saturatedTokenSum(_ lhs: Int, _ rhs: Int) -> Int {
        let result = lhs.addingReportingOverflow(rhs)
        return result.overflow ? Int.max : result.partialValue
    }
}

/// Formats the app's USD cost estimates consistently across widget renderers.
enum WidgetCostFormatter {
    static func usd(_ value: Double) -> String {
        let safeValue = value.isFinite && value >= 0 ? value : 0
        return String(
            format: "$%.2f",
            locale: Locale(identifier: "en_US_POSIX"),
            safeValue
        )
    }
}
