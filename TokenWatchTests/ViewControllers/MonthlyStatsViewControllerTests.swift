import AppKit
import Foundation
import Testing
@testable import TokenWatch

@Suite("MonthlyStatsViewController")
struct MonthlyStatsViewControllerTests {

    @MainActor
    @Test("加载后展示标题、说明和总量")
    func rendersTitleSubtitleAndTotal() throws {
        let calendar = utcCalendar()
        let viewController = MonthlyStatsViewController(
            stateProvider: {
                [.claude: .init(
                    stats: makeStats(byMonth: [
                        "2026-06": makeSummary(
                            total: 1_200_000,
                            cost: 12.5,
                            modelBreakdown: ["claude-sonnet": 1_200_000]
                        )
                    ]),
                    isLoading: false,
                    errorMessage: nil,
                    needsAuthorization: false
                )]
            },
            nowProvider: { date(2026, 6, 20, calendar: calendar) },
            calendar: calendar
        )

        viewController.loadViewIfNeeded()

        let labels = viewController.view.allDescendants(ofType: NSTextField.self).map(\.stringValue)
        #expect(labels.contains("最近 12 个月"))
        #expect(labels.contains("最近 12 个月,跨 provider 汇总"))
        #expect(labels.contains("Token 用量"))
        #expect(labels.contains("费用"))
        #expect(labels.contains("1.2M"))
        #expect(labels.contains("$12.50"))

        let chartView = try #require(viewController.view.firstDescendant(ofType: MonthlyTokenChartView.self))
        #expect(chartView.debugBarCount == 12)

        let costChartView = try #require(viewController.view.firstDescendant(ofType: MonthlyCostChartView.self))
        #expect(costChartView.debugBarCount == 12)

        let pieViews = viewController.view.allDescendants(ofType: UsageSharePieChartView.self)
        #expect(pieViews.map(\.debugTitle) == ["工具占比", "模型占比"])
        #expect(pieViews.first?.debugSliceLabels == ["Claude Code"])
        #expect(pieViews.last?.debugSliceLabels == ["claude-sonnet"])
    }

    @MainActor
    @Test("最近三十天配置展示标题、说明和三十个日桶")
    func rendersRecentThirtyDaysTitleSubtitleAndDailyBuckets() throws {
        let calendar = utcCalendar()
        let viewController = MonthlyStatsViewController(
            period: .recent30Days,
            stateProvider: {
                [.claude: .init(
                    stats: makeStats(byDay: [
                        "2026-06-20": makeSummary(
                            total: 500_000,
                            cost: 2.5,
                            modelBreakdown: ["claude-sonnet": 500_000]
                        )
                    ], byMonth: [:]),
                    isLoading: false,
                    errorMessage: nil,
                    needsAuthorization: false
                )]
            },
            nowProvider: { date(2026, 6, 20, calendar: calendar) },
            calendar: calendar
        )

        viewController.loadViewIfNeeded()

        let labels = viewController.view.allDescendants(ofType: NSTextField.self).map(\.stringValue)
        #expect(labels.contains("最近 30 天"))
        #expect(labels.contains("最近 30 天,跨 provider 汇总"))
        #expect(labels.contains("0.5M"))
        #expect(labels.contains("$2.50"))

        let chartView = try #require(viewController.view.firstDescendant(ofType: MonthlyTokenChartView.self))
        #expect(chartView.debugBarCount == 30)

        let costChartView = try #require(viewController.view.firstDescendant(ofType: MonthlyCostChartView.self))
        #expect(costChartView.debugBarCount == 30)
    }

