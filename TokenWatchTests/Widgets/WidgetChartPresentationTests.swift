import Foundation
import Testing
@testable import TokenWatch

@Suite("Widget chart presentation")
struct WidgetChartPresentationTests {
    @Test("current valid zero is data, not an empty state")
    func currentZeroRemainsARealVisualization() {
        let state = WidgetUsageEntryState.current(makeSnapshot(totalTokens: 0))
        let heatmap = WidgetChartPresentationBuilder.heatmap(for: state)
        let hourly = WidgetChartPresentationBuilder.hourlyLine(for: state)

        #expect(heatmap.message == nil)
        #expect(heatmap.totalText == "0")
        #expect(heatmap.cells.count == 154)
        #expect(heatmap.cells[0].isVisible)
        #expect(!heatmap.cells[152].isVisible)
        #expect(!heatmap.cells[153].isVisible)
        #expect(hourly.message == nil)
        #expect(hourly.totalText == "0")
        #expect(hourly.points.count == 24)
        #expect(hourly.maximumY == 1)
    }

    @Test("not-ready uses neutral full shapes and no current marker")
    func notReadyUsesNeutralVisualization() {
        let state = WidgetUsageEntryState.notReady(fallback)
        let heatmap = WidgetChartPresentationBuilder.heatmap(for: state)
        let hourly = WidgetChartPresentationBuilder.hourlyLine(for: state)
        let weekly = WidgetChartPresentationBuilder.weeklySummary(for: state)
        let budget = WidgetChartPresentationBuilder.monthlyBudget(for: state)
        let anomaly = WidgetChartPresentationBuilder.todayAnomaly(for: state)
        let project = WidgetChartPresentationBuilder.projectFocus(for: state)
        let model = WidgetChartPresentationBuilder.modelFocus(for: state)

        #expect(heatmap.message == fallback.notReadyMessage)
        #expect(heatmap.cells.count == 154)
        #expect(heatmap.cells.allSatisfy { $0.intensity == 0 && $0.isVisible })
        #expect(hourly.message == fallback.notReadyMessage)
        #expect(hourly.points.map(\.hour) == Array(0...23))
        #expect(hourly.points.allSatisfy {
            $0.totalTokens == 0 && !$0.isCurrentHour
        })
        #expect(hourly.maximumY == 1)
        #expect(hourly.currentPoint == nil)
        #expect(weekly.title == fallback.weeklySummaryTitle)
        #expect(weekly.message == fallback.notReadyMessage)
        #expect(weekly.points.count == 7)
        #expect(weekly.points.allSatisfy {
            $0.dayLabel.isEmpty && $0.totalTokens == 0 && !$0.isCurrentDay
        })
        #expect(weekly.maximumY == 1)
        #expect(budget.title == fallback.monthlyBudgetTitle)
        #expect(budget.message == fallback.notReadyMessage)
        #expect(anomaly.message == fallback.notReadyMessage)
        #expect(anomaly.points.count == 8)
        #expect(project.title == fallback.projectFocusTitle)
        #expect(project.message == fallback.notReadyMessage)
        #expect(model.title == fallback.modelFocusTitle)
        #expect(model.message == fallback.notReadyMessage)
    }

    @Test("stale data uses dated titles and hides the current-hour marker")
    func stalePresentationUsesStaleCopy() {
        let snapshot = makeSnapshot(totalTokens: 42)
        let state = WidgetUsageEntryState.stale(snapshot)
        let heatmap = WidgetChartPresentationBuilder.heatmap(for: state)
        let hourly = WidgetChartPresentationBuilder.hourlyLine(for: state)

        #expect(heatmap.title == snapshot.localizedText.heatmapTitle)
        #expect(heatmap.subtitle == snapshot.localizedText.updatedThroughTitle)
        #expect(heatmap.message == nil)
        #expect(hourly.title == snapshot.localizedText.datedUsageTitle)
        #expect(hourly.currentPoint == nil)
        #expect(hourly.points.contains { $0.isCurrentHour })
    }

    @Test("current and placeholder states use today's title and current point")
    func currentAndPlaceholderUseCurrentCopy() {
        let snapshot = makeSnapshot(totalTokens: 42)
        let states: [WidgetUsageEntryState] = [
            .current(snapshot),
            .placeholder(snapshot),
        ]

        for state in states {
            let heatmap = WidgetChartPresentationBuilder.heatmap(for: state)
            let hourly = WidgetChartPresentationBuilder.hourlyLine(for: state)
            #expect(heatmap.subtitle == nil)
            #expect(hourly.title == snapshot.localizedText.todayUsageTitle)
            #expect(hourly.currentPoint?.hour == 13)
        }
    }

    @Test("accessibility labels summarize aggregates without enumerating data points")
    func accessibilityLabelsAreAggregateOnly() {
        let snapshot = makeSnapshot(totalTokens: 42)
        let heatmap = WidgetChartPresentationBuilder.heatmap(for: .current(snapshot))
        let hourly = WidgetChartPresentationBuilder.hourlyLine(for: .current(snapshot))

        #expect(heatmap.accessibilityLabel.contains(heatmap.title))
        #expect(heatmap.accessibilityLabel.contains(heatmap.totalText))
        #expect(heatmap.accessibilityLabel.contains(
            snapshot.localizedText.updatedThroughTitle
        ))
        #expect(hourly.accessibilityLabel.contains(hourly.title))
        #expect(hourly.accessibilityLabel.contains(hourly.totalText))
        #expect(hourly.accessibilityLabel.contains(
            snapshot.localizedText.datedUsageTitle
        ))
        for cell in snapshot.heatmap.cells {
            if let dateKey = cell.dateKey {
                #expect(!heatmap.accessibilityLabel.contains(dateKey))
            }
        }
        for point in snapshot.hourlyLine.points {
            #expect(!hourly.accessibilityLabel.contains(point.hourKey))
        }
    }

    @Test("weekly summary keeps the heatmap's chronological order")
    func weeklySummaryUsesTrailingHeatmapCells() {
        let cells = (0..<10).map { index in
            WidgetHeatmapCell(
                dateKey: "source-order-\(index)",
                totalTokens: index * 10,
                intensity: 0,
                isPlaceholder: false,
                weekdayLabel: "D\(index)"
            )
        }
        let snapshot = makeSnapshot(totalTokens: 0, heatmapCells: cells)
        let current = WidgetChartPresentationBuilder.weeklySummary(for: .current(snapshot))
        let stale = WidgetChartPresentationBuilder.weeklySummary(for: .stale(snapshot))

        #expect(current.points.map(\.id) == (3..<10).map { "source-order-\($0)" })
        #expect(current.points.map(\.position) == Array(0..<7))
        #expect(current.points.map(\.dayLabel) == ["D3", "D4", "D5", "D6", "D7", "D8", "D9"])
        #expect(current.totalText == "420")
        #expect(current.maximumY == 90)
        #expect(current.points.filter(\.isCurrentDay).map(\.id) == ["source-order-9"])
        #expect(stale.subtitle == snapshot.localizedText.updatedThroughTitle)
        #expect(stale.points.allSatisfy { !$0.isCurrentDay })
    }

    @Test("monthly budget shows progress, forecast warning, and setup guidance")
    func monthlyBudgetPresentationHandlesConfiguredAndUnconfiguredStates() {
        let configured = makeSnapshot(
            totalTokens: 0,
            monthlyBudget: WidgetMonthlyBudgetSnapshot(
                monthKey: "2026-07",
                spentUSD: 80,
                budgetUSD: 100,
                forecastUSD: 120,
                title: "Monthly Budget",
                forecastTitle: "Month-end forecast",
                unconfiguredMessage: "Set a monthly budget in TokenWatch",
                forecastOverBudgetMessage: "Projected to exceed budget"
            )
        )
        let unconfigured = makeSnapshot(
            totalTokens: 0,
            monthlyBudget: WidgetMonthlyBudgetSnapshot(
                monthKey: "2026-07",
                spentUSD: 25,
                budgetUSD: nil,
                forecastUSD: 50,
                title: "Monthly Budget",
                forecastTitle: "Month-end forecast",
                unconfiguredMessage: "Set a monthly budget in TokenWatch",
                forecastOverBudgetMessage: "Projected to exceed budget"
            )
        )

        let current = WidgetChartPresentationBuilder.monthlyBudget(for: .current(configured))
        let stale = WidgetChartPresentationBuilder.monthlyBudget(for: .stale(configured))
        let setup = WidgetChartPresentationBuilder.monthlyBudget(for: .current(unconfigured))
        let missing = WidgetChartPresentationBuilder.monthlyBudget(
            for: .current(makeSnapshot(totalTokens: 0))
        )

        #expect(current.spentText == "$80.00")
        #expect(current.budgetText == "$100.00")
        #expect(current.forecastText == "Month-end forecast $120.00")
        #expect(current.progress == 0.8)
        #expect(current.forecastProgress == 1)
        #expect(current.isForecastOverBudget)
        #expect(current.message == "Projected to exceed budget")
        #expect(stale.subtitle == configured.localizedText.updatedThroughTitle)
        #expect(setup.budgetText == nil)
        #expect(setup.forecastText == nil)
        #expect(setup.progress == nil)
        #expect(setup.forecastProgress == nil)
        #expect(setup.message == "Set a monthly budget in TokenWatch")
        #expect(missing.title == fallback.monthlyBudgetTitle)
        #expect(missing.message == fallback.monthlyBudgetUnconfiguredMessage)
    }

    @Test("today check requires enough history before it reports a usage spike")
    func todayAnomalyUsesAConservativeSevenDayBaseline() {
        let elevatedSnapshot = makeSnapshot(
            totalTokens: 0,
            heatmapCells: dailyCells([100, 100, 100, 0, 0, 0, 0, 250])
        )
        let sparseSnapshot = makeSnapshot(
            totalTokens: 0,
            heatmapCells: dailyCells([100, 100, 0, 0, 0, 0, 0, 500])
        )
        let extremeSnapshot = makeSnapshot(
            totalTokens: 0,
            heatmapCells: dailyCells([1, 1, 1, 1, 1, 1, 1, Int.max])
        )

        let elevated = WidgetChartPresentationBuilder.todayAnomaly(
            for: .current(elevatedSnapshot)
        )
        let stale = WidgetChartPresentationBuilder.todayAnomaly(
            for: .stale(elevatedSnapshot)
        )
        let sparse = WidgetChartPresentationBuilder.todayAnomaly(
            for: .current(sparseSnapshot)
        )
        let extreme = WidgetChartPresentationBuilder.todayAnomaly(
            for: .current(extremeSnapshot)
        )

        #expect(elevated.totalText == "250")
        #expect(elevated.baselineTitle == fallback.weeklySummaryTitle)
        #expect(elevated.baselineText == "42")
        #expect(elevated.baselineValue == 42)
        #expect(elevated.multiplierText == "6.0×")
        #expect(elevated.differenceText == "+495%")
        #expect(elevated.hasComparableBaseline)
        #expect(elevated.isElevated)
        #expect(elevated.points.map(\.isToday) == [false, false, false, false, false, false, false, true])
        #expect(stale.subtitle == elevatedSnapshot.localizedText.updatedThroughTitle)
        #expect(!stale.hasComparableBaseline)
        #expect(!stale.isElevated)
        #expect(stale.multiplierText == nil)
        #expect(stale.differenceText == nil)
        #expect(!sparse.hasComparableBaseline)
        #expect(!sparse.isElevated)
        #expect(sparse.multiplierText == nil)
        #expect(sparse.differenceText == nil)
        #expect(extreme.differenceText == "+999%+")
    }

    @Test("focus cards use stored seven-day shares and honest empty states")
    func focusPresentationsUseStoredWindowData() {
        let snapshot = makeSnapshot(
            totalTokens: 0,
            projectFocus: WidgetProjectFocusSnapshot(
                windowStartDayKey: "2026-07-09",
                windowEndDayKey: "2026-07-15",
                windowTotalTokens: 1_000,
                topProjectName: "TokenWatch",
                topProjectTokens: 600
            ),
            modelFocus: WidgetModelFocusSnapshot(
                windowStartDayKey: "2026-07-09",
                windowEndDayKey: "2026-07-15",
                windowTotalTokens: 1_000,
                providerName: "Codex",
                modelName: "gpt-5",
                modelTokens: 400
            )
        )
        let empty = makeSnapshot(totalTokens: 0)

        let project = WidgetChartPresentationBuilder.projectFocus(for: .current(snapshot))
        let model = WidgetChartPresentationBuilder.modelFocus(for: .current(snapshot))
        let staleProject = WidgetChartPresentationBuilder.projectFocus(for: .stale(snapshot))
        let emptyModel = WidgetChartPresentationBuilder.modelFocus(for: .current(empty))

        #expect(project.projectName == "TokenWatch")
        #expect(project.totalText == "600")
        #expect(project.shareTitle == nil)
        #expect(project.shareText == "60%")
        #expect(project.progress == 0.6)
        #expect(project.message == nil)
        #expect(staleProject.subtitle == snapshot.localizedText.updatedThroughTitle)
        #expect(model.providerName == "Codex")
        #expect(model.modelName == "gpt-5")
        #expect(model.totalText == "400")
        #expect(model.shareTitle == nil)
        #expect(model.shareText == "40%")
        #expect(model.progress == 0.4)
        #expect(emptyModel.modelName == nil)
        #expect(emptyModel.message == empty.localizedText.modelFocusNoDataMessage)
    }

    private var fallback: WidgetLocalizedText {
        WidgetLocalizedText(
            heatmapTitle: "Recent 22 Weeks",
            todayUsageTitle: "Today's Usage",
            datedUsageTitle: "7/15 Usage",
            updatedThroughTitle: "Updated through 7/15",
            notReadyMessage: "Open TokenWatch to refresh data",
            monthlyBudgetTitle: "Monthly Budget",
            monthlyBudgetUnconfiguredMessage: "Set a monthly budget in TokenWatch",
            weeklySummaryTitle: "Last 7 Days",
            projectFocusTitle: "Project Usage",
            projectFocusNoDataMessage: "No project data",
            modelFocusTitle: "Primary Model",
            modelFocusNoDataMessage: "No model data"
        )
    }

    private func makeSnapshot(
        totalTokens: Int,
        heatmapCells: [WidgetHeatmapCell]? = nil,
        monthlyBudget: WidgetMonthlyBudgetSnapshot? = nil,
        projectFocus: WidgetProjectFocusSnapshot? = nil,
        modelFocus: WidgetModelFocusSnapshot? = nil
    ) -> WidgetUsageSnapshot {
        WidgetUsageSnapshot(
            schemaVersion: WidgetSharedConfiguration.schemaVersion,
            generatedAt: Date(timeIntervalSince1970: 100),
            localDayKey: "2026-07-15",
            localizedText: fallback,
            heatmap: WidgetHeatmapSnapshot(
                totalTokens: totalTokens,
                maxDailyTokens: totalTokens,
                cells: heatmapCells ?? (0..<154).map { index in
                    let isPlaceholder = index >= 152
                    return WidgetHeatmapCell(
                        dateKey: isPlaceholder ? nil : "heatmap-date-\(index)",
                        totalTokens: index == 0 ? totalTokens : 0,
                        intensity: index == 0 && totalTokens > 0 ? 4 : 0,
                        isPlaceholder: isPlaceholder
                    )
                }
            ),
            hourlyLine: WidgetHourlyLineSnapshot(
                dayKey: "2026-07-15",
                totalTokens: totalTokens,
                maxHourlyTokens: totalTokens,
                points: (0...23).map { hour in
                    WidgetHourlyPoint(
                        hour: hour,
                        hourKey: "hour-key-\(hour)",
                        hourLabel: "\(hour)",
                        totalTokens: hour == 13 ? totalTokens : 0,
                        isCurrentHour: hour == 13
                    )
                }
            ),
            monthlyBudget: monthlyBudget,
            projectFocus: projectFocus,
            modelFocus: modelFocus
        )
    }

    private func dailyCells(_ totals: [Int]) -> [WidgetHeatmapCell] {
        totals.enumerated().map { index, total in
            WidgetHeatmapCell(
                dateKey: "daily-\(index)",
                totalTokens: total,
                intensity: total > 0 ? 1 : 0,
                isPlaceholder: false
            )
        }
    }
}
