import AppKit
import Testing
@testable import TokenWatch

@MainActor
@Suite("StatusPopoverViewController")
struct StatusPopoverViewControllerTests {

    @Test("加载后创建摘要方块和二十二列热力图 collection view")
    func loadViewCreatesTwentyTwoColumnCollectionView() {
        let controller = makeController(language: .zhHans)

        controller.loadViewIfNeeded()

        #expect(controller.debugSummaryCards.map(\.title) == ["本月", "本周", "今日", "日均"])
        #expect(controller.debugSummaryCards.map(\.value) == ["0", "0", "0", "0"])
        #expect(controller.debugSummaryCards.map(\.toolTip) == ["本月 0 Tokens", "本周 0 Tokens", "今日 0 Tokens", "日均 0 Tokens"])
        #expect(controller.debugSummaryCards.map(\.styleName) == ["neutral", "neutral", "neutral", "neutral"])
        #expect(controller.debugSummaryCards.allSatisfy { $0.hasBackgroundColor })
        #expect(controller.debugSummaryCards.allSatisfy { !$0.hasBorder })
        #expect(controller.debugSummaryCards.allSatisfy { $0.cornerRadius == 8 })
        #expect(controller.debugTodayDescriptionText == "本日还没有消耗 token 哦～")
        #expect(controller.debugTodayDescriptionAlignment == .left)
        #expect(controller.debugTodayDescriptionRowCenteredInRoot)
        #expect(controller.debugTodayDescriptionLabelSitsAboveSummary)
        #expect(controller.debugCollectionView != nil)
        #expect(controller.debugWeekdayLabelCount == 0)
        #expect(controller.debugCollectionItemCount == 154)
        #expect(controller.debugHourlyLineChartView != nil)
        #expect(controller.debugHourlyLineChartPointCount == 24)
        #expect(controller.debugHourlyLineChartXAxisLabels == ["0", "6", "12", "18", "23"])
    }

    @Test("本日 token 文案右侧展示 SF Symbols 刷新按钮")
    func todayDescriptionShowsRefreshButtonOnRight() {
        let controller = makeController()

        controller.loadViewIfNeeded()

        #expect(controller.debugRefreshButtonTitle == "")
        #expect(controller.debugRefreshButtonSymbolName == "arrow.clockwise")
        #expect(controller.debugRefreshButtonUsesImageOnly)
        #expect(controller.debugRefreshButtonToolTip == "立即刷新")
        #expect(controller.debugRefreshButtonAccessibilityLabel == "刷新本日 token 消耗")
        #expect(controller.debugRefreshButtonImageAccessibilityDescription == "立即刷新")
        #expect(controller.debugRefreshButtonSitsRightOfDescriptionLabel)
        #expect(controller.debugRefreshButtonTrailingAlignsWithDescriptionRow)
        #expect(controller.debugRefreshButtonActionName == "refreshTodayStats:")
    }

    @Test("刷新按钮使用 ghost hover 样式")
    func refreshButtonUsesGhostHoverStyle() {
        let controller = makeController()

        controller.loadViewIfNeeded()

        #expect(controller.debugRefreshButtonCornerRadius == 6)
        #expect(!controller.debugRefreshButtonHasBackground)

        controller.debugSetRefreshButtonHovering(true)
        #expect(controller.debugRefreshButtonHasBackground)

        controller.debugSetRefreshButtonHovering(false)
        #expect(!controller.debugRefreshButtonHasBackground)
    }

    @Test("刷新按钮 loading 时禁用并显示同步图标")
    func refreshButtonShowsLoadingFeedback() {
        let controller = makeController()

        controller.loadViewIfNeeded()
        controller.debugSetRefreshButtonLoading(true)

        #expect(!controller.debugRefreshButtonIsEnabled)
        #expect(controller.debugRefreshButtonSymbolName == "arrow.triangle.2.circlepath")
        #expect(controller.debugRefreshButtonToolTip == "正在刷新")
        #expect(controller.debugRefreshButtonAccessibilityLabel == "正在刷新本日 token 消耗")
        #expect(controller.debugRefreshButtonImageAccessibilityDescription == "正在刷新")

        controller.debugSetRefreshButtonLoading(false)
        #expect(controller.debugRefreshButtonIsEnabled)
        #expect(controller.debugRefreshButtonSymbolName == "arrow.clockwise")
        #expect(controller.debugRefreshButtonToolTip == "立即刷新")
    }