    @MainActor
    @Test("本日配置展示标题、说明和二十四个小时桶")
    func rendersTodayTitleSubtitleAndHourlyBuckets() throws {
        let calendar = utcCalendar()
        let viewController = MonthlyStatsViewController(
            period: .today,
            stateProvider: {
                [.claude: .init(
                    stats: makeStats(byHour: [
                        "2026-06-20T09": makeSummary(
                            total: 150_000,
                            cost: 0.5,
                            modelBreakdown: ["claude-haiku": 150_000]
                        ),
                        "2026-06-20T14": makeSummary(
                            total: 250_000,
                            cost: 1.0,
                            modelBreakdown: ["claude-sonnet": 250_000]
                        ),
                    ], byDay: [
                        "2026-06-20": makeSummary(
                            total: 999_000,
                            cost: 9.99,
                            modelBreakdown: ["ignored-day-total": 999_000]
                        ),
                    ], byMonth: [:]),
                    isLoading: false,
                    errorMessage: nil,
                    needsAuthorization: false
                )]
            },
            nowProvider: { date(2026, 6, 20, calendar: calendar) },
            calendar: calendar
        )

        viewController.loadViewIfNeeded()

        let labels = viewController.view.allDescendants(ofType: NSTextField.self).map(\.stringValue)
        #expect(labels.contains("本日"))
        #expect(labels.contains("本日,跨 provider 汇总"))
        #expect(labels.contains("0.4M"))
        #expect(labels.contains("$1.50"))

        let chartView = try #require(viewController.view.firstDescendant(ofType: MonthlyTokenChartView.self))
        #expect(chartView.debugBarCount == 24)

        let costChartView = try #require(viewController.view.firstDescendant(ofType: MonthlyCostChartView.self))
        #expect(costChartView.debugBarCount == 24)
    }

    @MainActor
    @Test("两个柱状图使用一致配色")
    func barChartsUseMatchingColors() throws {
        let viewController = MonthlyStatsViewController()

        viewController.loadViewIfNeeded()

        let chartView = try #require(viewController.view.firstDescendant(ofType: MonthlyTokenChartView.self))
        let costChartView = try #require(viewController.view.firstDescendant(ofType: MonthlyCostChartView.self))
        #expect(chartView.debugRegularBarColor == costChartView.debugRegularBarColor)
        #expect(chartView.debugCurrentMonthBarColor == costChartView.debugCurrentMonthBarColor)
    }

    @MainActor
    @Test("两个饼图在最近十二个月页竖向排列")
    func pieChartsAreStackedVertically() throws {
        let calendar = utcCalendar()
        let viewController = MonthlyStatsViewController(
            stateProvider: {
                [
                    .claude: .init(
                        stats: makeStats(byMonth: [
                            "2026-06": makeSummary(total: 1_200_000, modelBreakdown: ["claude-sonnet": 1_200_000])
                        ]),
                        isLoading: false,
                        errorMessage: nil,
                        needsAuthorization: false
                    ),
                    .codex: .init(
                        stats: makeStats(byMonth: [
                            "2026-06": makeSummary(total: 800_000, modelBreakdown: ["gpt-5.5": 800_000])
                        ]),
                        isLoading: false,
                        errorMessage: nil,
                        needsAuthorization: false
                    ),
                ]
            },
            nowProvider: { date(2026, 6, 20, calendar: calendar) },
            calendar: calendar
        )

        viewController.loadViewIfNeeded()

        let pieViews = viewController.view.allDescendants(ofType: UsageSharePieChartView.self)
        let pieContainer = try #require(pieViews.first?.superview as? NSStackView)
        #expect(pieContainer.orientation == .vertical)
        #expect(pieContainer.arrangedSubviews.compactMap { $0 as? UsageSharePieChartView }.map(\.debugTitle) == ["工具占比", "模型占比"])
    }

    @MainActor
    @Test("无授权且无 stats 时提示先授权")
    func promptsAuthorizationWhenNoStatsAreLoaded() {
        let calendar = utcCalendar()
        let viewController = MonthlyStatsViewController(
            stateProvider: {
                [.claude: .init(stats: nil, isLoading: false, errorMessage: nil, needsAuthorization: true)]
            },
            nowProvider: { date(2026, 6, 20, calendar: calendar) },
            calendar: calendar
        )

        viewController.loadViewIfNeeded()

        let labels = viewController.view.allDescendants(ofType: NSTextField.self).map(\.stringValue)
        #expect(labels.contains("请先在设置中授权访问用户目录"))
    }

