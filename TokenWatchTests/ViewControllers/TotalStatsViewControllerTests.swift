import AppKit
import Foundation
import Testing
@testable import TokenWatch

@Suite("TotalStatsViewController")
struct TotalStatsViewControllerTests {

    @MainActor
    @Test("加载后展示总量、费用和模型排序")
    func rendersSummaryAndSortedModelRows() throws {
        let viewController = TotalStatsViewController(
            stateProvider: {
                [
                    .claude: .init(
                        stats: makeStats(
                            total: 1_200_000,
                            cost: 12.50,
                            byModel: [
                                "claude-sonnet": 900_000,
                                "claude-haiku": 300_000,
                            ]
                        ),
                        isLoading: false,
                        errorMessage: nil,
                        needsAuthorization: false
                    ),
                    .codex: .init(
                        stats: makeStats(
                            total: 800_000,
                            cost: 4.25,
                            byModel: [
                                "gpt-5": 500_000,
                                "claude-haiku": 300_000,
                            ]
                        ),
                        isLoading: false,
                        errorMessage: nil,
                        needsAuthorization: false
                    ),
                ]
            }
        )

        viewController.loadViewIfNeeded()

        let labels = viewController.view.allDescendants(ofType: NSTextField.self).map(\.stringValue)
        #expect(labels.contains("总 token"))
        #expect(labels.contains("总费用"))
        #expect(labels.contains("模型消耗"))
        #expect(labels.contains("2.0M"))
        #expect(labels.contains("$16.75"))
        #expect(viewController.debugModelRowLabels == ["claude-sonnet", "claude-haiku", "gpt-5"])
        #expect(viewController.debugModelRowValueTexts == ["0.9M · $0.00", "0.6M · $0.00", "0.5M · $0.00"])
    }

    @MainActor
    @Test("模型消耗行在 token 后展示费用并避免小用量显示为 0.0M")
    func modelRowsShowCostAndCompactSmallTokenCounts() throws {
        let viewController = TotalStatsViewController(
            stateProvider: {
                [
                    .claude: .init(
                        stats: makeStats(
                            total: 125_000,
                            cost: 1.83,
                            byModel: [
                                "small-model": (tokens: 50_000, cost: 0.42),
                                "tiny-model": (tokens: 900, cost: 0.01),
                            ]
                        ),
                        isLoading: false,
                        errorMessage: nil,
                        needsAuthorization: false
                    ),
                ]
            }
        )

        viewController.loadViewIfNeeded()

        #expect(viewController.debugModelRowLabels == ["small-model", "tiny-model"])
        #expect(viewController.debugModelRowValueTexts == ["50.0k · $0.42", "900 · $0.01"])
        #expect(!viewController.debugModelRowValueTexts.contains("0.0M"))
    }

    @MainActor
    @Test("总 token、总费用和模型列表与其他详情页保持左侧边距")
    func keepsSummaryAndModelRowsInsetFromDetailLeadingEdge() throws {
        let viewController = TotalStatsViewController(
            stateProvider: {
                [
                    .claude: .init(
                        stats: makeStats(
                            total: 1_200_000,
                            cost: 12.50,
                            byModel: ["claude-sonnet": 900_000]
                        ),
                        isLoading: false,
                        errorMessage: nil,
                        needsAuthorization: false
                    ),
                    .codex: .init(
                        stats: makeStats(
                            total: 800_000,
                            cost: 4.25,
                            byModel: ["gpt-5": 500_000]
                        ),
                        isLoading: false,
                        errorMessage: nil,
                        needsAuthorization: false
                    ),
                ]
            }
        )

        viewController.loadViewIfNeeded()
        viewController.view.setFrameSize(NSSize(width: 800, height: 600))
        viewController.view.layoutSubtreeIfNeeded()

        let labels = viewController.view.allDescendants(ofType: NSTextField.self)
        let totalTitleLabel = try #require(labels.first { $0.stringValue == "总 token" })
        let totalLabel = try #require(labels.first { $0.stringValue == "2.0M" })
        let costTitleLabel = try #require(labels.first { $0.stringValue == "总费用" })
        let costLabel = try #require(labels.first { $0.stringValue == "$16.75" })
        let modelSectionTitleLabel = try #require(labels.first { $0.stringValue == "模型消耗" })
        let modelNameLabel = try #require(labels.first { $0.stringValue == "claude-sonnet" })
        let detailTopY = viewController.view.bounds.maxY

        #expect(abs(totalTitleLabel.frame(in: viewController.view).minX - 32) <= 2)
        #expect(abs(totalTitleLabel.frame(in: viewController.view).maxY - detailTopY) <= 1)
        #expect(abs(totalLabel.frame(in: viewController.view).minX - 32) <= 2)
        #expect(abs(costTitleLabel.frame(in: viewController.view).minX - 32) <= 2)
        #expect(abs(costLabel.frame(in: viewController.view).minX - 32) <= 2)
        #expect(abs(modelSectionTitleLabel.frame(in: viewController.view).minX - 32) <= 2)
        #expect(abs(modelNameLabel.frame(in: viewController.view).minX - 32) <= 2)
    }

