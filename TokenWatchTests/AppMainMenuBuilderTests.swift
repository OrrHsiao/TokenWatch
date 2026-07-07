import AppKit
import Testing
@testable import TokenWatch

@MainActor
struct AppMainMenuBuilderTests {

    @Test func mainMenuOnlyContainsActionableTopLevelMenus() {
        let actionTarget = AppDelegate()
        let menu = AppMainMenuBuilder.build(actionTarget: actionTarget)

        #expect(menu.items.map(\.title) == ["AI Token Watch", "Window"])
    }

    @Test func applicationMenuContainsOnlySupportedCommands() throws {
        let actionTarget = AppDelegate()
        let menu = AppMainMenuBuilder.build(actionTarget: actionTarget)
        let appMenu = try #require(menu.items.first?.submenu)
        let items = appMenu.items.filter { !$0.isSeparatorItem }

        #expect(items.map(\.title) == [
            "About AI Token Watch",
            "Open AI Token Watch",
            "Settings...",
            "Refresh Now",
            "Hide AI Token Watch",
            "Hide Others",
            "Show All",
            "Quit AI Token Watch",
        ])
        #expect(items.map { $0.action.map(NSStringFromSelector) } == [
            "orderFrontStandardAboutPanel:",
            "openMainWindow:",
            "showSettings:",
            "refreshNow:",
            "hide:",
            "hideOtherApplications:",
            "unhideAllApplications:",
            "terminate:",
        ])
        #expect(items[1].target === actionTarget)
        #expect(items[2].target === actionTarget)
        #expect(items[3].target === actionTarget)
    }

    @Test func mainMenuUsesChineseTitlesWhenLanguageIsChinese() throws {
        let actionTarget = AppDelegate()
        let menu = AppMainMenuBuilder.build(actionTarget: actionTarget, language: .zhHans)
        let appMenu = try #require(menu.items.first?.submenu)
        let windowMenu = try #require(menu.item(withTitle: "窗口")?.submenu)

        #expect(menu.items.map(\.title) == ["AI Token Watch", "窗口"])
        #expect(appMenu.items.filter { !$0.isSeparatorItem }.map(\.title) == [
            "关于 AI Token Watch",
            "打开 AI Token Watch",
            "设置...",
            "立即刷新",
            "隐藏 AI Token Watch",
            "隐藏其他",
            "全部显示",
            "退出 AI Token Watch",
        ])
        #expect(windowMenu.items.filter { !$0.isSeparatorItem }.map(\.title) == [
            "最小化",
            "缩放",
            "全部置于前面",
        ])
    }

    @Test func installedMainMenuFollowsLanguageChanges() throws {
        let suiteName = "AppMainMenuBuilderTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let languageSettings = AppLanguageSettings(
            defaults: defaults,
            preferredLanguagesProvider: { ["zh-Hans"] }
        )
        let previousMainMenu = NSApp.mainMenu
        let previousWindowsMenu = NSApp.windowsMenu
        let controller = AppMainMenuController(
            actionTarget: AppDelegate(),
            languageSettings: languageSettings
        )
        controller.start()
        defer {
            controller.stop()
            NSApp.mainMenu = previousMainMenu
            NSApp.windowsMenu = previousWindowsMenu
        }

        #expect(NSApp.mainMenu?.items.map(\.title) == ["AI Token Watch", "窗口"])

        languageSettings.selectedPreference = .en

        #expect(NSApp.mainMenu?.items.map(\.title) == ["AI Token Watch", "Window"])
    }

    @Test func windowMenuContainsOnlySupportedWindowCommands() throws {
        let actionTarget = AppDelegate()
        let menu = AppMainMenuBuilder.build(actionTarget: actionTarget)
        let windowMenu = try #require(menu.item(withTitle: "Window")?.submenu)
        let items = windowMenu.items.filter { !$0.isSeparatorItem }

        #expect(items.map(\.title) == [
            "Minimize",
            "Zoom",
            "Bring All to Front",
        ])
        #expect(items.map { $0.action.map(NSStringFromSelector) } == [
            "performMiniaturize:",
            "performZoom:",
            "arrangeInFront:",
        ])
    }
}
