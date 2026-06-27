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
            },
            languageSettings: zhHansLanguageSettings()
        )

        viewController.loadViewIfNeeded()

        let labels = viewController.view.allDescendants(ofType: NSTextField.self).map(\.stringValue)
        #expect(labels.contains("总计"))
        #expect(!labels.contains("跨 provider 全量汇总"))
        #expect(!labels.contains("总 token"))
        #expect(!labels.contains("总费用"))
        #expect(labels.contains("模型消耗"))
        #expect(labels.contains("2.0M"))
        #expect(labels.contains("$16.75"))
        #expect(viewController.debugModelRowLabels == ["claude-sonnet", "claude-haiku", "gpt-5"])
        #expect(viewController.debugModelRowValueTexts == ["900,000", "600,000", "500,000"])
        #expect(labels.contains("45%"))
        #expect(labels.contains("30%"))
        #expect(labels.contains("25%"))
    }

    @MainActor
    @Test("英文下展示总计页文案")
    func rendersEnglishCopy() throws {
        let settings = AppLanguageSettings(defaults: temporaryDefaults(), preferredLanguagesProvider: { ["zh-Hans-US"] })
        settings.selectedPreference = .en
        let viewController = TotalStatsViewController(
            stateProvider: {
                [.claude: .init(stats: makeStats(total: 0), isLoading: false, errorMessage: nil, needsAuthorization: false)]
            },
            languageSettings: settings
        )

        viewController.loadViewIfNeeded()

        let labels = viewController.view.allDescendants(ofType: NSTextField.self).map(\.stringValue)
        #expect(labels.contains("Total"))
        #expect(!labels.contains("All-time summary across providers"))
        #expect(labels.contains("Model Usage"))
        #expect(viewController.debugStatusText == "No total token data")
        #expect(viewController.debugRefreshButtonToolTip == "Refresh Now")
    }

    @MainActor
    @Test("模型消耗行使用条形排名并展示完整 token 数")
    func modelRowsRenderRankBarsWithFullTokenCounts() throws {
        let viewController = TotalStatsViewController(
            stateProvider: {
                [
                    .claude: .init(
                        stats: makeStats(
                            total: 175_000,
                            cost: 1.83,
                            byModel: [
                                "large-model": (tokens: 125_000, cost: 0.42),
                                "small-model": (tokens: 50_000, cost: 0.01),
                            ]
                        ),
                        isLoading: false,
                        errorMessage: nil,
                        needsAuthorization: false
                    ),
                ]
            },
            languageSettings: zhHansLanguageSettings()
        )

        viewController.loadViewIfNeeded()
        viewController.view.setFrameSize(NSSize(width: 800, height: 600))
        viewController.view.layoutSubtreeIfNeeded()

        let labels = viewController.view.allDescendants(ofType: NSTextField.self).map(\.stringValue)
        let firstBar = try viewController.view.descendantView(withIdentifier: "TotalModelRankBar.0")
        let secondBar = try viewController.view.descendantView(withIdentifier: "TotalModelRankBar.1")
        let firstRow = try viewController.view.descendantView(withIdentifier: "TotalModelRankRow.0")
        let secondRow = try viewController.view.descendantView(withIdentifier: "TotalModelRankRow.1")
        let firstTokenLabel = try viewController.view.descendantTextField(withIdentifier: "TotalModelRankValue.0")
        let firstPercentLabel = try viewController.view.descendantTextField(withIdentifier: "TotalModelRankPercent.0")
        let firstBarFrame = firstBar.frame(in: viewController.view)
        let secondBarFrame = secondBar.frame(in: viewController.view)
        let firstRowFrame = firstRow.frame(in: viewController.view)
        let secondRowFrame = secondRow.frame(in: viewController.view)
        let firstTokenFrame = firstTokenLabel.frame(in: viewController.view)
        let firstPercentFrame = firstPercentLabel.frame(in: viewController.view)
        let barVerticalGap = firstBarFrame.minY - secondBarFrame.maxY
        let rowVerticalGap = firstRowFrame.minY - secondRowFrame.maxY

        #expect(viewController.debugModelRowLabels == ["large-model", "small-model"])
        #expect(viewController.debugModelRowValueTexts == ["125,000", "50,000"])
        #expect(labels.contains("125,000"))
        #expect(labels.contains("50,000"))
        #expect(labels.contains("71.4%"))
        #expect(labels.contains("28.6%"))
        #expect(!labels.contains("0.1M · $0.42"))
        #expect(!labels.contains("50.0k · $0.01"))
        #expect(firstBar.wantsLayer)
        #expect(firstBar.layer?.backgroundColor != nil)
        let firstBarAlpha = try #require(firstBar.layer?.backgroundColor?.alpha)
        #expect(firstBarAlpha < 1)
        #expect(firstBarAlpha > 0.4)
        #expect(firstBarFrame.width > secondBarFrame.width)
        #expect(abs((secondBarFrame.width / firstBarFrame.width) - 0.4) < 0.08)
        #expect(abs(firstBarFrame.height - firstRowFrame.height) <= 1)
        #expect(abs(secondBarFrame.height - secondRowFrame.height) <= 1)
        #expect(abs(barVerticalGap - rowVerticalGap) <= 1)
        #expect(barVerticalGap <= 4.5)
        #expect(abs(firstPercentFrame.maxX - firstTokenFrame.maxX) <= 1)
        #expect(firstPercentFrame.maxY <= firstTokenFrame.minY + 2)
        #expect(firstRow.toolTip == "large-model · 125,000 · $0.42")
    }

    @MainActor
    @Test("非零极小模型占比显示为小于 0.1% 且使用短条")
    func nonZeroTinyModelShareShowsLessThanPointOnePercent() throws {
        let viewController = TotalStatsViewController(
            stateProvider: {
                [
                    .claude: .init(
                        stats: makeStats(
                            total: 1_000_001,
                            byModel: [
                                "large-model": 1_000_000,
                                "tiny-model": 1,
                            ]
                        ),
                        isLoading: false,
                        errorMessage: nil,
                        needsAuthorization: false
                    ),
                ]
            },
            languageSettings: zhHansLanguageSettings()
        )

        viewController.loadViewIfNeeded()
        viewController.view.setFrameSize(NSSize(width: 800, height: 600))
        viewController.view.layoutSubtreeIfNeeded()

        let largeBar = try viewController.view.descendantView(withIdentifier: "TotalModelRankBar.0")
        let tinyBar = try viewController.view.descendantView(withIdentifier: "TotalModelRankBar.1")
        let tinyPercentLabel = try viewController.view.descendantTextField(withIdentifier: "TotalModelRankPercent.1")
        let largeBarFrame = largeBar.frame(in: viewController.view)
        let tinyBarFrame = tinyBar.frame(in: viewController.view)

        #expect(viewController.debugModelRowLabels == ["large-model", "tiny-model"])
        #expect(tinyPercentLabel.stringValue == "<0.1%")
        #expect(abs((tinyBarFrame.width / largeBarFrame.width) - 0.02) < 0.005)
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
            },
            languageSettings: zhHansLanguageSettings()
        )

        viewController.loadViewIfNeeded()
        viewController.view.setFrameSize(NSSize(width: 800, height: 600))
        viewController.view.layoutSubtreeIfNeeded()

        let labels = viewController.view.allDescendants(ofType: NSTextField.self)
        let totalLabel = try #require(labels.first { $0.stringValue == "2.0M" })
        let costLabel = try #require(labels.first { $0.stringValue == "$16.75" })
        let titleLabel = try #require(labels.first { $0.stringValue == "总计" })
        let modelSectionTitleLabel = try #require(labels.first { $0.stringValue == "模型消耗" })
        let modelNameLabel = try #require(labels.first { $0.stringValue == "claude-sonnet" })
        let firstModelBar = try viewController.view.descendantView(withIdentifier: "TotalModelRankBar.0")
        let expectedTopY = viewController.view.bounds.maxY - 32
        let totalFrame = totalLabel.frame(in: viewController.view)
        let costFrame = costLabel.frame(in: viewController.view)
        let firstModelBarFrame = firstModelBar.frame(in: viewController.view)
        let modelNameFrame = modelNameLabel.frame(in: viewController.view)
        let totalAlignmentFrame = totalLabel.alignmentFrame(in: viewController.view)
        let costAlignmentFrame = costLabel.alignmentFrame(in: viewController.view)
        let headerTextTrailingX = titleLabel.alignmentFrame(in: viewController.view).maxX

        #expect(titleLabel.font == .systemFont(ofSize: 22, weight: .semibold))
        #expect(!labels.contains { $0.stringValue == "跨 provider 全量汇总" })
        #expect(totalLabel.alignment == .natural)
        #expect(costLabel.alignment == .natural)
        #expect(costLabel.textColor == .secondaryLabelColor)
        #expect(abs(titleLabel.frame(in: viewController.view).minX - 32) <= 2)
        #expect(abs(titleLabel.frame(in: viewController.view).maxY - expectedTopY) <= 1)
        #expect(abs(totalAlignmentFrame.minX - (headerTextTrailingX + 16)) <= 1)
        #expect(abs(totalAlignmentFrame.minX - costAlignmentFrame.minX) <= 1)
        #expect(abs(totalFrame.midY - titleLabel.frame(in: viewController.view).midY) <= 6)
        #expect(costFrame.minY < totalFrame.minY)
        #expect(abs(modelSectionTitleLabel.frame(in: viewController.view).minX - 32) <= 2)
        #expect(abs(firstModelBarFrame.minX - 32) <= 2)
        #expect(abs(modelNameFrame.minX - (firstModelBarFrame.minX + 12)) <= 2)
    }

    @MainActor
    @Test("右上角展示与状态栏弹窗一致的刷新按钮")
    func headerShowsPopoverStyleRefreshButton() throws {
        let viewController = TotalStatsViewController(
            stateProvider: {
                [.claude: .init(stats: makeStats(total: 1_200_000), isLoading: false, errorMessage: nil, needsAuthorization: false)]
            },
            languageSettings: zhHansLanguageSettings()
        )

        viewController.loadViewIfNeeded()
        viewController.view.setFrameSize(NSSize(width: 800, height: 600))
        viewController.view.layoutSubtreeIfNeeded()

        #expect(viewController.debugRefreshButtonTitle == "")
        #expect(viewController.debugRefreshButtonSymbolName == "arrow.clockwise")
        #expect(viewController.debugRefreshButtonUsesImageOnly)
        #expect(viewController.debugRefreshButtonToolTip == "立即刷新")
        #expect(viewController.debugRefreshButtonActionName == "refreshStats:")
        #expect(viewController.debugRefreshButtonCornerRadius == 6)
        #expect(!viewController.debugRefreshButtonHasBackground)

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
            },
            languageSettings: zhHansLanguageSettings()
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
            },
            languageSettings: zhHansLanguageSettings()
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
            },
            languageSettings: zhHansLanguageSettings()
        )

        viewController.loadViewIfNeeded()

        #expect(viewController.debugStatusText == "请先在设置中授权访问用户目录")
    }

    @MainActor
    @Test("无 stats 且有错误时优先展示真实错误")
    func showsErrorBeforeAuthorizationPromptWhenNoStatsAreLoaded() {
        let viewController = TotalStatsViewController(
            stateProvider: {
                [
                    .opencode: .init(
                        stats: nil,
                        isLoading: false,
                        errorMessage: "opencode.db 读取失败",
                        needsAuthorization: true
                    ),
                ]
            },
            languageSettings: zhHansLanguageSettings()
        )

        viewController.loadViewIfNeeded()

        #expect(viewController.debugStatusText == "opencode.db 读取失败")
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
            },
            languageSettings: zhHansLanguageSettings()
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
            },
            languageSettings: zhHansLanguageSettings()
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

    private func temporaryDefaults() -> UserDefaults {
        let suiteName = "TotalStatsViewControllerTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        return defaults
    }

    @MainActor
    private func zhHansLanguageSettings() -> AppLanguageSettings {
        AppLanguageSettings(defaults: temporaryDefaults(), preferredLanguagesProvider: { ["zh-Hans-US"] })
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

    func descendantView(withIdentifier identifier: String) throws -> NSView {
        try #require(allDescendants(ofType: NSView.self).first {
            $0.accessibilityIdentifier() == identifier
        })
    }

    func descendantTextField(withIdentifier identifier: String) throws -> NSTextField {
        try #require(allDescendants(ofType: NSTextField.self).first {
            $0.accessibilityIdentifier() == identifier
        })
    }
}