    @Test("本日 token 文案按消耗分档")
    func todayDescriptionTextReflectsUsageTier() {
        #expect(StatusPopoverDailyTokenDescription.text(forTodayTokens: 0, language: .zhHans) == "本日还没有消耗 token 哦～")
        #expect(StatusPopoverDailyTokenDescription.text(forTodayTokens: 100_000, language: .zhHans) == "本日 token 消耗正在加速～")
        #expect(StatusPopoverDailyTokenDescription.text(forTodayTokens: 6_700_000, language: .zhHans) == "本日 token 消耗爆表～")
        #expect(StatusPopoverDailyTokenDescription.text(forTodayTokens: 0, language: .en) == "No token usage today")
        #expect(StatusPopoverDailyTokenDescription.text(forTodayTokens: 100_000, language: .en) == "Today's token usage is picking up")
        #expect(StatusPopoverDailyTokenDescription.text(forTodayTokens: 6_700_000, language: .en) == "Today's token usage is off the charts")
    }

    @Test("英文语言下摘要、描述和刷新按钮文案使用英文")
    func englishLanguageLocalizesSummaryDescriptionAndRefreshButton() {
        let controller = makeController(language: .en)

        controller.loadViewIfNeeded()

        #expect(controller.debugSummaryCards.map(\.title) == ["Month", "Week", "Today", "Daily Avg"])
        #expect(controller.debugSummaryCards.map(\.toolTip) == ["Month 0 Tokens", "Week 0 Tokens", "Today 0 Tokens", "Daily Avg 0 Tokens"])
        #expect(controller.debugTodayDescriptionText == "No token usage today")
        #expect(controller.debugRefreshButtonToolTip == "Refresh Now")
        #expect(controller.debugRefreshButtonAccessibilityLabel == "Refresh today's token usage")
        #expect(controller.debugRefreshButtonImageAccessibilityDescription == "Refresh Now")

        controller.debugSetRefreshButtonLoading(true)

        #expect(controller.debugRefreshButtonToolTip == "Refreshing")
        #expect(controller.debugRefreshButtonAccessibilityLabel == "Refreshing today's token usage")
        #expect(controller.debugRefreshButtonImageAccessibilityDescription == "Refreshing")
    }

    @Test("语言切换时重新渲染弹窗可见文案")
    func languageChangeRerendersVisibleText() throws {
        let suiteName = "StatusPopoverViewControllerTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let languageSettings = AppLanguageSettings(defaults: defaults, preferredLanguagesProvider: { ["zh-Hans"] })
        languageSettings.selectedPreference = .zhHans
        let controller = StatusPopoverViewController(
            viewModel: TokenStatsViewModel(languageSettings: languageSettings),
            nowProvider: { fixedDate() },
            calendar: fixedCalendar(),
            languageSettings: languageSettings
        )

        controller.loadViewIfNeeded()
        #expect(controller.debugSummaryCards.map(\.title) == ["本月", "本周", "今日", "日均"])
        #expect(controller.debugTodayDescriptionText == "本日还没有消耗 token 哦～")

        languageSettings.selectedPreference = .en

        #expect(controller.debugSummaryCards.map(\.title) == ["Month", "Week", "Today", "Daily Avg"])
        #expect(controller.debugTodayDescriptionText == "No token usage today")
        #expect(controller.debugRefreshButtonToolTip == "Refresh Now")
    }

    @Test("根视图使用动态窗口背景")
    func rootViewUsesDynamicWindowBackground() {
        let controller = makeController()

        controller.loadViewIfNeeded()

        #expect(controller.view is StatusPopoverRootView)
    }

    @Test("collection view 使用固定 7 行网格高度")
    func collectionViewUsesFixedGridHeight() {
        let controller = makeController()

        controller.loadViewIfNeeded()
        controller.view.layoutSubtreeIfNeeded()

        #expect(controller.debugCollectionHeight == StatusPopoverViewController.debugExpectedCollectionHeight)
        #expect(controller.debugCollectionView?.frame.height == StatusPopoverViewController.debugExpectedCollectionHeight)
    }

    @Test("collection view 宽度完整容纳二十二周列")
    func collectionViewWidthFitsTwentyTwoWeekColumns() {
        let controller = makeController()

        controller.loadViewIfNeeded()
        controller.view.layoutSubtreeIfNeeded()

        #expect(controller.debugCollectionView?.frame.width == 327)
    }

    @Test("本日小时折线图位于热力图下方并与热力图等宽")
    func hourlyLineChartSitsBelowHeatmapAndMatchesWidth() {
        let controller = makeController()

        controller.loadViewIfNeeded()
        controller.view.layoutSubtreeIfNeeded()

        #expect(controller.debugHourlyLineChartSitsBelowCollectionView)
        #expect(controller.debugHourlyLineChartWidthMatchesCollectionView)
        #expect(controller.debugHourlyLineChartBottomFitsInRootBounds)
    }