    @MainActor
    @Test("混合加载与授权状态时优先提示授权")
    func mixedLoadingAndAuthorizationShowsAuthorization() {
        let calendar = utcCalendar()
        let viewController = MonthlyStatsViewController(
            stateProvider: {
                [
                    .claude: .init(stats: nil, isLoading: true, errorMessage: nil, needsAuthorization: false),
                    .codex: .init(stats: nil, isLoading: false, errorMessage: nil, needsAuthorization: true),
                ]
            },
            nowProvider: { date(2026, 6, 20, calendar: calendar) },
            calendar: calendar
        )

        viewController.loadViewIfNeeded()

        let labels = viewController.view.allDescendants(ofType: NSTextField.self).map(\.stringValue)
        #expect(labels.contains("请先在设置中授权访问用户目录"))
    }

    @MainActor
    @Test("无已加载 stats 且有错误时展示错误")
    func showsErrorWhenNoStatsAreLoaded() {
        let calendar = utcCalendar()
        let viewController = MonthlyStatsViewController(
            stateProvider: {
                [.claude: .init(stats: nil, isLoading: false, errorMessage: "Claude 失败", needsAuthorization: false)]
            },
            nowProvider: { date(2026, 6, 20, calendar: calendar) },
            calendar: calendar
        )

        viewController.loadViewIfNeeded()

        let labels = viewController.view.allDescendants(ofType: NSTextField.self).map(\.stringValue)
        #expect(labels.contains("Claude 失败"))
    }

    @MainActor
    @Test("已加载且无错误但零 token 时展示暂无数据")
    func showsNoDataWhenLoadedStatsHaveZeroMonthlyTokens() {
        let calendar = utcCalendar()
        let viewController = MonthlyStatsViewController(
            stateProvider: {
                [.claude: .init(
                    stats: makeStats(byMonth: ["2026-06": makeSummary(total: 0)]),
                    isLoading: false,
                    errorMessage: nil,
                    needsAuthorization: false
                )]
            },
            nowProvider: { date(2026, 6, 20, calendar: calendar) },
            calendar: calendar
        )

        viewController.loadViewIfNeeded()

        let labels = viewController.view.allDescendants(ofType: NSTextField.self).map(\.stringValue)
        #expect(labels.contains("最近 12 个月暂无 token 数据"))
    }

    @MainActor
    @Test("零 token 数据伴随 provider 错误时展示错误")
    func zeroDataWithProviderErrorShowsError() {
        let calendar = utcCalendar()
        let viewController = MonthlyStatsViewController(
            stateProvider: {
                [
                    .claude: .init(
                        stats: makeStats(byMonth: ["2026-06": makeSummary(total: 0)]),
                        isLoading: false,
                        errorMessage: nil,
                        needsAuthorization: false
                    ),
                    .codex: .init(stats: nil, isLoading: false, errorMessage: "Codex 失败", needsAuthorization: false),
                ]
            },
            nowProvider: { date(2026, 6, 20, calendar: calendar) },
            calendar: calendar
        )

        viewController.loadViewIfNeeded()

        let labels = viewController.view.allDescendants(ofType: NSTextField.self).map(\.stringValue)
        #expect(labels.contains("Codex 失败"))
    }

    @MainActor
    @Test("部分加载中时保留已加载图表并提示")
    func keepsChartWhenSomeProvidersAreLoading() throws {
        let calendar = utcCalendar()
        let viewController = MonthlyStatsViewController(
            stateProvider: {
                [
                    .claude: .init(
                        stats: makeStats(byMonth: ["2026-06": makeSummary(total: 500)]),
                        isLoading: false,
                        errorMessage: nil,
                        needsAuthorization: false
                    ),
                    .codex: .init(stats: nil, isLoading: true, errorMessage: nil, needsAuthorization: false),
                ]
            },
            nowProvider: { date(2026, 6, 20, calendar: calendar) },
            calendar: calendar
        )

        viewController.loadViewIfNeeded()

        let chartView = try #require(viewController.view.firstDescendant(ofType: MonthlyTokenChartView.self))
        #expect(chartView.debugBarCount == 12)

        let labels = viewController.view.allDescendants(ofType: NSTextField.self).map(\.stringValue)
        #expect(labels.contains("部分数据仍在加载"))
    }

