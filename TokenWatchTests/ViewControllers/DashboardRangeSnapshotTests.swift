import Foundation
import Testing
@testable import TokenWatch

@Suite("DashboardRangeSnapshot")
struct DashboardRangeSnapshotTests {
    @Test("未知的模型和项目名称使用当前语言")
    func unknownNamesUseSelectedLanguage() {
        #expect(
            DashboardRangeSnapshot.localizedUnknownName("unknown", language: .zhHans) == "未知"
        )
        #expect(
            DashboardRangeSnapshot.localizedUnknownName("unknown", language: .en) == "Unknown"
        )
        #expect(
            DashboardRangeSnapshot.displayProjectName("unknown", language: .zhHans) == "未知"
        )
    }

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

    @Test("模型消耗排行跟随选中的时间范围并按 Token 降序排序")
    func modelRowsFollowSelectedRangeAndAreOrderedByTokensDescending() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let now = try #require(calendar.date(from: DateComponents(
            year: 2026, month: 6, day: 20, hour: 12
        )))

        let todaySummary = summary(models: [
            "claude-3-5-sonnet": (tokens: 1_000, cost: 1.5),
            "gpt-4o": (tokens: 500, cost: 1.0),
            "zero-token-model": (tokens: 0, cost: 0.0),
        ])
        let threeDaysAgoSummary = summary(models: [
            "claude-3-opus": (tokens: 2_000, cost: 10.0),
        ])
        let twentyDaysAgoSummary = summary(models: [
            "gemini-pro": (tokens: 3_000, cost: 3.0),
        ])
        let oldMonthSummary = summary(models: [
            "legacy-model": (tokens: 8_000, cost: 8.0),
        ])

        var byDay: [String: UsageSummary] = [:]
        byDay["2026-06-20"] = todaySummary
        byDay["2026-06-17"] = threeDaysAgoSummary
        byDay["2026-06-01"] = twentyDaysAgoSummary

        var byHour: [String: UsageSummary] = [:]
        byHour["2026-06-20T12"] = todaySummary

        let allModels = [
            "claude-3-5-sonnet": modelSummary(tokens: 1_000, cost: 1.5),
            "gpt-4o": modelSummary(tokens: 500, cost: 1.0),
            "zero-token-model": modelSummary(tokens: 0, cost: 0.0),
            "claude-3-opus": modelSummary(tokens: 2_000, cost: 10.0),
            "gemini-pro": modelSummary(tokens: 3_000, cost: 3.0),
            "legacy-model": modelSummary(tokens: 8_000, cost: 8.0),
        ]

        let stats = AggregatedStats(
            overall: UsageSummary(
                inputTokens: 14_500,
                outputTokens: 0,
                cacheReadTokens: 0,
                cacheCreationTokens: 0,
                reasoningTokens: 0,
                totalTokens: 14_500,
                cost: 23.5,
                entryCount: 5,
                modelBreakdown: allModels
            ),
            byHour: byHour,
            byDay: byDay,
            byWeek: [:],
            byMonth: [
                "2026-06": summary(models: [
                    "claude-3-5-sonnet": (tokens: 1_000, cost: 1.5),
                    "gpt-4o": (tokens: 500, cost: 1.0),
                    "claude-3-opus": (tokens: 2_000, cost: 10.0),
                    "gemini-pro": (tokens: 3_000, cost: 3.0),
                ]),
                "2026-04": oldMonthSummary,
            ],
            bySession: [:],
            byModel: allModels,
            byProject: [:],
            dataSourceCount: 1
        )

        let providerStates: [ProviderID: TokenStatsViewModel.ProviderState] = [
            .claude: .init(
                stats: stats,
                isLoading: false,
                errorMessage: nil,
                needsAuthorization: false
            )
        ]

        let daySnapshot = DashboardRangeSnapshot.build(
            states: providerStates,
            range: .day,
            now: now,
            calendar: calendar,
            language: .zhHans
        )
        #expect(daySnapshot.modelRows.map(\.modelName) == ["claude-3-5-sonnet", "gpt-4o"])
        #expect(daySnapshot.modelRows.first?.totalTokens == 1_000)
        #expect(daySnapshot.modelRows.first?.totalCost == 1.5)

        let sevenDaySnapshot = DashboardRangeSnapshot.build(
            states: providerStates,
            range: .sevenDays,
            now: now,
            calendar: calendar,
            language: .zhHans
        )
        #expect(sevenDaySnapshot.modelRows.map(\.modelName) == ["claude-3-opus", "claude-3-5-sonnet", "gpt-4o"])

        let monthSnapshot = DashboardRangeSnapshot.build(
            states: providerStates,
            range: .month,
            now: now,
            calendar: calendar,
            language: .zhHans
        )
        #expect(monthSnapshot.modelRows.map(\.modelName) == ["gemini-pro", "claude-3-opus", "claude-3-5-sonnet", "gpt-4o"])

        let allSnapshot = DashboardRangeSnapshot.build(
            states: providerStates,
            range: .all,
            now: now,
            calendar: calendar,
            language: .zhHans
        )
        #expect(allSnapshot.modelRows.map(\.modelName) == ["legacy-model", "gemini-pro", "claude-3-opus", "claude-3-5-sonnet", "gpt-4o"])
    }

    private func modelSummary(tokens: Int, cost: Double = 0.0) -> UsageSummary {
        UsageSummary(
            inputTokens: tokens,
            outputTokens: 0,
            cacheReadTokens: 0,
            cacheCreationTokens: 0,
            reasoningTokens: 0,
            totalTokens: tokens,
            cost: cost,
            entryCount: 1,
            modelBreakdown: [:]
        )
    }

    private func summary(models: [String: (tokens: Int, cost: Double)]) -> UsageSummary {
        var breakdown: [String: UsageSummary] = [:]
        var totalTokens = 0
        var totalCost = 0.0
        for (name, data) in models {
            breakdown[name] = modelSummary(tokens: data.tokens, cost: data.cost)
            totalTokens += data.tokens
            totalCost += data.cost
        }
        return UsageSummary(
            inputTokens: totalTokens,
            outputTokens: 0,
            cacheReadTokens: 0,
            cacheCreationTokens: 0,
            reasoningTokens: 0,
            totalTokens: totalTokens,
            cost: totalCost,
            entryCount: models.count,
            modelBreakdown: breakdown
        )
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
