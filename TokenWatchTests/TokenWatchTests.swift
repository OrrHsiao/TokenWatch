//
//  TokenWatchTests.swift
//  TokenWatchTests
//
//  Created by OrrHsiao on 2026/6/13.
//

import Testing
import AppKit
@testable import TokenWatch

struct TokenWatchTests {

    @MainActor
    @Test func firstLaunchWithoutBookmarkRequestsInitialAuthorization() async {
        var didLoadAllStats = false
        var didRequestAuthorization = false
        var didMarkPrompted = false

        let coordinator = AppLaunchAuthorizationCoordinator(
            hasBookmark: { false },
            hasPromptedInitialAuthorization: { false },
            markInitialAuthorizationPrompted: { didMarkPrompted = true },
            loadAllStats: { didLoadAllStats = true },
            requestInitialAuthorization: {
                didRequestAuthorization = true
                return true
            }
        )

        await coordinator.performStartupWork()

        #expect(didRequestAuthorization)
        #expect(didMarkPrompted)
        #expect(!didLoadAllStats)
    }

    @MainActor
    @Test func startupWithBookmarkLoadsStatsWithoutInitialAuthorization() async {
        var didLoadAllStats = false
        var didRequestAuthorization = false
        var didMarkPrompted = false

        let coordinator = AppLaunchAuthorizationCoordinator(
            hasBookmark: { true },
            hasPromptedInitialAuthorization: { false },
            markInitialAuthorizationPrompted: { didMarkPrompted = true },
            loadAllStats: { didLoadAllStats = true },
            requestInitialAuthorization: {
                didRequestAuthorization = true
                return true
            }
        )

        await coordinator.performStartupWork()

        #expect(didLoadAllStats)
        #expect(!didRequestAuthorization)
        #expect(!didMarkPrompted)
    }

    @MainActor
    @Test func startupAfterInitialPromptAttemptLoadsStatsWithoutReprompting() async {
        var didLoadAllStats = false
        var didRequestAuthorization = false
        var didMarkPrompted = false

        let coordinator = AppLaunchAuthorizationCoordinator(
            hasBookmark: { false },
            hasPromptedInitialAuthorization: { true },
            markInitialAuthorizationPrompted: { didMarkPrompted = true },
            loadAllStats: { didLoadAllStats = true },
            requestInitialAuthorization: {
                didRequestAuthorization = true
                return true
            }
        )

        await coordinator.performStartupWork()

        #expect(didLoadAllStats)
        #expect(!didRequestAuthorization)
        #expect(!didMarkPrompted)
    }

    @MainActor
    @Test func canceledInitialAuthorizationFallsBackToStatsLoad() async {
        var didLoadAllStats = false
        var didRequestAuthorization = false
        var didMarkPrompted = false

        let coordinator = AppLaunchAuthorizationCoordinator(
            hasBookmark: { false },
            hasPromptedInitialAuthorization: { false },
            markInitialAuthorizationPrompted: { didMarkPrompted = true },
            loadAllStats: { didLoadAllStats = true },
            requestInitialAuthorization: {
                didRequestAuthorization = true
                return false
            }
        )

        await coordinator.performStartupWork()

        #expect(didRequestAuthorization)
        #expect(didMarkPrompted)
        #expect(didLoadAllStats)
    }

    @MainActor
    @Test func mainStoryboardUsesRoomierDefaultWindowSize() throws {
        let storyboard = NSStoryboard(name: "Main", bundle: Bundle.main)
        let windowController = try #require(storyboard.instantiateInitialController() as? NSWindowController)
        let contentSize = try #require(windowController.window?.contentView?.frame.size)

        #expect(contentSize == NSSize(width: 900, height: 640))
    }

    @MainActor
    @Test func mainWindowFactoryBuildsVisibleMainWindowShape() throws {
        let windowController = MainWindowFactory.makeWindowController(languageSettings: zhHansLanguageSettings())
        let window = try #require(windowController.window)
        defer { window.close() }

        #expect(window.title == "TokenWatch")
        #expect(window.styleMask.contains(.titled))
        #expect(window.styleMask.contains(.closable))
        #expect(window.styleMask.contains(.miniaturizable))
        #expect(window.styleMask.contains(.resizable))
        #expect(window.isReleasedWhenClosed == false)
        #expect(window.contentViewController is ViewController)
        #expect(window.contentView?.frame.size == MainWindowFactory.contentSize)
    }

