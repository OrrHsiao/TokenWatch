import Foundation
import Testing
@testable import TokenWatch

@Suite("DashboardRangeSnapshot")
struct DashboardRangeSnapshotTests {
    @Test("秋季回拨日 dashboard 仍生成唯一的 00 到 23")
    func fallBackDayUsesTwentyFourUniqueWallClockBuckets() throws {
        let calendar = losAngelesCalendar()
        let now = try #require(calendar.date(from: DateComponents(
            year: 2026, month: 11, day: 1, hour: 12
        )))
        let stats = AggregatedStats(
            overall: .zero,
            byHour: ["2026-11-01T01": summary(total: 40)],
            byDay: [:],
            byWeek: [:],
            byMonth: [:],
            bySession: [:],
            byModel: [:],
            byProject: [:],
            dataSourceCount: 1
        )

        let snapshot = DashboardRangeSnapshot.build(
            states: [.claude: .init(
                stats: stats,
                isLoading: false,
                errorMessage: nil,
                needsAuthorization: false
            )],
            range: .day,
            now: now,
            calendar: calendar,
            language: .zhHans
        )

        #expect(snapshot.trendBuckets.count == 24)
        #expect(Set(snapshot.trendBuckets.map(\.key)).count == 24)
        #expect(snapshot.trendBuckets.first?.key == "2026-11-01T00")
        #expect(snapshot.trendBuckets.last?.key == "2026-11-01T23")
        #expect(snapshot.trendBuckets.filter { $0.key == "2026-11-01T01" }.count == 1)
        #expect(snapshot.trendBuckets.first(where: { $0.key == "2026-11-01T01" })?.totalTokens == 40)
        #expect(snapshot.totalTokens == 40)
    }

    private func losAngelesCalendar() -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/Los_Angeles")!
        return calendar
    }

    private func summary(total: Int) -> UsageSummary {
        UsageSummary(
            inputTokens: total,
            outputTokens: 0,
            cacheReadTokens: 0,
            cacheCreationTokens: 0,
            reasoningTokens: 0,
            totalTokens: total,
            cost: 0,
            entryCount: 1,
            modelBreakdown: [:]
        )
    }
}
