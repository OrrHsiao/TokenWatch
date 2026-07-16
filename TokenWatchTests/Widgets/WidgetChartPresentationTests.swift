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

    private var fallback: WidgetLocalizedText {
        WidgetLocalizedText(
            heatmapTitle: "Recent 22 Weeks",
            todayUsageTitle: "Today's Usage",
            datedUsageTitle: "7/15 Usage",
            updatedThroughTitle: "Updated through 7/15",
            notReadyMessage: "Open TokenWatch to refresh data"
        )
    }

    private func makeSnapshot(totalTokens: Int) -> WidgetUsageSnapshot {
        WidgetUsageSnapshot(
            schemaVersion: WidgetSharedConfiguration.schemaVersion,
            generatedAt: Date(timeIntervalSince1970: 100),
            localDayKey: "2026-07-15",
            localizedText: fallback,
            heatmap: WidgetHeatmapSnapshot(
                totalTokens: totalTokens,
                maxDailyTokens: totalTokens,
                cells: (0..<154).map { index in
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
            )
        )
    }
}