    @MainActor
    @Test func mainWindowUsesNativeSidebarSplitLayout() throws {
        let viewController = ViewController(languageSettings: zhHansLanguageSettings())
        viewController.loadViewIfNeeded()

        let splitView = try #require(viewController.view.firstDescendant(ofType: NSSplitView.self))
        #expect(splitView.isVertical)
        #expect(splitView.arrangedSubviews.count == 2)
    }

    @MainActor
    @Test func sidebarListsAggregatePagesAndSettingsOnly() throws {
        let viewController = ViewController(languageSettings: zhHansLanguageSettings())
        viewController.loadViewIfNeeded()

        let sidebar = try #require(viewController.view.firstDescendant(ofType: NSTableView.self))
        #expect(sidebar.style == .sourceList)

        let displayedTitles = (0..<sidebar.numberOfRows).compactMap { row in
            (sidebar.view(atColumn: 0, row: row, makeIfNecessary: true) as? NSTableCellView)?
                .textField?
                .stringValue
        }
        #expect(displayedTitles == ["总计", "最近 12 个月", "最近 30 天", "本日", "设置"])
    }

    @MainActor
    @Test func sidebarRowsUseSFSymbolIcons() throws {
        let viewController = ViewController(languageSettings: zhHansLanguageSettings())
        viewController.loadViewIfNeeded()

        let sidebar = try #require(viewController.view.firstDescendant(ofType: NSTableView.self))
        let displayedIconIdentifiers = (0..<sidebar.numberOfRows).compactMap { row in
            let cell = sidebar.view(atColumn: 0, row: row, makeIfNecessary: true) as? NSTableCellView
            #expect(cell?.imageView?.image != nil)
            return cell?.imageView?.identifier?.rawValue
        }

        #expect(displayedIconIdentifiers == [
            "SidebarIcon.chart.bar.xaxis",
            "SidebarIcon.calendar",
            "SidebarIcon.clock",
            "SidebarIcon.sun.max",
            "SidebarIcon.gearshape",
        ])
    }

    @MainActor
    @Test func sidebarRowsExposeStableAccessibilityIdentifiers() throws {
        let viewController = ViewController(languageSettings: zhHansLanguageSettings())
        viewController.loadViewIfNeeded()

        let sidebar = try #require(viewController.view.firstDescendant(ofType: NSTableView.self))
        #expect(sidebar.accessibilityIdentifier() == "MainSidebarTableView")

        let cellIdentifiers = (0..<sidebar.numberOfRows).compactMap { row in
            (sidebar.view(atColumn: 0, row: row, makeIfNecessary: true) as? NSTableCellView)?
                .accessibilityIdentifier()
        }
        #expect(cellIdentifiers == [
            "SidebarRow.total",
            "SidebarRow.monthly",
            "SidebarRow.recent30Days",
            "SidebarRow.today",
            "SidebarRow.settings",
        ])
    }

    @MainActor
    @Test func initialSelectionShowsTotalStatsPage() throws {
        let viewController = ViewController(languageSettings: zhHansLanguageSettings())
        viewController.loadViewIfNeeded()

        let labels = viewController.view.allDescendants(ofType: NSTextField.self).map(\.stringValue)
        #expect(!labels.contains("总 token"))
        #expect(!labels.contains("总费用"))
        #expect(labels.contains("模型消耗"))
    }

    @MainActor
    @Test func selectingTotalShowsTotalStatsPage() throws {
        let viewController = ViewController(languageSettings: zhHansLanguageSettings())
        viewController.loadViewIfNeeded()

        let sidebar = try #require(viewController.view.firstDescendant(ofType: NSTableView.self))
        sidebar.selectRowIndexes(IndexSet(integer: sidebar.numberOfRows - 5), byExtendingSelection: false)

        let labels = viewController.view.allDescendants(ofType: NSTextField.self).map(\.stringValue)
        #expect(!labels.contains("总 token"))
        #expect(!labels.contains("总费用"))
        #expect(labels.contains("模型消耗"))
    }

    @MainActor
    @Test func selectingMonthlyShowsMonthlyChartPage() throws {
        let viewController = ViewController(languageSettings: zhHansLanguageSettings())
        viewController.loadViewIfNeeded()

        let sidebar = try #require(viewController.view.firstDescendant(ofType: NSTableView.self))
        sidebar.selectRowIndexes(IndexSet(integer: sidebar.numberOfRows - 4), byExtendingSelection: false)

        let labels = viewController.view.allDescendants(ofType: NSTextField.self).map(\.stringValue)
        #expect(labels.contains("最近 12 个月"))
        #expect(!labels.contains("最近 12 个月,跨 provider 汇总"))
        #expect(viewController.view.firstDescendant(ofType: MonthlyTokenChartView.self) != nil)
    }

    @MainActor
    @Test func selectingRecentThirtyDaysShowsDailyChartPage() throws {
        let viewController = ViewController(languageSettings: zhHansLanguageSettings())
        viewController.loadViewIfNeeded()

        let sidebar = try #require(viewController.view.firstDescendant(ofType: NSTableView.self))
        sidebar.selectRowIndexes(IndexSet(integer: sidebar.numberOfRows - 3), byExtendingSelection: false)

        let labels = viewController.view.allDescendants(ofType: NSTextField.self).map(\.stringValue)
        #expect(labels.contains("最近 30 天"))
        #expect(!labels.contains("最近 30 天,跨 provider 汇总"))
        #expect(viewController.view.firstDescendant(ofType: MonthlyTokenChartView.self) != nil)
    }

    @MainActor
    @Test func selectingTodayShowsTodayChartPage() throws {
        let viewController = ViewController(languageSettings: zhHansLanguageSettings())
        viewController.loadViewIfNeeded()

        let sidebar = try #require(viewController.view.firstDescendant(ofType: NSTableView.self))
        sidebar.selectRowIndexes(IndexSet(integer: sidebar.numberOfRows - 2), byExtendingSelection: false)

        let labels = viewController.view.allDescendants(ofType: NSTextField.self).map(\.stringValue)
        #expect(labels.contains("本日"))
        #expect(!labels.contains("本日,跨 provider 汇总"))
        #expect(viewController.view.firstDescendant(ofType: MonthlyTokenChartView.self) != nil)
    }

    @MainActor
    @Test func selectingSettingsShowsSettingsActions() throws {
        let viewController = ViewController(languageSettings: zhHansLanguageSettings())
        viewController.loadViewIfNeeded()

        let sidebar = try #require(viewController.view.firstDescendant(ofType: NSTableView.self))
        sidebar.selectRowIndexes(IndexSet(integer: sidebar.numberOfRows - 1), byExtendingSelection: false)

        let buttonTitles = viewController.view.allDescendants(ofType: NSButton.self).map(\.title)
        #expect(buttonTitles.contains("去授权") || buttonTitles.contains("已授权"))
        #expect(buttonTitles.contains("刷新全部数据"))
    }

    @MainActor
    @Test func mainMenuSettingsCommandShowsSettingsActions() throws {
        let viewController = ViewController(languageSettings: zhHansLanguageSettings())
        viewController.loadViewIfNeeded()

        viewController.showSettingsFromMainMenu(nil)

        let buttonTitles = viewController.view.allDescendants(ofType: NSButton.self).map(\.title)
        #expect(buttonTitles.contains("去授权") || buttonTitles.contains("已授权"))
        #expect(buttonTitles.contains("刷新全部数据"))
    }

    @MainActor
    @Test func settingsAuthorizationRowReflectsExistingAuthorization() throws {
        let settingsViewController = SettingsViewController(
            isAuthorized: { true },
            languageSettings: zhHansLanguageSettings()
        )
        settingsViewController.loadViewIfNeeded()

        let labels = settingsViewController.view.allDescendants(ofType: NSTextField.self).map(\.stringValue)
        #expect(labels.contains("通用访问权限"))

        let authorizedButton = try #require(settingsViewController.view.allDescendants(ofType: NSButton.self).first {
            $0.title == "已授权"
        })
        #expect(!authorizedButton.isEnabled)

        let buttonTitles = settingsViewController.view.allDescendants(ofType: NSButton.self).map(\.title)
        #expect(!buttonTitles.contains("去授权"))
    }

    @MainActor
    @Test func settingsAuthorizationRowUsesHorizontalSettingLayout() throws {
        let settingsViewController = SettingsViewController(
            isAuthorized: { false },
            languageSettings: zhHansLanguageSettings()
        )
        settingsViewController.loadViewIfNeeded()

        let permissionStack = try #require(settingsViewController.view.allDescendants(ofType: NSStackView.self).first { stack in
            let labels = stack.arrangedSubviews.compactMap { ($0 as? NSTextField)?.stringValue }
            let buttons = stack.arrangedSubviews.compactMap { ($0 as? NSButton)?.title }
            return labels.contains("通用访问权限") && buttons.contains("去授权")
        })
        #expect(permissionStack.orientation == .horizontal)

        let buttonTitles = settingsViewController.view.allDescendants(ofType: NSButton.self).map { $0.title }
        #expect(!buttonTitles.contains("已授权"))
    }

    @MainActor
    @Test func settingsShowsAutoRefreshIntervalMenu() throws {
        try withTemporaryDefaults { defaults in
            let settingsViewController = SettingsViewController(
                isAuthorized: { false },
                autoRefreshSettings: AutoRefreshSettings(defaults: defaults),
                languageSettings: zhHansLanguageSettings(defaults: defaults)
            )
            settingsViewController.loadViewIfNeeded()

            let labels = settingsViewController.view.allDescendants(ofType: NSTextField.self).map(\.stringValue)
            #expect(labels.contains("自动刷新间隔"))

            let popUpButton = try #require(settingsViewController.view.popUpButton(identifier: "AutoRefreshIntervalPopUpButton"))
            #expect(popUpButton.itemTitles == ["30 秒", "1 分钟", "5 分钟", "15 分钟", "关闭自动刷新"])
            #expect(popUpButton.titleOfSelectedItem == "30 秒")
        }
    }

    @MainActor
    @Test func settingsShowsLaunchAtLoginSwitch() throws {
        let loginItemSettings = FakeLoginItemSettings(isEnabled: true)
        let settingsViewController = SettingsViewController(
            isAuthorized: { false },
            loginItemSettings: loginItemSettings,
            languageSettings: zhHansLanguageSettings()
        )
        settingsViewController.loadViewIfNeeded()

        let labels = settingsViewController.view.allDescendants(ofType: NSTextField.self).map(\.stringValue)
        #expect(labels.contains("开机自启动"))

        let launchAtLoginSwitch = try #require(settingsViewController.view.switchControl(identifier: "LaunchAtLoginSwitch"))
        #expect(launchAtLoginSwitch.state == .on)
    }

    @MainActor
    @Test func togglingLaunchAtLoginSwitchUpdatesLoginItemSetting() throws {
        let loginItemSettings = FakeLoginItemSettings(isEnabled: false)
        let settingsViewController = SettingsViewController(
            isAuthorized: { false },
            loginItemSettings: loginItemSettings,
            languageSettings: zhHansLanguageSettings()
        )
        settingsViewController.loadViewIfNeeded()

        let launchAtLoginSwitch = try #require(settingsViewController.view.switchControl(identifier: "LaunchAtLoginSwitch"))
        launchAtLoginSwitch.state = .on
        _ = launchAtLoginSwitch.sendAction(launchAtLoginSwitch.action, to: launchAtLoginSwitch.target)
        #expect(loginItemSettings.requestedStates == [true])
        #expect(launchAtLoginSwitch.state == .on)

        launchAtLoginSwitch.state = .off
        _ = launchAtLoginSwitch.sendAction(launchAtLoginSwitch.action, to: launchAtLoginSwitch.target)
        #expect(loginItemSettings.requestedStates == [true, false])
        #expect(launchAtLoginSwitch.state == .off)
    }

    @MainActor
    @Test func failedLaunchAtLoginToggleRestoresActualState() throws {
        let loginItemSettings = FakeLoginItemSettings(isEnabled: false)
        loginItemSettings.errorToThrow = FakeLoginItemSettings.ToggleError.failed
        let settingsViewController = SettingsViewController(
            isAuthorized: { false },
            loginItemSettings: loginItemSettings,
            languageSettings: zhHansLanguageSettings()
        )
        settingsViewController.loadViewIfNeeded()

        let launchAtLoginSwitch = try #require(settingsViewController.view.switchControl(identifier: "LaunchAtLoginSwitch"))
        launchAtLoginSwitch.state = .on
        _ = launchAtLoginSwitch.sendAction(launchAtLoginSwitch.action, to: launchAtLoginSwitch.target)

        #expect(loginItemSettings.requestedStates == [true])
        #expect(launchAtLoginSwitch.state == .off)
    }

    @MainActor
    @Test func changingAutoRefreshIntervalPersistsSelection() throws {
        try withTemporaryDefaults { defaults in
            let settingsViewController = SettingsViewController(
                isAuthorized: { false },
                autoRefreshSettings: AutoRefreshSettings(defaults: defaults),
                languageSettings: zhHansLanguageSettings(defaults: defaults)
            )
            settingsViewController.loadViewIfNeeded()

            let popUpButton = try #require(settingsViewController.view.popUpButton(identifier: "AutoRefreshIntervalPopUpButton"))
            popUpButton.selectItem(withTitle: "5 分钟")
            _ = popUpButton.sendAction(popUpButton.action, to: popUpButton.target)

            #expect(defaults.string(forKey: "TokenWatch.autoRefreshInterval") == "minutes5")
        }
    }

    @MainActor
    @Test func settingsShowsLanguageMenu() throws {
        try withTemporaryDefaults { defaults in
            let languageSettings = AppLanguageSettings(defaults: defaults, preferredLanguagesProvider: { ["zh-Hans-US"] })
            let settingsViewController = SettingsViewController(
                isAuthorized: { false },
                autoRefreshSettings: AutoRefreshSettings(defaults: defaults),
                languageSettings: languageSettings
            )
            settingsViewController.loadViewIfNeeded()

            let popUpButton = try #require(settingsViewController.view.popUpButton(identifier: "LanguagePreferencePopUpButton"))
            #expect(popUpButton.itemTitles == [
                "跟随系统",
                "简体中文",
                "繁體中文",
                "English",
                "日本語",
                "한국어",
                "Español",
                "Deutsch",
                "Français",
                "Português (Brasil)",
                "Italiano",
                "Nederlands",
                "Polski",
            ])
            #expect(popUpButton.titleOfSelectedItem == "跟随系统")
        }
    }

    @MainActor
    @Test func settingsControlsExposeStableAccessibilityIdentifiers() throws {
        try withTemporaryDefaults { defaults in
            let settingsViewController = SettingsViewController(
                isAuthorized: { false },
                autoRefreshSettings: AutoRefreshSettings(defaults: defaults),
                languageSettings: zhHansLanguageSettings(defaults: defaults)
            )
            settingsViewController.loadViewIfNeeded()

            let buttons = settingsViewController.view.allDescendants(ofType: NSButton.self)
            #expect(buttons.first { $0.title == "去授权" }?.accessibilityIdentifier() == "AuthorizationActionButton")
            #expect(buttons.first { $0.title == "刷新全部数据" }?.accessibilityIdentifier() == "RefreshAllDataButton")

            let autoRefreshPopUp = try #require(settingsViewController.view.popUpButton(identifier: "AutoRefreshIntervalPopUpButton"))
            #expect(autoRefreshPopUp.accessibilityIdentifier() == "AutoRefreshIntervalPopUpButton")

            let launchAtLoginSwitch = try #require(settingsViewController.view.switchControl(identifier: "LaunchAtLoginSwitch"))
            #expect(launchAtLoginSwitch.accessibilityIdentifier() == "LaunchAtLoginSwitch")

            let languagePopUp = try #require(settingsViewController.view.popUpButton(identifier: "LanguagePreferencePopUpButton"))
            #expect(languagePopUp.accessibilityIdentifier() == "LanguagePreferencePopUpButton")
        }
    }

    @MainActor
    @Test func changingLanguagePersistsSelectionAndRefreshesSettingsLabels() throws {
        try withTemporaryDefaults { defaults in
            let languageSettings = AppLanguageSettings(defaults: defaults, preferredLanguagesProvider: { ["zh-Hans-US"] })
            let settingsViewController = SettingsViewController(
                isAuthorized: { false },
                autoRefreshSettings: AutoRefreshSettings(defaults: defaults),
                languageSettings: languageSettings
            )
            settingsViewController.loadViewIfNeeded()

            let popUpButton = try #require(settingsViewController.view.popUpButton(identifier: "LanguagePreferencePopUpButton"))
            popUpButton.selectItem(withTitle: "English")
            _ = popUpButton.sendAction(popUpButton.action, to: popUpButton.target)

            let labels = settingsViewController.view.allDescendants(ofType: NSTextField.self).map(\.stringValue)
            #expect(defaults.string(forKey: AppLanguageSettings.storageKey) == "en")
            #expect(labels.contains("Settings"))
            #expect(labels.contains("Language"))
            #expect(popUpButton.itemTitles == [
                "System",
                "简体中文",
                "繁體中文",
                "English",
                "日本語",
                "한국어",
                "Español",
                "Deutsch",
                "Français",
                "Português (Brasil)",
                "Italiano",
                "Nederlands",
                "Polski",
            ])
            #expect(popUpButton.titleOfSelectedItem == "English")
        }
    }

    @MainActor
    @Test func sidebarUsesEnglishTitlesWhenLanguageIsEnglish() throws {
        try withTemporaryDefaults { defaults in
            let languageSettings = AppLanguageSettings(defaults: defaults, preferredLanguagesProvider: { ["zh-Hans-US"] })
            languageSettings.selectedPreference = .en
            let viewController = ViewController(languageSettings: languageSettings)
            viewController.loadViewIfNeeded()

            let sidebar = try #require(viewController.view.firstDescendant(ofType: NSTableView.self))
            let displayedTitles = (0..<sidebar.numberOfRows).compactMap { row in
                (sidebar.view(atColumn: 0, row: row, makeIfNecessary: true) as? NSTableCellView)?
                    .textField?
                    .stringValue
            }

            #expect(displayedTitles == ["Total", "Last 12 Months", "Last 30 Days", "Today", "Settings"])
        }
    }
}

