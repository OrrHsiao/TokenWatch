import Foundation
import Testing
@testable import TokenWatch

@Suite("MonthlyTokenChartBuilder")
struct MonthlyTokenChartBuilderTests {

    @Test("生成过去十二个月窗口并按旧到新排序")
    func buildsPastTwelveMonthsInAscendingOrder() {
        let calendar = utcCalendar()

        let snapshot = MonthlyTokenChartBuilder.build(
            states: [:],
            now: date(2026, 6, 20, calendar: calendar),
            calendar: calendar
        )

        #expect(snapshot.monthBuckets.map(\.monthKey) == [
            "2025-07", "2025-08", "2025-09", "2025-10",
            "2025-11", "2025-12", "2026-01", "2026-02",
            "2026-03", "2026-04", "2026-05", "2026-06",
        ])
        #expect(snapshot.monthBuckets.map(\.monthLabel) == [
            "7月", "8月", "9月", "10月", "11月", "12月",
            "1月", "2月", "3月", "4月", "5月", "6月",
        ])
        #expect(snapshot.monthBuckets.last?.isCurrentMonth == true)
    }

    @Test("跨 provider 合并 byMonth token 并缺失月份补零")
    func sumsMonthlyTokensAcrossProvidersAndFillsMissingMonths() {
        let calendar = utcCalendar()
        let claudeStats = makeStats(byMonth: [
            "2026-05": makeSummary(total: 100),
            "2026-06": makeSummary(total: 300),
        ])
        let codexStats = makeStats(byMonth: [
            "2026-06": makeSummary(total: 50),
        ])

        let snapshot = MonthlyTokenChartBuilder.build(
            states: [
                .claude: .init(stats: claudeStats, isLoading: false, errorMessage: nil, needsAuthorization: false),
                .codex: .init(stats: codexStats, isLoading: false, errorMessage: nil, needsAuthorization: false),
                .opencode: .init(stats: nil, isLoading: false, errorMessage: nil, needsAuthorization: true),
            ],
            now: date(2026, 6, 20, calendar: calendar),
            calendar: calendar
        )

        #expect(snapshot.bucket("2026-04")?.totalTokens == 0)
        #expect(snapshot.bucket("2026-05")?.totalTokens == 100)
        #expect(snapshot.bucket("2026-06")?.totalTokens == 350)
        #expect(snapshot.totalTokens == 450)
        #expect(snapshot.maxMonthlyTokens == 350)
        #expect(snapshot.loadedProviderCount == 2)
        #expect(snapshot.unauthorizedProviderCount == 1)
    }

    @Test("跨 provider 合并 byMonth cost 并缺失月份补零")
    func sumsMonthlyCostsAcrossProvidersAndFillsMissingMonths() {
        let calendar = utcCalendar()
        let claudeStats = makeStats(byMonth: [
            "2026-05": makeSummary(total: 100, cost: 1.25),
            "2026-06": makeSummary(total: 300, cost: 2.50),
        ])
        let codexStats = makeStats(byMonth: [
            "2026-06": makeSummary(total: 50, cost: 0.75),
        ])

        let snapshot = MonthlyTokenChartBuilder.build(
            states: [
                .claude: .init(stats: claudeStats, isLoading: false, errorMessage: nil, needsAuthorization: false),
                .codex: .init(stats: codexStats, isLoading: false, errorMessage: nil, needsAuthorization: false),
            ],
            now: date(2026, 6, 20, calendar: calendar),
            calendar: calendar
        )

        #expect(snapshot.bucket("2026-04")?.totalCost == 0)
        #expect(snapshot.bucket("2026-05")?.totalCost == 1.25)
        #expect(snapshot.bucket("2026-06")?.totalCost == 3.25)
        #expect(snapshot.totalCost == 4.50)
        #expect(snapshot.maxMonthlyCost == 3.25)
    }

    @Test("normalizedHeight 保持在 0...1 且全零时稳定")
    func normalizedHeightIsBoundedAndStableForZeroData() {
        let calendar = utcCalendar()

        let emptySnapshot = MonthlyTokenChartBuilder.build(
            states: [.claude: .init(stats: makeStats(byMonth: [:]), isLoading: false, errorMessage: nil, needsAuthorization: false)],
            now: date(2026, 6, 20, calendar: calendar),
            calendar: calendar
        )

        #expect(emptySnapshot.maxMonthlyTokens == 0)
        #expect(emptySnapshot.monthBuckets.allSatisfy { $0.normalizedHeight == 0 })

        let filledSnapshot = MonthlyTokenChartBuilder.build(
            states: [.claude: .init(stats: makeStats(byMonth: [
                "2026-05": makeSummary(total: 50),
                "2026-06": makeSummary(total: 100),
            ]), isLoading: false, errorMessage: nil, needsAuthorization: false)],
            now: date(2026, 6, 20, calendar: calendar),
            calendar: calendar
        )

        #expect(filledSnapshot.bucket("2026-05")?.normalizedHeight == 0.5)
        #expect(filledSnapshot.bucket("2026-06")?.normalizedHeight == 1.0)
        #expect(filledSnapshot.monthBuckets.allSatisfy {
            $0.normalizedHeight >= 0 && $0.normalizedHeight <= 1
        })
    }

    @Test("normalizedCostHeight 保持在 0...1 且全零费用时稳定")
    func normalizedCostHeightIsBoundedAndStableForZeroData() {
        let calendar = utcCalendar()

        let emptySnapshot = MonthlyTokenChartBuilder.build(
            states: [.claude: .init(stats: makeStats(byMonth: [:]), isLoading: false, errorMessage: nil, needsAuthorization: false)],
            now: date(2026, 6, 20, calendar: calendar),
            calendar: calendar
        )

        #expect(emptySnapshot.maxMonthlyCost == 0)
        #expect(emptySnapshot.monthBuckets.allSatisfy { $0.normalizedCostHeight == 0 })

        let filledSnapshot = MonthlyTokenChartBuilder.build(
            states: [.claude: .init(stats: makeStats(byMonth: [
                "2026-05": makeSummary(total: 50, cost: 1.0),
                "2026-06": makeSummary(total: 100, cost: 4.0),
            ]), isLoading: false, errorMessage: nil, needsAuthorization: false)],
            now: date(2026, 6, 20, calendar: calendar),
            calendar: calendar
        )

        #expect(filledSnapshot.bucket("2026-05")?.normalizedCostHeight == 0.25)
        #expect(filledSnapshot.bucket("2026-06")?.normalizedCostHeight == 1.0)
        #expect(filledSnapshot.monthBuckets.allSatisfy {
            $0.normalizedCostHeight >= 0 && $0.normalizedCostHeight <= 1
        })
    }

    @Test("聚合 loading unauthorized error 状态")
    func countsProviderStatesAndCollectsErrors() {
        let calendar = utcCalendar()

        let snapshot = MonthlyTokenChartBuilder.build(
            states: [
                .claude: .init(stats: makeStats(byMonth: [:]), isLoading: false, errorMessage: nil, needsAuthorization: false),
                .codex: .init(stats: nil, isLoading: true, errorMessage: nil, needsAuthorization: false),
                .opencode: .init(stats: nil, isLoading: false, errorMessage: "OpenCode 失败", needsAuthorization: true),
            ],
            now: date(2026, 6, 20, calendar: calendar),
            calendar: calendar
        )

        #expect(snapshot.loadedProviderCount == 1)
        #expect(snapshot.loadingProviderCount == 1)
        #expect(snapshot.unauthorizedProviderCount == 1)
        #expect(snapshot.errorMessages == ["OpenCode 失败"])
    }

    @Test("按过去十二个月生成工具和模型 token 占比")
    func buildsToolAndModelTokenShareSlicesForVisibleMonths() {
        let calendar = utcCalendar()
        let claudeStats = makeStats(byMonth: [
            "2025-06": makeSummary(total: 999, modelBreakdown: ["old-model": 999]),
            "2026-05": makeSummary(total: 100, modelBreakdown: [
                "claude-sonnet": 80,
                "claude-opus": 20,
            ]),
            "2026-06": makeSummary(total: 200, modelBreakdown: ["claude-sonnet": 200]),
        ])
        let codexStats = makeStats(byMonth: [
            "2026-06": makeSummary(total: 100, modelBreakdown: ["gpt-5": 100]),
        ])

        let snapshot = MonthlyTokenChartBuilder.build(
            states: [
                .claude: .init(stats: claudeStats, isLoading: false, errorMessage: nil, needsAuthorization: false),
                .codex: .init(stats: codexStats, isLoading: false, errorMessage: nil, needsAuthorization: false),
            ],
            now: date(2026, 6, 20, calendar: calendar),
            calendar: calendar
        )

        #expect(snapshot.toolShareSlices.map(\.label) == ["Claude Code", "Codex"])
        #expect(snapshot.toolShareSlices.map(\.totalTokens) == [300, 100])
        #expect(abs((snapshot.toolShareSlices.first?.percentage ?? 0) - 0.75) < 0.0001)
        #expect(abs((snapshot.toolShareSlices.last?.percentage ?? 0) - 0.25) < 0.0001)

        #expect(snapshot.modelShareSlices.map(\.label) == ["claude-sonnet", "gpt-5", "claude-opus"])
        #expect(snapshot.modelShareSlices.map(\.totalTokens) == [280, 100, 20])
        #expect(abs((snapshot.modelShareSlices.first?.percentage ?? 0) - 0.70) < 0.0001)
        #expect(snapshot.modelShareSlices.allSatisfy { $0.percentage > 0 })
        #expect(!snapshot.modelShareSlices.map(\.label).contains("old-model"))
    }

    private func utcCalendar() -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        calendar.firstWeekday = 2
        return calendar
    }

    private func date(_ year: Int, _ month: Int, _ day: Int, calendar: Calendar) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day))!
    }

    private func makeSummary(
        total: Int,
        cost: Double = 0,
        modelBreakdown: [String: Int] = [:]
    ) -> UsageSummary {
        UsageSummary(
            inputTokens: total,
            outputTokens: 0,
            cacheReadTokens: 0,
            cacheCreationTokens: 0,
            reasoningTokens: 0,
            totalTokens: total,
            cost: cost,
            entryCount: 1,
            modelBreakdown: modelBreakdown.mapValues { modelTotal in
                UsageSummary(
                    inputTokens: modelTotal,
                    outputTokens: 0,
                    cacheReadTokens: 0,
                    cacheCreationTokens: 0,
                    reasoningTokens: 0,
                    totalTokens: modelTotal,
                    cost: 0,
                    entryCount: 1,
                    modelBreakdown: [:]
                )
            }
        )
    }

    private func makeStats(byMonth: [String: UsageSummary]) -> AggregatedStats {
        AggregatedStats(
            overall: .zero,
            byHour: [:],
            byDay: [:],
            byWeek: [:],
            byMonth: byMonth,
            bySession: [:],
            byModel: [:],
            byProject: [:],
            dataSourceCount: 1
        )
    }
}

private extension MonthlyTokenChartSnapshot {
    func bucket(_ monthKey: String) -> MonthlyTokenBucket? {
        monthBuckets.first { $0.monthKey == monthKey }
    }
}
