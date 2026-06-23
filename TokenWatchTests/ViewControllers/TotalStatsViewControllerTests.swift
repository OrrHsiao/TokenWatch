import AppKit
import Foundation
import Testing
@testable import TokenWatch

@Suite("TotalStatsViewController")
struct TotalStatsViewControllerTests {

    @MainActor
    @Test("加载后展示标题、总量、费用和模型排序")
    func rendersTitleSummaryAndSortedModelRows() throws {
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
        #expect(labels.contains("总计"))
        #expect(labels.contains("跨 provider 全量汇总"))
        #expect(labels.contains("模型消耗"))
        #expect(labels.contains("2.0M"))
        #expect(labels.contains("$16.75"))
        #expect(viewController.debugModelRowLabels == ["claude-sonnet", "claude-haiku", "gpt-5"])
        #expect(viewController.debugModelRowTokenTexts == ["0.9M", "0.6M", "0.5M"])
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
}
