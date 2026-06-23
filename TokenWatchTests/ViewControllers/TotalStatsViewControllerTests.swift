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
        #expect(viewController.debugModelRowTokenTexts == ["0.9M", "0.6M", "0.5M"])
    }

    @MainActor
    @Test("总 token、总费用和模型列表从详情视图左上角开始布局")
    func alignsSummaryAndModelRowsToDetailTopLeadingCorner() throws {
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

        #expect(totalTitleLabel.frame(in: viewController.view).minX <= 1)
        #expect(abs(totalTitleLabel.frame(in: viewController.view).maxY - detailTopY) <= 1)
        #expect(totalLabel.frame(in: viewController.view).minX <= 1)
        #expect(costTitleLabel.frame(in: viewController.view).minX <= 1)
        #expect(costLabel.frame(in: viewController.view).minX <= 1)
        #expect(modelSectionTitleLabel.frame(in: viewController.view).minX <= 1)
        #expect(modelNameLabel.frame(in: viewController.view).minX <= 1)
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
        let modelSummaries = byModel.mapValues { tokens in
            UsageSummary(
                inputTokens: tokens,
                outputTokens: 0,
                cacheReadTokens: 0,
                cacheCreationTokens: 0,
                reasoningTokens: 0,
                totalTokens: tokens,
                cost: 0,
                entryCount: tokens > 0 ? 1 : 0,
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
