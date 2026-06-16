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
}