    @MainActor
    @Test("token 有数据但费用为零时仍展示费用图")
    func rendersCostChartWhenCostIsZero() throws {
        let calendar = utcCalendar()
        let viewController = MonthlyStatsViewController(
            stateProvider: {
                [.claude: .init(
                    stats: makeStats(byMonth: ["2026-06": makeSummary(total: 500, cost: 0)]),
                    isLoading: false,
                    errorMessage: nil,
                    needsAuthorization: false
                )]
            },
            nowProvider: { date(2026, 6, 20, calendar: calendar) },
            calendar: calendar
        )

        viewController.loadViewIfNeeded()

        let costChartView = try #require(viewController.view.firstDescendant(ofType: MonthlyCostChartView.self))
        #expect(costChartView.debugBarCount == 12)
        #expect(costChartView.debugNormalizedHeights.allSatisfy { $0 == 0 })
    }

    @MainActor
    @Test("主界面很宽时柱状图仍保持紧凑宽度")
    func barChartsKeepCompactWidthInWideContainer() throws {
        let calendar = utcCalendar()
        let viewController = MonthlyStatsViewController(
            stateProvider: {
                [.claude: .init(
                    stats: makeStats(byMonth: ["2026-06": makeSummary(total: 500, cost: 1.5)]),
                    isLoading: false,
                    errorMessage: nil,
                    needsAuthorization: false
                )]
            },
            nowProvider: { date(2026, 6, 20, calendar: calendar) },
            calendar: calendar
        )

        viewController.loadViewIfNeeded()
        viewController.view.frame = NSRect(x: 0, y: 0, width: 1_200, height: 800)
        viewController.view.layoutSubtreeIfNeeded()

        let chartView = try #require(viewController.view.firstDescendant(ofType: MonthlyTokenChartView.self))
        let costChartView = try #require(viewController.view.firstDescendant(ofType: MonthlyCostChartView.self))
        #expect(chartView.frame.width == 520)
        #expect(costChartView.frame.width == 520)
    }

    @MainActor
    @Test("四个图表 hover 用量展示在标题右侧")
    func hoverUsageAppearsBesideChartTitles() throws {
        let calendar = utcCalendar()
        let viewController = MonthlyStatsViewController(
            stateProvider: {
                [.claude: .init(
                    stats: makeStats(byMonth: [
                        "2026-06": makeSummary(
                            total: 500,
                            cost: 12.5,
                            modelBreakdown: ["claude-sonnet": 500]
                        )
                    ]),
                    isLoading: false,
                    errorMessage: nil,
                    needsAuthorization: false
                )]
            },
            nowProvider: { date(2026, 6, 20, calendar: calendar) },
            calendar: calendar
        )

        viewController.loadViewIfNeeded()
        viewController.view.frame = NSRect(x: 0, y: 0, width: 1_200, height: 800)
        viewController.view.layoutSubtreeIfNeeded()

        viewController.debugSimulateTokenChartHover(monthKey: "2026-06")
        viewController.debugSimulateCostChartHover(monthKey: "2026-06")
        let pieViews = viewController.view.allDescendants(ofType: UsageSharePieChartView.self)
        let toolPieView = try #require(pieViews.first)
        let modelPieView = try #require(pieViews.last)
        toolPieView.debugSimulateHover(sliceID: "claude")
        modelPieView.debugSimulateHover(sliceID: "claude-sonnet")
        viewController.view.layoutSubtreeIfNeeded()

        #expect(viewController.debugTokenChartHoverText == "6月 · 0.0M · claude-sonnet 0.0M")
        #expect(viewController.debugCostChartHoverText == "6月 · $12.50")
        #expect(toolPieView.debugHoverText == "Claude Code · 0.0M")
        #expect(modelPieView.debugHoverText == "claude-sonnet · 0.0M")
        #expect(viewController.debugTokenHoverLabelTrailingAlignsWithTokenChart)
        #expect(viewController.debugCostHoverLabelTrailingAlignsWithCostChart)
        #expect(toolPieView.debugHoverLabelTrailingAlignsWithChart)
        #expect(modelPieView.debugHoverLabelTrailingAlignsWithChart)

        viewController.debugSimulateTokenChartHover(monthKey: nil)
        viewController.debugSimulateCostChartHover(monthKey: nil)
        toolPieView.debugSimulateHover(sliceID: nil)
        modelPieView.debugSimulateHover(sliceID: nil)

        #expect(viewController.debugTokenChartHoverText == "")
        #expect(viewController.debugCostChartHoverText == "")
        #expect(toolPieView.debugHoverText == "")
        #expect(modelPieView.debugHoverText == "")
    }