    @MainActor
    @Test("部分数据加载中时总 token 和总费用保持紧凑间距")
    func keepsSummaryMetricsCompactWhilePartiallyLoading() throws {
        let viewController = TotalStatsViewController(
            stateProvider: {
                [
                    .claude: .init(
                        stats: makeStats(
                            total: 1_200_000,
                            cost: 12.50,
                            byModel: ["claude-sonnet": 900_000]
                        ),
                        isLoading: false,
                        errorMessage: nil,
                        needsAuthorization: false
                    ),
                    .codex: .init(
                        stats: nil,
                        isLoading: true,
                        errorMessage: nil,
                        needsAuthorization: false
                    ),
                ]
            }
        )

        viewController.loadViewIfNeeded()
        viewController.view.setFrameSize(NSSize(width: 800, height: 600))
        viewController.view.layoutSubtreeIfNeeded()

        let labels = viewController.view.allDescendants(ofType: NSTextField.self)
        let totalTitleLabel = try #require(labels.first { $0.stringValue == "总 token" })
        let costTitleLabel = try #require(labels.first { $0.stringValue == "总费用" })
        let totalTitleFrame = totalTitleLabel.frame(in: viewController.view)
        let costTitleFrame = costTitleLabel.frame(in: viewController.view)
        let titleDistance = totalTitleFrame.maxY - costTitleFrame.maxY

        #expect(viewController.debugStatusText == "部分数据仍在加载")
        #expect(titleDistance <= 80)
    }

    @MainActor
    @Test("无授权且无 stats 时提示先授权")
    func promptsAuthorizationWhenNoStatsAreLoaded() {
        let viewController = TotalStatsViewController(
            stateProvider: {
                [.claude: .init(stats: nil, isLoading: false, errorMessage: nil, needsAuthorization: true)]
            }
        )

        viewController.loadViewIfNeeded()

        #expect(viewController.debugStatusText == "请先在设置中授权访问用户目录")
    }

    @MainActor
    @Test("全部加载中时展示加载提示")
    func showsLoadingWhenAllProvidersAreLoading() {
        let viewController = TotalStatsViewController(
            stateProvider: {
                [
                    .claude: .init(stats: nil, isLoading: true, errorMessage: nil, needsAuthorization: false),
                    .codex: .init(stats: nil, isLoading: true, errorMessage: nil, needsAuthorization: false),
                ]
            }
        )

        viewController.loadViewIfNeeded()

        #expect(viewController.debugStatusText == "正在加载用量数据...")
    }

    @MainActor
    @Test("已加载但零 token 时展示暂无数据")
    func showsNoDataWhenLoadedStatsHaveZeroTokens() {
        let viewController = TotalStatsViewController(
            stateProvider: {
                [.claude: .init(stats: makeStats(total: 0), isLoading: false, errorMessage: nil, needsAuthorization: false)]
            }
        )

        viewController.loadViewIfNeeded()

        #expect(viewController.debugStatusText == "总计暂无 token 数据")
    }

    @MainActor
    @Test("已有数据且有错误时保留数据并展示错误")
    func keepsDataAndShowsProviderError() {
        let viewController = TotalStatsViewController(
            stateProvider: {
                [
                    .claude: .init(stats: makeStats(total: 1_000_000), isLoading: false, errorMessage: nil, needsAuthorization: false),
                    .codex: .init(stats: nil, isLoading: false, errorMessage: "Codex 失败", needsAuthorization: false),
                ]
            }
        )

        viewController.loadViewIfNeeded()

        #expect(viewController.debugTotalText == "1.0M")
        #expect(viewController.debugStatusText == "Codex 失败")
    }

    private func makeStats(
        total: Int,
        cost: Double = 0,
        byModel: [String: Int] = [:]
    ) -> AggregatedStats {
        makeStats(
            total: total,
            cost: cost,
            byModel: byModel.mapValues { (tokens: $0, cost: 0) }
        )
    }

    private func makeStats(
        total: Int,
        cost: Double = 0,
        byModel: [String: (tokens: Int, cost: Double)]
    ) -> AggregatedStats {
        let modelSummaries = byModel.mapValues { modelSummary in
            UsageSummary(
                inputTokens: modelSummary.tokens,
                outputTokens: 0,
                cacheReadTokens: 0,
                cacheCreationTokens: 0,
                reasoningTokens: 0,
                totalTokens: modelSummary.tokens,
                cost: modelSummary.cost,
                entryCount: modelSummary.tokens > 0 ? 1 : 0,
                modelBreakdown: [:]
            )
        }
        return AggregatedStats(
            overall: UsageSummary(
                inputTokens: total,
                outputTokens: 0,
                cacheReadTokens: 0,
                cacheCreationTokens: 0,
                reasoningTokens: 0,
                totalTokens: total,
                cost: cost,
                entryCount: total > 0 ? 1 : 0,
                modelBreakdown: modelSummaries
            ),
            byHour: [:],
            byDay: [:],
            byWeek: [:],
            byMonth: [:],
            bySession: [:],
            byModel: modelSummaries,
            byProject: [:],
            dataSourceCount: 1
        )
    }
}

private extension NSView {
    func allDescendants<T: NSView>(ofType type: T.Type) -> [T] {
        let current = (self as? T).map { [$0] } ?? []
        return current + subviews.flatMap { $0.allDescendants(ofType: type) }
    }

    func frame(in rootView: NSView) -> NSRect {
        convert(bounds, to: rootView)
    }
}
