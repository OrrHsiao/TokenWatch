import Foundation
import Testing
@testable import TokenWatch

@Suite("Widget timeline planning")
struct WidgetTimelinePlanningTests {
    @Test("same local day is current and prior local day is stale")
    func classifiesCurrentAndStale() {
        let currentSnapshot = snapshot(dayKey: "2026-07-15")
        let staleSnapshot = snapshot(dayKey: "2026-07-14")

        #expect(WidgetTimelinePlanner.state(
            for: .available(currentSnapshot),
            at: isoDate("2026-07-15T13:00:00+08:00"),
            calendar: shanghaiCalendar,
            fallbackText: fallback
        ) == .current(currentSnapshot))
        #expect(WidgetTimelinePlanner.state(
            for: .available(staleSnapshot),
            at: isoDate("2026-07-15T00:01:00+08:00"),
            calendar: shanghaiCalendar,
            fallbackText: fallback
        ) == .stale(staleSnapshot))
    }

    @Test("missing and every invalid read use not-ready fallback")
    func missingAndInvalidAreNotReady() {
        let results: [WidgetSnapshotReadResult] = [
            .missing,
            .invalid(.unreadable),
            .invalid(.corrupt),
            .invalid(.unsupportedSchema(WidgetSharedConfiguration.schemaVersion + 1)),
        ]

        for result in results {
            #expect(WidgetTimelinePlanner.state(
                for: result,
                at: isoDate("2026-07-15T13:00:00+08:00"),
                calendar: shanghaiCalendar,
                fallbackText: fallback
            ) == .notReady(fallback))
        }
    }

    @Test("next midnight respects the 23-hour spring-forward day")
    func nextMidnightRespectsSpringForward() throws {
        let calendar = losAngelesCalendar
        let reference = try #require(calendar.date(from: DateComponents(
            year: 2026,
            month: 3,
            day: 8,
            hour: 12
        )))
        let dayStart = try #require(calendar.date(from: DateComponents(
            year: 2026,
            month: 3,
            day: 8
        )))
        let expected = try #require(calendar.date(from: DateComponents(
            year: 2026,
            month: 3,
            day: 9
        )))

        let actual = WidgetTimelinePlanner.nextLocalMidnight(
            after: reference,
            calendar: calendar
        )

        #expect(actual == expected)
        #expect(actual.timeIntervalSince(dayStart) == 23 * 60 * 60)
    }

    @Test("next midnight respects the 25-hour fall-back day")
    func nextMidnightRespectsFallBack() throws {
        let calendar = losAngelesCalendar
        let reference = try #require(calendar.date(from: DateComponents(
            year: 2026,
            month: 11,
            day: 1,
            hour: 12
        )))
        let dayStart = try #require(calendar.date(from: DateComponents(
            year: 2026,
            month: 11,
            day: 1
        )))
        let expected = try #require(calendar.date(from: DateComponents(
            year: 2026,
            month: 11,
            day: 2
        )))

        let actual = WidgetTimelinePlanner.nextLocalMidnight(
            after: reference,
            calendar: calendar
        )

        #expect(actual == expected)
        #expect(actual.timeIntervalSince(dayStart) == 25 * 60 * 60)
    }

    private var shanghaiCalendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Shanghai")!
        return calendar
    }

    private var losAngelesCalendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/Los_Angeles")!
        return calendar
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

    private func isoDate(_ string: String) -> Date {
        ISO8601DateFormatter().date(from: string)!
    }

    private func snapshot(dayKey: String) -> WidgetUsageSnapshot {
        WidgetUsageSnapshot(
            schemaVersion: WidgetSharedConfiguration.schemaVersion,
            generatedAt: isoDate("2026-07-15T05:00:00Z"),
            localDayKey: dayKey,
            localizedText: fallback,
            heatmap: WidgetHeatmapSnapshot(
                totalTokens: 42,
                maxDailyTokens: 42,
                cells: (0..<154).map { index in
                    WidgetHeatmapCell(
                        dateKey: "heatmap-date-\(index)",
                        totalTokens: index == 0 ? 42 : 0,
                        intensity: index == 0 ? 4 : 0,
                        isPlaceholder: false
                    )
                }
            ),
            hourlyLine: WidgetHourlyLineSnapshot(
                dayKey: dayKey,
                totalTokens: 42,
                maxHourlyTokens: 42,
                points: (0...23).map { hour in
                    WidgetHourlyPoint(
                        hour: hour,
                        hourKey: "hour-key-\(hour)",
                        hourLabel: "\(hour)",
                        totalTokens: hour == 13 ? 42 : 0,
                        isCurrentHour: hour == 13
                    )
                }
            )
        )
    }
}