    @MainActor
    @Test("主界面很宽时饼图贴左且图例贴齐柱状图右侧")
    func pieChartsAlignPieLeftAndLegendRightWithBarChart() throws {
        let calendar = utcCalendar()
        let viewController = MonthlyStatsViewController(
            stateProvider: {
                [.claude: .init(
                    stats: makeStats(byMonth: [
                        "2026-06": makeSummary(
                            total: 1_200_000,
                            modelBreakdown: ["claude-sonnet": 1_200_000]
                        )
                    ]),
                    isLoading: false,
                    errorMessage: nil,
                    needsAuthorization: false
                )]
            },
            nowProvider: { date(2026, 6, 20, calendar: calendar) },
            calendar: calendar
        )

        viewController.loadViewIfNeeded()
        viewController.view.frame = NSRect(x: 0, y: 0, width: 1_200, height: 800)
        viewController.view.layoutSubtreeIfNeeded()

        let chartView = try #require(viewController.view.firstDescendant(ofType: MonthlyTokenChartView.self))
        let pieViews = viewController.view.allDescendants(ofType: UsageSharePieChartView.self)
        let toolPieView = try #require(pieViews.first)
        let pieContainer = try #require(pieViews.first?.superview as? NSStackView)
        let chartFrame = chartView.convert(chartView.bounds, to: viewController.view)
        let pieContainerFrame = pieContainer.convert(pieContainer.bounds, to: viewController.view)
        let drawingView = try #require(toolPieView.firstDescendant(ofType: UsageSharePieDrawingView.self))
        let drawingFrame = drawingView.convert(drawingView.bounds, to: viewController.view)
        let legendRight = try #require(toolPieView.legendRowRights(in: viewController.view).max())

        #expect(abs(pieContainerFrame.minX - chartFrame.minX) < 0.5)
        #expect(abs(pieContainerFrame.width - chartFrame.width) < 0.5)
        #expect(abs(drawingFrame.minX - chartFrame.minX) < 0.5)
        #expect(abs(legendRight - chartFrame.maxX) < 0.5)
    }

    private func utcCalendar() -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
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

private extension NSView {
    func firstDescendant<T: NSView>(ofType type: T.Type) -> T? {
        if let match = self as? T {
            return match
        }
        for subview in subviews {
            if let match = subview.firstDescendant(ofType: type) {
                return match
            }
        }
        return nil
    }

    func allDescendants<T: NSView>(ofType type: T.Type) -> [T] {
        let current = (self as? T).map { [$0] } ?? []
        return current + subviews.flatMap { $0.allDescendants(ofType: type) }
    }

    func legendRowRights(in targetView: NSView) -> [CGFloat] {
        allDescendants(ofType: NSStackView.self)
            .filter { $0.toolTip != nil }
            .map { row in row.convert(row.bounds, to: targetView).maxX }
    }
}
