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

    /// 热力图 popover 尺寸要能容纳标题、星期行和 7 列日历网格。
    @Test func heatmapPopoverContentSizeFitsCalendarGrid() {
        #expect(StatusBarPopoverLayout.contentSize == NSSize(width: 300, height: 300))
    }

    /// 状态栏布局尺寸应复用 popover 内容控制器尺寸,避免两处常量漂移。
    @Test func statusBarPopoverLayoutMatchesContentControllerSize() {
        #expect(StatusBarPopoverLayout.contentSize == StatusPopoverViewController.contentSize)
    }
}
