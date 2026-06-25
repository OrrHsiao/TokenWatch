import Foundation
import Testing
@testable import TokenWatch

@Suite("MonthlyTokenChartBuilder")
struct MonthlyTokenChartBuilderTests {

    @Test("生成最近十二个月窗口并按自然月排序")
    func buildsRecentTwelveMonthsInAscendingOrder() {
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
        #expect(snapshot.bucket("2026-06")?.isCurrentMonth == true)
        #expect(snapshot.bucket("2025-07")?.isCurrentMonth == false)
    }

    @Test("年初展示跨年的最近十二个月")
    func buildsRecentTwelveMonthWindowAtYearStart() {
        let calendar = utcCalendar()

        let snapshot = MonthlyTokenChartBuilder.build(
            states: [:],
            now: date(2026, 1, 5, calendar: calendar),
            calendar: calendar
        )

        #expect(snapshot.monthBuckets.map(\.monthKey) == [
            "2025-02", "2025-03", "2025-04", "2025-05",
            "2025-06", "2025-07", "2025-08", "2025-09",
            "2025-10", "2025-11", "2025-12", "2026-01",
        ])
        #expect(snapshot.bucket("2026-01")?.isCurrentMonth == true)
    }

    @Test("生成最近三十天窗口并按自然日排序")
    func buildsRecentThirtyDaysInAscendingOrder() {
        let calendar = utcCalendar()

        let snapshot = MonthlyTokenChartBuilder.build(
            states: [:],
            period: .recent30Days,
            now: date(2026, 6, 20, calendar: calendar),
            calendar: calendar
        )

        #expect(snapshot.monthBuckets.count == 30)
        #expect(snapshot.monthBuckets.first?.monthKey == "2026-05-22")
        #expect(snapshot.monthBuckets.last?.monthKey == "2026-06-20")
        #expect(snapshot.monthBuckets.first?.monthLabel == "5/22")
        #expect(snapshot.monthBuckets.last?.monthLabel == "6/20")
        #expect(snapshot.bucket("2026-06-20")?.isCurrentMonth == true)
        #expect(snapshot.bucket("2026-06-19")?.isCurrentMonth == false)
    }

    @Test("本日窗口生成当天二十四个小时桶")
    func buildsTodayWindowWithTwentyFourHourlyBuckets() {
        let calendar = utcCalendar()

        let snapshot = MonthlyTokenChartBuilder.build(
            states: [:],
            period: .today,
            now: dateTime(2026, 6, 20, hour: 14, minute: 30, calendar: calendar),
            calendar: calendar
        )

        #expect(snapshot.monthBuckets.count == 24)
        #expect(snapshot.monthBuckets.first?.monthKey == "2026-06-20T00")
        #expect(snapshot.monthBuckets.last?.monthKey == "2026-06-20T23")
        #expect(snapshot.monthBuckets.first?.monthLabel == "0时")
        #expect(snapshot.monthBuckets.last?.monthLabel == "23时")
        #expect(snapshot.bucket("2026-06-20T14")?.isCurrentMonth == true)
        #expect(snapshot.bucket("2026-06-20T13")?.isCurrentMonth == false)
    }

    @Test("英文标题、说明、空状态和小时标签")
    func periodTextUsesEnglish() {
        let calendar = utcCalendar()
        let now = dateTime(2026, 6, 20, hour: 9, minute: 0, calendar: calendar)
        let snapshot = MonthlyTokenChartBuilder.build(
            states: [:],
            period: .today,
            now: now,
            calendar: calendar,
            language: .en
        )

        #expect(UsageStatsPeriod.recent12Months.title(language: .en) == "Last 12 Months")
        #expect(UsageStatsPeriod.recent30Days.title(language: .en) == "Last 30 Days")
        #expect(UsageStatsPeriod.today.emptyDataText(language: .en) == "Today has no token data")
        #expect(snapshot.monthBuckets[9].monthLabel == "9")
    }

    @Test("跨年边界只统计最近十二个月")
    func ignoresMonthsOutsideRecentTwelveMonthWindow() {
        let calendar = utcCalendar()
        let stats = makeStats(byMonth: [
            "2025-01": makeSummary(total: 999, cost: 9.99),
            "2025-12": makeSummary(total: 200, cost: 2.00),
            "2026-01": makeSummary(total: 100, cost: 1.00),
        ])

        let snapshot = MonthlyTokenChartBuilder.build(
            states: [.claude: .init(stats: stats, isLoading: false, errorMessage: nil, needsAuthorization: false)],
            now: date(2026, 1, 5, calendar: calendar),
            calendar: calendar
        )

        #expect(snapshot.bucket("2025-01") == nil)
        #expect(snapshot.bucket("2025-12")?.totalTokens == 200)
        #expect(snapshot.bucket("2026-01")?.totalTokens == 100)
        #expect(snapshot.totalTokens == 300)
        #expect(snapshot.totalCost == 3.00)
    }

    @Test("跨 provider 合并 byMonth token 并缺失月份补零")
    func sumsMonthlyTokensAcrossProvidersAndFillsMissingMonths() {
        let calendar = utcCalendar()
        let claudeStats = makeStats(byMonth: [
            "2025-07": makeSummary(total: 80),
            "2026-05": makeSummary(total: 100),
            "2026-06": makeSummary(total: 300),
            "2026-12": makeSummary(total: 70),
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

        #expect(snapshot.bucket("2025-07")?.totalTokens == 80)
        #expect(snapshot.bucket("2026-04")?.totalTokens == 0)
        #expect(snapshot.bucket("2026-05")?.totalTokens == 100)
        #expect(snapshot.bucket("2026-06")?.totalTokens == 350)
        #expect(snapshot.bucket("2026-12") == nil)
        #expect(snapshot.totalTokens == 530)
        #expect(snapshot.maxMonthlyTokens == 350)
        #expect(snapshot.loadedProviderCount == 2)
        #expect(snapshot.unauthorizedProviderCount == 1)
    }

    @Test("跨 provider 合并 byMonth cost 并缺失月份补零")
    func sumsMonthlyCostsAcrossProvidersAndFillsMissingMonths() {
        let calendar = utcCalendar()
        let claudeStats = makeStats(byMonth: [
            "2025-07": makeSummary(total: 80, cost: 0.80),
            "2026-05": makeSummary(total: 100, cost: 1.25),
            "2026-06": makeSummary(total: 300, cost: 2.50),
            "2026-12": makeSummary(total: 70, cost: 0.40),
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

        #expect(snapshot.bucket("2025-07")?.totalCost == 0.80)
        #expect(snapshot.bucket("2026-04")?.totalCost == 0)
        #expect(snapshot.bucket("2026-05")?.totalCost == 1.25)
        #expect(snapshot.bucket("2026-06")?.totalCost == 3.25)
        #expect(snapshot.bucket("2026-12") == nil)
        #expect(snapshot.totalCost == 5.30)
        #expect(snapshot.maxMonthlyCost == 3.25)
    }

    @Test("最近三十天跨 provider 合并 byDay token 和 cost")
    func recentThirtyDaysSumsDailyTokensAndCostsAcrossProviders() {
        let calendar = utcCalendar()
        let claudeStats = makeStats(
            byDay: [
                "2026-05-21": makeSummary(total: 999, cost: 9.99),
                "2026-05-22": makeSummary(total: 80, cost: 0.80),
                "2026-06-19": makeSummary(total: 100, cost: 1.25),
                "2026-06-20": makeSummary(total: 300, cost: 2.50),
                "2026-06-21": makeSummary(total: 700, cost: 7.00),
            ],
            byMonth: [:]
        )
        let codexStats = makeStats(
            byDay: [
                "2026-06-20": makeSummary(total: 50, cost: 0.75),
            ],
            byMonth: [:]
        )

        let snapshot = MonthlyTokenChartBuilder.build(
            states: [
                .claude: .init(stats: claudeStats, isLoading: false, errorMessage: nil, needsAuthorization: false),
                .codex: .init(stats: codexStats, isLoading: false, errorMessage: nil, needsAuthorization: false),
                .opencode: .init(stats: nil, isLoading: false, errorMessage: nil, needsAuthorization: true),
            ],
            period: .recent30Days,
            now: date(2026, 6, 20, calendar: calendar),
            calendar: calendar
        )

        #expect(snapshot.bucket("2026-05-21") == nil)
        #expect(snapshot.bucket("2026-05-22")?.totalTokens == 80)
        #expect(snapshot.bucket("2026-06-18")?.totalTokens == 0)
        #expect(snapshot.bucket("2026-06-19")?.totalTokens == 100)
        #expect(snapshot.bucket("2026-06-20")?.totalTokens == 350)
        #expect(snapshot.bucket("2026-06-21") == nil)
        #expect(snapshot.totalTokens == 530)
        #expect(snapshot.totalCost == 5.30)
        #expect(snapshot.maxMonthlyTokens == 350)
        #expect(snapshot.maxMonthlyCost == 3.25)
        #expect(snapshot.loadedProviderCount == 2)
        #expect(snapshot.unauthorizedProviderCount == 1)
    }

    @Test("本日按小时汇总当天的 byHour token 和 cost")
    func todaySumsCurrentDayHourlyTokensAndCosts() {
        let calendar = utcCalendar()
        let claudeStats = makeStats(
            byHour: [
                "2026-06-19T23": makeSummary(total: 100, cost: 1.00),
                "2026-06-20T09": makeSummary(total: 120, cost: 1.25),
                "2026-06-20T14": makeSummary(total: 300, cost: 2.50),
                "2026-06-21T00": makeSummary(total: 700, cost: 7.00),
            ],
            byDay: [
                "2026-06-20": makeSummary(total: 999, cost: 9.99),
            ],
            byMonth: [:]
        )
        let codexStats = makeStats(
            byHour: [
                "2026-06-20T14": makeSummary(total: 50, cost: 0.75),
            ],
            byDay: [:],
            byMonth: [:]
        )

        let snapshot = MonthlyTokenChartBuilder.build(
            states: [
                .claude: .init(stats: claudeStats, isLoading: false, errorMessage: nil, needsAuthorization: false),
                .codex: .init(stats: codexStats, isLoading: false, errorMessage: nil, needsAuthorization: false),
                .opencode: .init(stats: nil, isLoading: false, errorMessage: nil, needsAuthorization: true),
            ],
            period: .today,
            now: dateTime(2026, 6, 20, hour: 14, minute: 30, calendar: calendar),
            calendar: calendar
        )

        #expect(snapshot.bucket("2026-06-19T23") == nil)
        #expect(snapshot.bucket("2026-06-20T08")?.totalTokens == 0)
        #expect(snapshot.bucket("2026-06-20T09")?.totalTokens == 120)
        #expect(snapshot.bucket("2026-06-20T14")?.totalTokens == 350)
        #expect(snapshot.bucket("2026-06-20T14")?.totalCost == 3.25)
        #expect(snapshot.bucket("2026-06-21T00") == nil)
        #expect(snapshot.totalTokens == 470)
        #expect(snapshot.totalCost == 4.50)
        #expect(snapshot.maxMonthlyTokens == 350)
        #expect(snapshot.loadedProviderCount == 2)
        #expect(snapshot.unauthorizedProviderCount == 1)
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

    @Test("按最近十二个月生成工具和模型 token 占比")
    func buildsToolAndModelTokenShareSlicesForVisibleMonths() {
        let calendar = utcCalendar()
        let claudeStats = makeStats(byMonth: [
            "2025-06": makeSummary(total: 999, modelBreakdown: ["old-model": 999]),
            "2025-07": makeSummary(total: 50, modelBreakdown: ["claude-haiku": 50]),
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
        #expect(snapshot.toolShareSlices.map(\.totalTokens) == [350, 100])
        #expect(abs((snapshot.toolShareSlices.first?.percentage ?? 0) - (350.0 / 450.0)) < 0.0001)
        #expect(abs((snapshot.toolShareSlices.last?.percentage ?? 0) - (100.0 / 450.0)) < 0.0001)

        #expect(snapshot.modelShareSlices.map(\.label) == ["claude-sonnet", "gpt-5", "claude-haiku", "claude-opus"])
        #expect(snapshot.modelShareSlices.map(\.totalTokens) == [280, 100, 50, 20])
        #expect(abs((snapshot.modelShareSlices.first?.percentage ?? 0) - (280.0 / 450.0)) < 0.0001)
        #expect(snapshot.modelShareSlices.allSatisfy { $0.percentage > 0 })
        #expect(!snapshot.modelShareSlices.map(\.label).contains("old-model"))
    }

    @Test("每个月 bucket 包含按模型拆分的 token 段")
    func buildsMonthlyModelSegmentsForStackedBars() {
        let calendar = utcCalendar()
        let claudeStats = makeStats(byMonth: [
            "2026-05": makeSummary(total: 120, modelBreakdown: [
                "claude-sonnet": 100,
                "claude-opus": 20,
            ]),
            "2026-06": makeSummary(total: 300, modelBreakdown: [
                "claude-sonnet": 180,
                "claude-opus": 120,
            ]),
        ])
        let codexStats = makeStats(byMonth: [
            "2026-06": makeSummary(total: 100, modelBreakdown: [
                "gpt-5": 100,
            ]),
        ])

        let snapshot = MonthlyTokenChartBuilder.build(
            states: [
                .claude: .init(stats: claudeStats, isLoading: false, errorMessage: nil, needsAuthorization: false),
                .codex: .init(stats: codexStats, isLoading: false, errorMessage: nil, needsAuthorization: false),
            ],
            now: date(2026, 6, 20, calendar: calendar),
            calendar: calendar
        )

        #expect(snapshot.bucket("2026-04")?.modelSegments == [])
        #expect(snapshot.bucket("2026-05")?.modelSegments.map(\.modelName) == ["claude-sonnet", "claude-opus"])
        #expect(snapshot.bucket("2026-05")?.modelSegments.map(\.totalTokens) == [100, 20])
        #expect(snapshot.bucket("2026-06")?.modelSegments.map(\.modelName) == ["claude-sonnet", "claude-opus", "gpt-5"])
        #expect(snapshot.bucket("2026-06")?.modelSegments.map(\.totalTokens) == [180, 120, 100])
        #expect(abs((snapshot.bucket("2026-06")?.modelSegments.first?.percentage ?? 0) - 0.45) < 0.0001)
    }

    @Test("月度柱状图模型段超过五项时合并剩余项为其他")
    func monthlyModelSegmentsMergeOverflowRowsIntoOther() {
        let calendar = utcCalendar()
        let stats = makeStats(byMonth: [
            "2026-06": makeSummary(total: 1_000, modelBreakdown: [
                "a": 500,
                "b": 200,
                "c": 120,
                "d": 80,
                "e": 60,
                "f": 40,
            ]),
        ])

        let snapshot = MonthlyTokenChartBuilder.build(
            states: [.claude: .init(stats: stats, isLoading: false, errorMessage: nil, needsAuthorization: false)],
            now: date(2026, 6, 20, calendar: calendar),
            calendar: calendar
        )

        #expect(snapshot.bucket("2026-06")?.modelSegments.map(\.modelName) == ["a", "b", "c", "d", "其他"])
        #expect(snapshot.bucket("2026-06")?.modelSegments.map(\.totalTokens) == [500, 200, 120, 80, 100])
        #expect(snapshot.bucket("2026-06")?.modelSegments.map(\.percentage) == [0.50, 0.20, 0.12, 0.08, 0.10])
    }

    @Test("英文 Other 模型和溢出 Other 使用不同内部身份")
    func englishOtherModelDoesNotCollideWithOverflowSegment() throws {
        let calendar = utcCalendar()
        let stats = makeStats(byMonth: [
            "2026-06": makeSummary(total: 4_500, modelBreakdown: [
                "a": 1_000,
                "Other": 900,
                "b": 800,
                "c": 700,
                "d": 600,
                "e": 500,
            ]),
        ])

        let snapshot = MonthlyTokenChartBuilder.build(
            states: [.claude: .init(stats: stats, isLoading: false, errorMessage: nil, needsAuthorization: false)],
            now: date(2026, 6, 20, calendar: calendar),
            calendar: calendar,
            language: .en
        )
        let segments = try #require(snapshot.bucket("2026-06")?.modelSegments)

        #expect(segments.map(\.modelName) == ["a", "Other", "b", "c", "Other"])
        #expect(Set(segments.map(\.id)).count == segments.count)
        #expect(segments.first { $0.id == "Other" && !$0.isOverflow }?.totalTokens == 900)
        #expect(segments.first { $0.id == MonthlyTokenModelSegment.overflowID && $0.isOverflow }?.totalTokens == 1_100)
    }

    @Test("每个月模型段同时包含费用拆分")
    func monthlyModelSegmentsIncludeCostBreakdown() {
        let calendar = utcCalendar()
        let stats = makeStats(byMonth: [
            "2026-06": makeSummary(total: 1_000, cost: 3.75, modelBreakdown: [
                "a": (tokens: 600, cost: 2.25),
                "b": (tokens: 400, cost: 1.50),
            ]),
        ])

        let snapshot = MonthlyTokenChartBuilder.build(
            states: [.claude: .init(stats: stats, isLoading: false, errorMessage: nil, needsAuthorization: false)],
            now: date(2026, 6, 20, calendar: calendar),
            calendar: calendar
        )

        #expect(snapshot.bucket("2026-06")?.modelSegments.map(\.modelName) == ["a", "b"])
        #expect(snapshot.bucket("2026-06")?.modelSegments.map(\.totalCost) == [2.25, 1.50])
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

    private func dateTime(
        _ year: Int,
        _ month: Int,
        _ day: Int,
        hour: Int,
        minute: Int,
        calendar: Calendar
    ) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour, minute: minute))!
    }

    private func makeSummary(
        total: Int,
        cost: Double = 0,
        modelBreakdown: [String: Int] = [:]
    ) -> UsageSummary {
        makeSummary(
            total: total,
            cost: cost,
            modelBreakdown: modelBreakdown.mapValues { (tokens: $0, cost: 0) }
        )
    }

    private func makeSummary(
        total: Int,
        cost: Double = 0,
        modelBreakdown: [String: (tokens: Int, cost: Double)]
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
            modelBreakdown: modelBreakdown.mapValues { modelSummary in
                UsageSummary(
                    inputTokens: modelSummary.tokens,
                    outputTokens: 0,
                    cacheReadTokens: 0,
                    cacheCreationTokens: 0,
                    reasoningTokens: 0,
                    totalTokens: modelSummary.tokens,
                    cost: modelSummary.cost,
                    entryCount: 1,
                    modelBreakdown: [:]
                )
            }
        )
    }

    private func makeStats(
        byHour: [String: UsageSummary] = [:],
        byDay: [String: UsageSummary] = [:],
        byMonth: [String: UsageSummary]
    ) -> AggregatedStats {
        AggregatedStats(
            overall: .zero,
            byHour: byHour,
            byDay: byDay,
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
