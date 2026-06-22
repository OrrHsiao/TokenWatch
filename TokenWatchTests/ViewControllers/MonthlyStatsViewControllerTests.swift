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
        #expect(labels.contains("按月"))
        #expect(labels.contains("过去 12 个月,跨 provider 汇总"))
        #expect(labels.contains("1.2M tokens"))
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
    @Test("两个饼图在按月页竖向排列")
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
        #expect(labels.contains("过去 12 个月暂无 token 数据"))
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
}
