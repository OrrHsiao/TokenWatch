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
        #expect(labels.contains("总计"))
        #expect(labels.contains("跨 provider 全量汇总"))
        #expect(!labels.contains("总 token"))
        #expect(!labels.contains("总费用"))
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
    @Test("总 token 和总费用位于标题右侧并左对齐")
    func summaryMetricsAlignLeadingAtTitleTrailingSide() throws {
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
        let totalLabel = try #require(labels.first { $0.stringValue == "2.0M" })
        let costLabel = try #require(labels.first { $0.stringValue == "$16.75" })
        let titleLabel = try #require(labels.first { $0.stringValue == "总计" })
        let subtitleLabel = try #require(labels.first { $0.stringValue == "跨 provider 全量汇总" })
        let modelSectionTitleLabel = try #require(labels.first { $0.stringValue == "模型消耗" })
        let modelNameLabel = try #require(labels.first { $0.stringValue == "claude-sonnet" })
        let expectedTopY = viewController.view.bounds.maxY - 32
        let totalFrame = totalLabel.frame(in: viewController.view)
        let costFrame = costLabel.frame(in: viewController.view)
        let totalAlignmentFrame = totalLabel.alignmentFrame(in: viewController.view)
        let costAlignmentFrame = costLabel.alignmentFrame(in: viewController.view)
        let headerTextTrailingX = max(
            titleLabel.alignmentFrame(in: viewController.view).maxX,
            subtitleLabel.alignmentFrame(in: viewController.view).maxX
        )

        #expect(titleLabel.font == .systemFont(ofSize: 22, weight: .semibold))
        #expect(subtitleLabel.textColor == .secondaryLabelColor)
        #expect(totalLabel.alignment == .natural)
        #expect(costLabel.alignment == .natural)
        #expect(costLabel.textColor == .secondaryLabelColor)
        #expect(abs(titleLabel.frame(in: viewController.view).minX - 32) <= 2)
        #expect(abs(titleLabel.frame(in: viewController.view).maxY - expectedTopY) <= 1)
        #expect(abs(totalAlignmentFrame.minX - (headerTextTrailingX + 16)) <= 1)
        #expect(abs(totalAlignmentFrame.minX - costAlignmentFrame.minX) <= 1)
        #expect(abs(totalFrame.midY - titleLabel.frame(in: viewController.view).midY) <= 6)
        #expect(abs(costFrame.midY - subtitleLabel.frame(in: viewController.view).midY) <= 6)
        #expect(abs(modelSectionTitleLabel.frame(in: viewController.view).minX - 32) <= 2)
        #expect(abs(modelNameLabel.frame(in: viewController.view).minX - 32) <= 2)
    }

    @MainActor
    @Test("右上角展示与状态栏弹窗一致的刷新按钮")
    func headerShowsPopoverStyleRefreshButton() throws {
        let viewController = TotalStatsViewController(
            stateProvider: {
                [.claude: .init(stats: makeStats(total: 1_200_000), isLoading: false, errorMessage: nil, needsAuthorization: false)]
            }
        )

        viewController.loadViewIfNeeded()
        viewController.view.setFrameSize(NSSize(width: 800, height: 600))
        viewController.view.layoutSubtreeIfNeeded()

        let refreshFrame = viewController.debugRefreshButtonFrameInView
        let refreshButton = try #require(viewController.view.allDescendants(ofType: NSButton.self).first {
            $0.toolTip == "立即刷新"
        })
        let headerView = try #require(refreshButton.superview)
        let headerFrame = headerView.convert(headerView.bounds, to: viewController.view)

        #expect(viewController.debugRefreshButtonTitle == "")
        #expect(viewController.debugRefreshButtonSymbolName == "arrow.clockwise")
        #expect(viewController.debugRefreshButtonUsesImageOnly)
        #expect(viewController.debugRefreshButtonToolTip == "立即刷新")
        #expect(viewController.debugRefreshButtonActionName == "refreshStats:")
        #expect(viewController.debugRefreshButtonCornerRadius == 6)
        #expect(!viewController.debugRefreshButtonHasBackground)
        #expect(abs(refreshFrame.width - 20) <= 1)
        #expect(abs(refreshFrame.maxX - headerFrame.maxX) <= 2)
        #expect(abs(refreshFrame.maxY - headerFrame.maxY) <= 4)

        viewController.debugSetRefreshButtonHovering(true)
        #expect(viewController.debugRefreshButtonHasBackground)

        viewController.debugSetRefreshButtonHovering(false)
        #expect(!viewController.debugRefreshButtonHasBackground)
    }

    @MainActor
    @Test("刷新按钮 loading 时禁用并显示同步图标")
    func refreshButtonShowsLoadingState() {
        let viewController = TotalStatsViewController(
            stateProvider: {
                [.claude: .init(stats: nil, isLoading: true, errorMessage: nil, needsAuthorization: false)]
            }
        )

        viewController.loadViewIfNeeded()

        #expect(!viewController.debugRefreshButtonIsEnabled)
        #expect(viewController.debugRefreshButtonSymbolName == "arrow.triangle.2.circlepath")
        #expect(viewController.debugRefreshButtonToolTip == "正在刷新")
    }

    @MainActor
    @Test("点击刷新按钮调用总计页刷新动作")
    func refreshButtonRunsRefreshAction() async {
        var refreshCount = 0
        let viewController = TotalStatsViewController(
            stateProvider: { [:] },
            refreshAction: {
                refreshCount += 1
            }
        )

        viewController.loadViewIfNeeded()
        viewController.debugClickRefreshButton()
        await Task.yield()

        #expect(refreshCount == 1)
    }

    @MainActor
    @Test("部分数据加载中提示展示在刷新按钮下方且总计指标保持紧凑")
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
        let totalLabel = try #require(labels.first { $0.stringValue == "1.2M" })
        let costLabel = try #require(labels.first { $0.stringValue == "$12.50" })
        let statusLabel = try #require(labels.first { $0.stringValue == "部分数据仍在加载" })
        let modelSectionTitleLabel = try #require(labels.first { $0.stringValue == "模型消耗" })
        let totalFrame = totalLabel.frame(in: viewController.view)
        let costFrame = costLabel.frame(in: viewController.view)
        let statusFrame = statusLabel.frame(in: viewController.view)
        let refreshFrame = viewController.debugRefreshButtonFrameInView
        let modelSectionTitleFrame = modelSectionTitleLabel.frame(in: viewController.view)
        let valueDistance = totalFrame.minY - costFrame.minY

        #expect(viewController.debugStatusText == "部分数据仍在加载")
        #expect(abs(statusFrame.maxX - refreshFrame.maxX) <= 2)
        #expect(statusFrame.maxY <= refreshFrame.minY - 2)
        #expect(statusFrame.minY > modelSectionTitleFrame.maxY)
        #expect(valueDistance <= 28)
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

    func alignmentFrame(in rootView: NSView) -> NSRect {
        guard let superview else {
            return alignmentRect(forFrame: frame)
        }
        return superview.convert(alignmentRect(forFrame: frame), to: rootView)
    }
}
