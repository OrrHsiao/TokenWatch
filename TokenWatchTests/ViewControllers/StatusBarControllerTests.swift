import AppKit
import Testing
@testable import TokenWatch

struct StatusBarControllerTests {

    /// 普通左键用于切换 popover。
    @Test func leftMouseUpTogglesPopover() {
        #expect(StatusBarClickAction.resolve(
            eventType: .leftMouseUp,
            modifierFlags: []
        ) == .togglePopover)
    }

    /// 右键保留原状态栏菜单入口。
    @Test func rightMouseUpShowsMenu() {
        #expect(StatusBarClickAction.resolve(
            eventType: .rightMouseUp,
            modifierFlags: []
        ) == .showMenu)
    }

    /// macOS 惯例:Control-click 视作辅助点击,同样显示菜单。
    @Test func controlLeftClickShowsMenu() {
        #expect(StatusBarClickAction.resolve(
            eventType: .leftMouseUp,
            modifierFlags: [.control]
        ) == .showMenu)
    }

    /// Popover 的外部关闭只由控制器负责，避免 AppKit transient 在 mouseDown 抢先关闭后，
    /// mouseUp 的状态栏 action 又把它重新打开。
    @Test func popoverDismissalIsApplicationDefined() {
        #expect(StatusBarPopoverPolicy.behavior == .applicationDefined)
    }

    /// 普通左键应稳定完成「打开 -> 关闭」，关闭动画期间不复用同一轮 presentation。
    @Test func popoverLifecycleClosesTheShownPresentation() {
        var lifecycle = StatusPopoverLifecycle()

        #expect(lifecycle.toggle() == .show(1))
        #expect(lifecycle.phase == .shown(1))
        #expect(lifecycle.toggle() == .close(1))
        #expect(lifecycle.phase == .closing(1))
        #expect(lifecycle.didClose() == .none)
        #expect(lifecycle.phase == .hidden)
    }

    /// 关闭动画期间再次左键只记录重新打开意图；旧弹窗 didClose 后才创建新一代。
    @Test func popoverLifecycleReopensAfterTheClosingPresentationFinishes() {
        var lifecycle = StatusPopoverLifecycle()

        #expect(lifecycle.toggle() == .show(1))
        #expect(lifecycle.toggle() == .close(1))
        #expect(lifecycle.toggle() == .none)
        #expect(lifecycle.desiredVisible)

        #expect(lifecycle.didClose() == .show(2))
        #expect(lifecycle.phase == .shown(2))
        #expect(!lifecycle.ownsShownPresentation(1))
        #expect(lifecycle.ownsShownPresentation(2))
    }

    /// 右键菜单或背景关闭会取消尚未执行的 reopen，迟到回调不能恢复旧意图。
    @Test func popoverLifecycleDismissCancelsPendingReopen() {
        var lifecycle = StatusPopoverLifecycle()

        #expect(lifecycle.toggle() == .show(1))
        #expect(lifecycle.toggle() == .close(1))
        #expect(lifecycle.toggle() == .none)
        #expect(lifecycle.dismiss(generation: 1) == .none)

        #expect(lifecycle.didClose() == .none)
        #expect(lifecycle.phase == .hidden)
        #expect(!lifecycle.desiredVisible)
    }

    /// 从已展示状态打开右键菜单时，应关闭当前 presentation 且不安排 reopen。
    @Test func rightMenuDismissesTheShownPopover() {
        var lifecycle = StatusPopoverLifecycle()

        #expect(lifecycle.toggle() == .show(1))
        #expect(lifecycle.dismiss() == .close(1))
        #expect(lifecycle.phase == .closing(1))
        #expect(!lifecycle.desiredVisible)
        #expect(lifecycle.didClose() == .none)
        #expect(lifecycle.phase == .hidden)
    }

    /// 关闭期间的快速点击按最终奇偶意图收敛，不应无条件重新打开。
    @Test func repeatedToggleDuringClosingCanCancelPendingReopen() {
        var lifecycle = StatusPopoverLifecycle()

        #expect(lifecycle.toggle() == .show(1))
        #expect(lifecycle.toggle() == .close(1))
        #expect(lifecycle.toggle() == .none)
        #expect(lifecycle.toggle() == .none)

        #expect(lifecycle.didClose() == .none)
        #expect(lifecycle.phase == .hidden)
    }

    /// 所有异步 monitor / activation / highlight 回调必须绑定 presentation generation。
    @Test func stalePopoverPresentationCallbacksAreRejected() {
        var lifecycle = StatusPopoverLifecycle()

        #expect(lifecycle.toggle() == .show(1))
        #expect(lifecycle.toggle() == .close(1))
        #expect(lifecycle.toggle() == .none)
        #expect(lifecycle.didClose() == .show(2))

        #expect(lifecycle.dismiss(generation: 1) == .none)
        #expect(lifecycle.phase == .shown(2))
        #expect(lifecycle.ownsShownPresentation(2))
    }

    /// 状态栏菜单应走系统状态栏项 presenter,避免普通 view 坐标弹窗覆盖图标。
    @Test func statusMenuUsesStatusItemPresenter() {
        #expect(StatusBarMenuPresentation.presenter() == .statusItemMenu(selectorName: "popUpStatusItemMenu:"))
    }

    /// 状态栏双行标题通过富文本基线下移修正视觉居中,不替换系统状态栏 cell。
    @Test func statusBarTitleTextUsesDownwardBaselineOffset() {
        #expect(StatusBarTitleTextLayout.baselineOffset < 0)
    }

    /// 状态栏图标通过透明右留白拉开与文字的距离,避免在标题字符串里塞空格。
    @Test func statusBarIconAddsTrailingSpacingBeforeTitle() {
        #expect(StatusBarIconLayout.pointSize == 18)
        #expect(StatusBarIconLayout.pointSize < 20)
        #expect(StatusBarIconLayout.imageTitleSpacing == 4)
        #expect(StatusBarIconLayout.canvasSize(for: NSSize(width: 20, height: 18)) == NSSize(width: 24, height: 18))

        let image = NSImage(size: NSSize(width: 20, height: 18))
        image.isTemplate = true
        let paddedImage = StatusBarIconLayout.imageWithTrailingSpacing(image)
        #expect(paddedImage.size == NSSize(width: 24, height: 18))
        #expect(paddedImage.isTemplate)
    }

    /// 状态栏按钮必须使用 AppKit 原生 image + attributedTitle。
    /// 自定义子视图或自定义 cell 都会绕过系统状态栏绘制语义,可能造成重绘或垂直位置异常。
    @MainActor
    @Test func statusBarButtonUsesNativeCellImageAndTitleWithoutCustomLayoutSubviews() throws {
        let suiteName = "StatusBarControllerTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let controller = StatusBarController(
            viewModel: TokenStatsViewModel(),
            quotaStore: inertQuotaStore(),
            autoRefreshSettings: AutoRefreshSettings(defaults: defaults),
            displaySettings: StatusBarDisplaySettings(defaults: defaults)
        )
        defer { controller.stop() }

        #expect(controller.debugStatusButtonCustomSubviewCount == 0)
        #expect(controller.debugStatusItemLength == NSStatusItem.variableLength)
        #expect(!controller.debugStatusButtonUsesCustomCell)
        #expect(controller.debugTitleBaselineOffsets.allSatisfy { $0 == StatusBarTitleTextLayout.baselineOffset })
    }

    /// 阿拉伯语只翻译文案；状态栏按钮和右键菜单仍固定左到右。
    @MainActor
    @Test func statusBarSurfacesStayLeftToRight() throws {
        let suiteName = "StatusBarControllerTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let languageSettings = AppLanguageSettings(defaults: defaults)
        languageSettings.selectedPreference = .language(.ar)
        let controller = StatusBarController(
            viewModel: TokenStatsViewModel(languageSettings: languageSettings),
            autoRefreshSettings: AutoRefreshSettings(defaults: defaults),
            languageSettings: languageSettings
        )
        defer { controller.stop() }
        let statusMenu = try #require(
            Mirror(reflecting: controller).children.first { $0.label == "statusMenu" }?.value as? NSMenu
        )
        let statusItem = try #require(
            Mirror(reflecting: controller).children.first { $0.label == "statusItem" }?.value as? NSStatusItem
        )

        #expect(statusMenu.userInterfaceLayoutDirection == .leftToRight)
        #expect(statusItem.button?.userInterfaceLayoutDirection == .leftToRight)
    }

    /// popover 显示期间应让状态栏按钮保持系统高亮背景。
    @Test func popoverShownHighlightsStatusButton() {
        #expect(StatusBarButtonHighlight.isHighlighted(popoverIsShown: true))
    }

    /// popover 关闭后应清掉状态栏按钮高亮背景。
    @Test func popoverClosedClearsStatusButtonHighlight() {
        #expect(!StatusBarButtonHighlight.isHighlighted(popoverIsShown: false))
    }

    /// 打开 popover 后的高亮要延迟到 mouseUp 跟踪结束后应用,避免被 AppKit 复原。
    @Test func popoverShownDefersStatusButtonHighlight() {
        #expect(StatusBarButtonHighlight.applicationTiming(popoverIsShown: true) == .afterCurrentEvent)
    }

    /// 关闭 popover 时可以立即清掉高亮,避免留下残影。
    @Test func popoverClosedClearsStatusButtonHighlightImmediately() {
        #expect(StatusBarButtonHighlight.applicationTiming(popoverIsShown: false) == .immediate)
    }

    /// 原统计区保持 370 × 355pt；弹窗总高度只在其上累加订阅区高度，不压缩原区域。
    @Test func heatmapPopoverContentSizeFitsCalendarGrid() {
        #expect(StatusPopoverViewController.originalContentSize == NSSize(width: 370, height: 355))
        #expect(StatusBarPopoverLayout.contentSize == NSSize(
            width: 370,
            height: 355 + SubscriptionQuotaSectionLayout.height
        ))
        #expect((550...590).contains(StatusBarPopoverLayout.contentSize.height))
    }

    /// 状态栏布局尺寸应复用 popover 内容控制器尺寸,避免两处常量漂移。
    @Test func statusBarPopoverLayoutMatchesContentControllerSize() {
        #expect(StatusBarPopoverLayout.contentSize == StatusPopoverViewController.contentSize)
    }

    /// Popover 显示后点击背景应关闭视图。
    @Test func popoverBackgroundClickDismissesPopover() {
        #expect(StatusPopoverOutsideClick.resolve(
            isPopoverShown: true,
            eventTarget: .background
        ) == .closePopover)
    }

    /// 点击状态栏按钮时交给按钮 action 处理,避免背景监听先关闭再被 action 重新打开。
    @Test func popoverStatusButtonClickKeepsPopoverForButtonAction() {
        #expect(StatusPopoverOutsideClick.resolve(
            isPopoverShown: true,
            eventTarget: .statusButton
        ) == .keepPopover)
    }

    /// 点击 popover 内部时不应被背景逻辑关闭,为后续内容交互预留空间。
    @Test func popoverContentClickKeepsPopover() {
        #expect(StatusPopoverOutsideClick.resolve(
            isPopoverShown: true,
            eventTarget: .popover
        ) == .keepPopover)
    }

    /// Popover 显示后应激活应用、让窗口成为 key,并把内容视图设为 first responder。
    @Test func popoverShownRequestsFirstResponderActivation() {
        #expect(StatusPopoverActivation.actions(isPopoverShown: true) == [
            .activateApplication,
            .makePopoverWindowKey,
            .makeContentFirstResponder,
        ])
    }

    /// Popover 外观应与应用当前有效外观同步，避免默认继承状态栏暗色外观。
    @MainActor
    @Test func popoverAppearanceSynchronizesWithAppAppearance() {
        let controller = StatusBarController(viewModel: TokenStatsViewModel())
        defer { controller.stop() }

        #expect(controller.debugPopoverAppearance?.name == NSApp.effectiveAppearance.name)
    }

    /// 从状态栏菜单打开主窗口时,应等菜单 action 结束后再激活并强制置前已有窗口。
    @Test func mainWindowOpenFromStatusMenuDefersAndOrdersWindowFrontRegardless() {
        #expect(StatusMainWindowPresentation.timing() == .afterCurrentEvent)
        #expect(StatusMainWindowPresentation.actions(targetWindowExists: true) == [
            .activateApplication,
            .makeWindowKeyAndOrderFront,
            .orderWindowFrontRegardless,
        ])
    }

    /// 空 popover 根视图也需要能成为 first responder,否则 makeFirstResponder 会失败。
    @Test func emptyPopoverViewAcceptsFirstResponder() async {
        await MainActor.run {
            let view = EmptyStatusPopoverView(frame: .zero)

            #expect(view.acceptsFirstResponder)
        }
    }

    /// 自动刷新间隔来自持久化设置,设置变化后状态栏定时器应立即重建。
    @MainActor
    @Test func autoRefreshTimerFollowsPersistedSettingChanges() throws {
        let suiteName = "StatusBarControllerTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let settings = AutoRefreshSettings(defaults: defaults)
        settings.selectedOption = .minutes5

        let controller = StatusBarController(
            viewModel: TokenStatsViewModel(),
            autoRefreshSettings: settings
        )
        defer { controller.stop() }

        #expect(controller.debugRefreshTimerInterval == 300)

        settings.selectedOption = .disabled
        #expect(controller.debugRefreshTimerInterval == nil)
    }

    /// 状态栏菜单文案应跟随语言设置变化,且切换语言只重绘 UI。
    @MainActor
    @Test func statusMenuTitlesFollowLanguageChanges() throws {
        let suiteName = "StatusBarControllerTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let languageSettings = AppLanguageSettings(
            defaults: defaults,
            preferredLanguagesProvider: { ["zh-Hans"] }
        )
        languageSettings.selectedPreference = .language(.zhHans)

        let displaySettings = StatusBarDisplaySettings(defaults: defaults)
        displaySettings.mode = .todayTokens
        let controller = StatusBarController(
            viewModel: TokenStatsViewModel(),
            quotaStore: inertQuotaStore(),
            autoRefreshSettings: AutoRefreshSettings(defaults: defaults),
            languageSettings: languageSettings,
            displaySettings: displaySettings
        )
        defer { controller.stop() }

        #expect(controller.debugStatusMenuItemTitles == [
            "打开 AI Token Watch",
            "立即刷新",
            "状态栏显示",
            "额度周期",
            "选择 Claude 额度文件…",
            "退出 AI Token Watch",
        ])
        #expect(controller.debugDisplayModeMenuTitles == ["订阅额度 + 今日 Tokens", "订阅额度", "今日 Tokens"])
        #expect(controller.debugCheckedDisplayModeTitle == "今日 Tokens")
        #expect(controller.debugQuotaWindowsMenuTitles == ["两个周期", "5 小时", "一周"])
        #expect(controller.debugTitlePlainString == "—\nTokens")

        languageSettings.selectedPreference = .language(.viVN)

        #expect(controller.debugStatusMenuItemTitles.first == "Mở AI Token Watch")
        #expect(controller.debugStatusMenuItemTitles[1] == "Làm mới ngay")
        #expect(controller.debugStatusMenuItemTitles.last == "Thoát AI Token Watch")
        #expect(controller.debugTitlePlainString == "—\nTokens")
    }

    /// 状态栏按钮 ToolTip 包含今日总量并在有近时消耗时包含燃烧速率
    @MainActor
    @Test func statusButtonToolTipShowsTodayTokensAndBurnRate() throws {
        let suiteName = "StatusBarControllerTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let languageSettings = AppLanguageSettings(
            defaults: defaults,
            preferredLanguagesProvider: { ["zh-Hans"] }
        )
        languageSettings.selectedPreference = .language(.zhHans)

        let displaySettings = StatusBarDisplaySettings(defaults: defaults)
        displaySettings.mode = .todayTokens
        let controller = StatusBarController(
            viewModel: TokenStatsViewModel(),
            quotaStore: inertQuotaStore(),
            autoRefreshSettings: AutoRefreshSettings(defaults: defaults),
            languageSettings: languageSettings,
            displaySettings: displaySettings
        )
        defer { controller.stop() }

        #expect(controller.debugStatusButtonToolTip == "TokenWatch · — Tokens")
    }

    /// 纯额度模式:单张原生图像承载圆环与百分比,不使用 attributedTitle,也不跑 token 加载动画。
    @MainActor
    @Test func quotaModeRendersSingleNativeImageWithoutTitle() async throws {
        let suiteName = "StatusBarControllerTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let languageSettings = AppLanguageSettings(
            defaults: defaults,
            preferredLanguagesProvider: { ["zh-Hans"] }
        )
        languageSettings.selectedPreference = .language(.zhHans)
        let displaySettings = StatusBarDisplaySettings(defaults: defaults)
        displaySettings.mode = .subscriptionQuota
        let quotaStore = inertQuotaStore(isDemoMode: true)
        await quotaStore.refresh()

        let controller = StatusBarController(
            viewModel: TokenStatsViewModel(),
            quotaStore: quotaStore,
            autoRefreshSettings: AutoRefreshSettings(defaults: defaults),
            languageSettings: languageSettings,
            displaySettings: displaySettings
        )
        defer { controller.stop() }

        #expect(displaySettings.mode == .subscriptionQuota)
        #expect(controller.debugRenderedDisplayMode == .subscriptionQuota)
        #expect(controller.debugStatusButtonImagePosition != .imageLeft)
        #expect(controller.debugTitlePlainString == "")
        #expect(controller.debugStatusButtonCustomSubviewCount == 0)
        #expect(!controller.debugStatusButtonUsesCustomCell)
        #expect(controller.debugQuotaPresentationTimerInterval == 60)
        let model = try #require(controller.debugLastRenderedQuotaModel)
        #expect(model.groups.map { $0.rings.map(\.valueText) } == [["68%", "86%"], ["88%", "98%"]])
        let toolTip = try #require(controller.debugStatusButtonToolTip)
        #expect(toolTip.hasPrefix("Claude · 记录于 2 分钟前\n5 小时 · 剩余 68% · "))
        #expect(toolTip.contains("\n\nCodex · 记录于 刚刚\n"))

        let imageSize = try #require(controller.debugStatusButtonImageSize)
        displaySettings.quotaWindows = .fiveHour
        #expect(try #require(controller.debugLastRenderedQuotaModel).groups.map { $0.rings.count } == [1, 1])
        #expect(try #require(controller.debugStatusButtonImageSize).width < imageSize.width)

        displaySettings.mode = .todayTokens
        #expect(controller.debugRenderedDisplayMode == .todayTokens)
        #expect(controller.debugStatusButtonImagePosition == .imageLeft)
        #expect(controller.debugTitlePlainString == "—\nTokens")
        #expect(controller.debugQuotaPresentationTimerInterval == nil)
        #expect(controller.debugCheckedDisplayModeTitle == "今日 Tokens")
    }

    /// 默认同时展示:原有图标 + 今日 token 双行文本在前,额度圆环在后,悬停说明按同一顺序包含两部分。
    @MainActor
    @Test func defaultModeShowsQuotaAndTodayTokens() async throws {
        let suiteName = "StatusBarControllerTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let languageSettings = AppLanguageSettings(
            defaults: defaults,
            preferredLanguagesProvider: { ["zh-Hans"] }
        )
        languageSettings.selectedPreference = .language(.zhHans)
        let displaySettings = StatusBarDisplaySettings(defaults: defaults)
        let quotaStore = inertQuotaStore(isDemoMode: true)
        await quotaStore.refresh()

        let controller = StatusBarController(
            viewModel: TokenStatsViewModel(),
            quotaStore: quotaStore,
            autoRefreshSettings: AutoRefreshSettings(defaults: defaults),
            languageSettings: languageSettings,
            displaySettings: displaySettings
        )
        defer { controller.stop() }

        #expect(displaySettings.mode == .quotaAndTodayTokens)
        #expect(controller.debugRenderedDisplayMode == .quotaAndTodayTokens)
        // 原生标题只能位于图像一侧,组合模式把今日 token 文本绘制进图像以排在圆环之前。
        #expect(controller.debugStatusButtonImagePosition != .imageLeft)
        #expect(controller.debugTitlePlainString == "")
        #expect(controller.debugRenderedTokenPrimary == "—")
        #expect(controller.debugStatusButtonCustomSubviewCount == 0)
        #expect(controller.debugQuotaPresentationTimerInterval == 60)
        #expect(controller.debugCheckedDisplayModeTitle == "订阅额度 + 今日 Tokens")
        let model = try #require(controller.debugLastRenderedQuotaModel)
        #expect(model.groups.map { $0.rings.map(\.valueText) } == [["68%", "86%"], ["88%", "98%"]])
        let toolTip = try #require(controller.debugStatusButtonToolTip)
        #expect(toolTip.hasPrefix("TokenWatch · — Tokens\n\nClaude · 记录于 2 分钟前\n"))
        let combinedWidth = try #require(controller.debugStatusButtonImageSize).width
        #expect(combinedWidth > StatusBarQuotaLayout.imageSize(for: model).width)

        displaySettings.mode = .subscriptionQuota
        #expect(controller.debugTitlePlainString == "")
        #expect(try #require(controller.debugStatusButtonImageSize).width < combinedWidth)

        displaySettings.mode = .todayTokens
        #expect(controller.debugTitlePlainString == "—\nTokens")
        #expect(controller.debugRenderedTokenPrimary == nil)

        displaySettings.mode = .quotaAndTodayTokens
        #expect(controller.debugTitlePlainString == "")
        #expect(try #require(controller.debugStatusButtonImageSize).width == combinedWidth)
    }

    /// 额度来源状态未变化时不重新赋值状态栏图像,避免触发重复布局。
    @MainActor
    @Test func unchangedQuotaDoesNotReplaceStatusImage() async throws {
        let suiteName = "StatusBarControllerTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let quotaStore = inertQuotaStore(isDemoMode: true)
        await quotaStore.refresh()
        let controller = StatusBarController(
            viewModel: TokenStatsViewModel(),
            quotaStore: quotaStore,
            autoRefreshSettings: AutoRefreshSettings(defaults: defaults),
            languageSettings: AppLanguageSettings(defaults: defaults),
            displaySettings: StatusBarDisplaySettings(defaults: defaults)
        )
        defer { controller.stop() }
        let statusItem = try #require(
            Mirror(reflecting: controller).children.first { $0.label == "statusItem" }?.value as? NSStatusItem
        )
        let firstImage = try #require(statusItem.button?.image)

        controller.debugRenderTitle()

        #expect(statusItem.button?.image === firstImage)
    }
}

/// 不访问真实 bookmark 与文件系统的额度 store；Demo 模式下返回确定性快照。
@MainActor
private func inertQuotaStore(isDemoMode: Bool = false) -> SubscriptionQuotaStore {
    SubscriptionQuotaStore(
        bookmarkManager: NoQuotaBookmarks(),
        languageProvider: { .zhHans },
        isDemoModeEnabled: { isDemoMode }
    )
}

@MainActor
private struct NoQuotaBookmarks: SubscriptionQuotaBookmarkAccessing {
    func hasBookmark(forKey key: String) -> Bool { false }
    func restoreBookmarkAndAccess(forKey key: String) -> URL? { nil }
    func stopAccessing(forKey key: String) {}
    func persistSelectedDirectory(_ url: URL, forKey key: String) -> Bool { false }
}