    @Test("collection view 使用 GitHub 风格小方格布局")
    func collectionViewUsesGitHubStyleGridLayout() throws {
        let controller = makeController()

        controller.loadViewIfNeeded()

        let collectionView = try #require(controller.debugCollectionView)
        let layout = try #require(collectionView.collectionViewLayout as? NSCollectionViewFlowLayout)

        #expect(layout.itemSize == NSSize(width: 12, height: 12))
        #expect(layout.minimumInteritemSpacing == 3)
        #expect(layout.minimumLineSpacing == 3)
        #expect(layout.scrollDirection == .horizontal)
    }

    @Test("collection view 底部保留弹窗边距")
    func collectionViewBottomStaysInsidePopoverBounds() {
        let controller = makeController()

        controller.loadViewIfNeeded()
        controller.view.layoutSubtreeIfNeeded()

        #expect(controller.debugCollectionViewBottomFitsInRootBounds)
    }

    @Test("data source 返回快照数量")
    func dataSourceReturnsSnapshotCount() throws {
        let controller = makeController()

        controller.loadViewIfNeeded()

        let collectionView = try #require(controller.debugCollectionView)
        #expect(controller.collectionView(collectionView, numberOfItemsInSection: 0) == 154)
    }

    @Test("hover token 文案展示在热力图右上角并可恢复")
    func hoverTextAppearsAtHeatmapTopTrailingCorner() throws {
        let controller = makeController()

        controller.loadViewIfNeeded()
        let defaultSummaryCards = controller.debugSummaryCards
        controller.view.layoutSubtreeIfNeeded()
        controller.debugUpdateHoverText("2026-06-10 · 12,345 tokens")
        controller.view.layoutSubtreeIfNeeded()

        #expect(controller.debugSummaryCards == defaultSummaryCards)
        #expect(controller.debugHoverText == "2026-06-10 · 12,345 tokens")
        #expect(controller.debugHoverLabelTrailingAlignsWithCollectionView)
        #expect(controller.debugHoverLabelLeadingAlignsWithCollectionView)
        #expect(controller.debugHoverLabelSitsJustAboveCollectionView)
        #expect(try label(named: "hoverLabel", in: controller).textColor == .secondaryLabelColor)

        controller.debugUpdateHoverText(nil)
        controller.view.layoutSubtreeIfNeeded()

        #expect(controller.debugSummaryCards == defaultSummaryCards)
        #expect(controller.debugHoverText == "")
    }

    @Test("折线图 hover 复用热力图 hover label")
    func hourlyLineChartHoverUsesSharedHoverLabel() {
        let controller = makeController()

        controller.loadViewIfNeeded()
        controller.debugSimulateHourlyLineChartHover(monthKey: "2026-06-17T09")

        #expect(controller.debugHoverText == "9时 · 0.0M")

        controller.debugSimulateHourlyLineChartHover(monthKey: nil)
        #expect(controller.debugHoverText == "")
    }

    @Test("cell 访问对越界索引做保护")
    func cellAccessChecksItemBounds() {
        let controller = makeController()

        controller.loadViewIfNeeded()

        #expect(controller.debugHasCell(at: 0))
        #expect(!controller.debugHasCell(at: 999))
    }

    private func makeController(language: AppLanguage = .zhHans) -> StatusPopoverViewController {
        let suiteName = "StatusPopoverViewControllerTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        let languageSettings = AppLanguageSettings(defaults: defaults, preferredLanguagesProvider: {
            language == .zhHans ? ["zh-Hans"] : ["en-US"]
        })
        languageSettings.selectedPreference = language == .zhHans ? .zhHans : .en
        let controller = StatusPopoverViewController(
            viewModel: TokenStatsViewModel(languageSettings: languageSettings),
            nowProvider: { fixedDate() },
            calendar: fixedCalendar(),
            languageSettings: languageSettings
        )
        defaults.removePersistentDomain(forName: suiteName)
        return controller
    }

    private func fixedCalendar() -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        calendar.firstWeekday = 2
        return calendar
    }

    private func fixedDate() -> Date {
        fixedCalendar().date(from: DateComponents(year: 2026, month: 6, day: 17))!
    }

    private func label(named name: String, in controller: StatusPopoverViewController) throws -> NSTextField {
        let child = Mirror(reflecting: controller).children.first { $0.label == name }
        return try #require(child?.value as? NSTextField)
    }
}
