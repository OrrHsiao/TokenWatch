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

    /// 状态栏菜单应走系统状态栏项 presenter,避免普通 view 坐标弹窗覆盖图标。
    @Test func statusMenuUsesStatusItemPresenter() {
        #expect(StatusBarMenuPresentation.presenter() == .statusItemMenu(selectorName: "popUpStatusItemMenu:"))
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

    /// 热力图 popover 尺寸要能容纳摘要方块、22 列网格和本日小时折线图。
    @Test func heatmapPopoverContentSizeFitsCalendarGrid() {
        #expect(StatusBarPopoverLayout.contentSize == NSSize(width: 370, height: 355))
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
        languageSettings.selectedPreference = .zhHans

        let controller = StatusBarController(
            viewModel: TokenStatsViewModel(),
            autoRefreshSettings: AutoRefreshSettings(defaults: defaults),
            languageSettings: languageSettings
        )
        defer { controller.stop() }

        #expect(controller.debugStatusMenuItemTitles == [
            "打开 TokenWatch",
            "立即刷新",
            "退出 TokenWatch",
        ])
        #expect(controller.debugTitlePlainString == "—\nTokens")

        languageSettings.selectedPreference = .en

        #expect(controller.debugStatusMenuItemTitles == [
            "Open TokenWatch",
            "Refresh Now",
            "Quit TokenWatch",
        ])
        #expect(controller.debugTitlePlainString == "—\nTokens")
    }
}
