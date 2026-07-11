import Foundation
import Testing
@testable import TokenWatch

@Suite("DashboardRangeSnapshot")
struct DashboardRangeSnapshotTests {
    @Test("跨 provider 极值在窗口与全量快照中饱和")
    func extremeProviderSummariesSaturateInWindowAndAllSnapshots() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let now = try #require(calendar.date(from: DateComponents(
            year: 2026, month: 6, day: 13, hour: 12
        )))
        let states: [ProviderID: TokenStatsViewModel.ProviderState] = [
            .claude: .init(
                stats: stats(
                    summary: summary(total: .max, project: "/first/shared"),
                    hourKey: "2026-06-13T12",
                    monthKey: "2026-06"
                ),
                isLoading: false,
                errorMessage: nil,
                needsAuthorization: false
            ),
            .codex: .init(
                stats: stats(
                    summary: summary(total: 1, project: "/second/shared"),
                    hourKey: "2026-06-13T12",
                    monthKey: "2026-06"
                ),
                isLoading: false,
                errorMessage: nil,
                needsAuthorization: false
            ),
        ]

        let window = DashboardRangeSnapshot.build(
            states: states,
            range: .day,
            now: now,
            calendar: calendar,
            language: .zhHans
        )
        let all = DashboardRangeSnapshot.build(
            states: states,
            range: .all,
            now: now,
            calendar: calendar,
            language: .zhHans
        )

        #expect(window.totalTokens == Int.max)
        #expect(window.summary.inputTokens == Int.max)
        #expect(window.summary.projects.first { $0.name == "shared" }?.tokens == Int.max)
        #expect(window.toolShareSlices.count == 2)
        #expect(window.toolShareSlices.allSatisfy { $0.percentage.isFinite })
        #expect(abs(window.toolShareSlices.reduce(0) { $0 + $1.percentage } - 1) < 0.000_001)
        #expect(window.toolShareSlices.allSatisfy { 0...1 ~= $0.percentage })
        #expect(all.totalTokens == Int.max)
        #expect(all.summary.inputTokens == Int.max)
        #expect(all.summary.projects.first { $0.name == "shared" }?.tokens == Int.max)
        #expect(all.toolShareSlices.allSatisfy { $0.percentage.isFinite })
        #expect(abs(all.toolShareSlices.reduce(0) { $0 + $1.percentage } - 1) < 0.000_001)
        #expect(all.toolShareSlices.allSatisfy { 0...1 ~= $0.percentage })
    }

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

    private func summary(total: Int, project: String? = nil) -> UsageSummary {
        let projectSummary = UsageSummary(
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
        return UsageSummary(
            inputTokens: total,
            outputTokens: 0,
            cacheReadTokens: 0,
            cacheCreationTokens: 0,
            reasoningTokens: 0,
            totalTokens: total,
            cost: 0,
            entryCount: 1,
            modelBreakdown: [:],
            projectBreakdown: project.map { [$0: projectSummary] } ?? [:]
        )
    }

    private func stats(
        summary: UsageSummary,
        hourKey: String,
        monthKey: String
    ) -> AggregatedStats {
        AggregatedStats(
            overall: summary,
            byHour: [hourKey: summary],
            byDay: [:],
            byWeek: [:],
            byMonth: [monthKey: summary],
            bySession: [:],
            byModel: [:],
            byProject: summary.projectBreakdown,
            dataSourceCount: 1
        )
    }
}