private extension NSView {
    func firstDescendant<T: NSView>(ofType type: T.Type) -> T? {
        if let match = self as? T {
            return match
        }
        for subview in subviews {
            if let match = subview.firstDescendant(ofType: type) {
                return match
            }
        }
        return nil
    }

    func allDescendants<T: NSView>(ofType type: T.Type) -> [T] {
        let current = (self as? T).map { [$0] } ?? []
        return current + subviews.flatMap { $0.allDescendants(ofType: type) }
    }

    func popUpButton(identifier: String) -> NSPopUpButton? {
        allDescendants(ofType: NSPopUpButton.self).first {
            $0.identifier?.rawValue == identifier
        }
    }

    func switchControl(identifier: String) -> NSSwitch? {
        allDescendants(ofType: NSSwitch.self).first {
            $0.identifier?.rawValue == identifier
        }
    }
}

@MainActor
private final class FakeLoginItemSettings: LoginItemSettingsControlling {
    enum ToggleError: Error {
        case failed
    }

    private(set) var requestedStates: [Bool] = []
    var errorToThrow: Error?
    var isEnabled: Bool

    init(isEnabled: Bool) {
        self.isEnabled = isEnabled
    }

    func setEnabled(_ enabled: Bool) throws {
        requestedStates.append(enabled)
        if let errorToThrow {
            throw errorToThrow
        }
        isEnabled = enabled
    }
}

private func withTemporaryDefaults(_ body: (UserDefaults) throws -> Void) rethrows {
    let suiteName = "TokenWatchTests.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suiteName)!
    defer { defaults.removePersistentDomain(forName: suiteName) }
    try body(defaults)
}

@MainActor
private func zhHansLanguageSettings(defaults: UserDefaults? = nil) -> AppLanguageSettings {
    let defaults = defaults ?? UserDefaults(suiteName: "TokenWatchTests.Language.\(UUID().uuidString)")!
    return AppLanguageSettings(defaults: defaults, preferredLanguagesProvider: { ["zh-Hans-US"] })
}
