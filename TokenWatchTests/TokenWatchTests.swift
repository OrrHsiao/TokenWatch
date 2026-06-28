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

        #expect(contentSize == NSSize(width: 1180, height: 760))
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
    @Test func mainWindowUsesPencilDashboardLayout() throws {
        let viewController = ViewController(languageSettings: zhHansLanguageSettings())
        viewController.loadViewIfNeeded()

        #expect(viewController.view.accessibilityIdentifier() == "DashboardRootView")
        #expect(viewController.view.firstDescendant(ofType: NSSplitView.self) == nil)
        #expect(viewController.view.firstDescendant(identifier: "DashboardSidebar") != nil)
        #expect(viewController.view.firstDescendant(identifier: "DashboardMainContent") != nil)
    }

    @MainActor
    @Test func dashboardSidebarMatchesPencilNavigation() throws {
        let viewController = ViewController(languageSettings: zhHansLanguageSettings())
        viewController.loadViewIfNeeded()

        let labels = viewController.view.allDescendants(ofType: NSTextField.self).map(\.stringValue)
        #expect(labels.contains("TokenWatch"))
        #expect(labels.contains("本地 AI 用量监控"))
        #expect(labels.contains("数据源"))
        #expect(labels.contains("上次本地扫描"))

        let navTitles: [String] = viewController.view.allDescendants(ofType: NSButton.self).compactMap { button -> String? in
            guard button.identifier?.rawValue.hasPrefix("DashboardNav.") == true else { return nil }
            return button.title
        }
        #expect(navTitles == ["总览", "时间线", "会话", "模型", "项目", "设置"])
    }

    @MainActor
    @Test func dashboardDataSourcesShowAuthorizationIndicatorsOnly() throws {
        let viewController = DashboardViewController(
            settingsViewController: SettingsViewController(languageSettings: zhHansLanguageSettings()),
            stateProvider: {
                [
                    .claude: .init(stats: nil, isLoading: false, errorMessage: nil, needsAuthorization: false),
                    .codex: .init(stats: nil, isLoading: true, errorMessage: nil, needsAuthorization: true),
                ]
            },
            refreshAction: {},
            languageSettings: zhHansLanguageSettings()
        )
        viewController.loadViewIfNeeded()
        viewController.view.setFrameSize(MainWindowFactory.contentSize)
        viewController.view.layoutSubtreeIfNeeded()

        let labels = viewController.view.allDescendants(ofType: NSTextField.self).map(\.stringValue)
        #expect(!labels.contains("已连接"))
        #expect(!labels.contains("待授权"))
        #expect(!labels.contains("刷新中"))

        let claudeIndicator = try #require(viewController.view.firstDescendant(identifier: "DashboardDataSourceStatus.claude"))
        let codexIndicator = try #require(viewController.view.firstDescendant(identifier: "DashboardDataSourceStatus.codex"))
        let openCodeIndicator = try #require(viewController.view.firstDescendant(identifier: "DashboardDataSourceStatus.opencode"))

        #expect(claudeIndicator.accessibilityValue() as? String == "authorized")
        #expect(codexIndicator.accessibilityValue() as? String == "unauthorized")
        #expect(openCodeIndicator.accessibilityValue() as? String == "unauthorized")
    }

    @MainActor
    @Test func dashboardHeaderMatchesPencilOverview() throws {
        let viewController = ViewController(languageSettings: zhHansLanguageSettings())
        viewController.loadViewIfNeeded()

        let labels = viewController.view.allDescendants(ofType: NSTextField.self).map(\.stringValue)
        #expect(labels.contains("用量总览"))
        #expect(labels.contains("汇总 Claude Code、Codex rollout 与 opencode SQLite 的本地记录"))

        let controlTitles: [String] = viewController.view.allDescendants(ofType: NSButton.self).compactMap { button -> String? in
            guard button.identifier?.rawValue.hasPrefix("DashboardRange.") == true
                || button.identifier?.rawValue == "DashboardRefreshButton" else { return nil }
            return button.title
        }
        #expect(controlTitles == ["当天", "7天", "30天", "全部", "刷新"])
    }

    @MainActor
    @Test func dashboardShowsPencilMetricCardsAndPanels() throws {
        let viewController = ViewController(languageSettings: zhHansLanguageSettings())
        viewController.loadViewIfNeeded()

        let labels = viewController.view.allDescendants(ofType: NSTextField.self).map(\.stringValue)
        #expect(labels.contains("总 Token"))
        #expect(labels.contains("总费用"))
        #expect(labels.contains("会话数"))
        #expect(labels.contains("每小时 Token 与缓存命中率"))
        #expect(labels.contains("模型消耗排行"))
        #expect(labels.contains("来源占比"))
        #expect(labels.contains("项目消耗"))
        #expect(labels.contains("最近明细"))
    }

    @MainActor
    @Test func dashboardTextUsesLeftAlignment() throws {
        let viewController = ViewController(languageSettings: zhHansLanguageSettings())
        viewController.loadViewIfNeeded()

        let labels = viewController.view
            .allDescendants(ofType: NSTextField.self)
            .filter { !$0.stringValue.isEmpty && $0.stringValue != "T" }

        #expect(!labels.isEmpty)
        #expect(labels.allSatisfy { $0.alignment == .left })
    }

    @MainActor
    @Test func dashboardSectionsStartAtLeadingEdges() throws {
        let viewController = ViewController(languageSettings: zhHansLanguageSettings())
        viewController.loadViewIfNeeded()
        viewController.view.setFrameSize(MainWindowFactory.contentSize)
        viewController.view.layoutSubtreeIfNeeded()

        let sidebar = try #require(viewController.view.firstDescendant(identifier: "DashboardSidebar"))
        let mainContent = try #require(viewController.view.firstDescendant(identifier: "DashboardMainContent"))
        let overviewTitle = try #require(viewController.view.textField(stringValue: "用量总览"))
        let overviewButton = try #require(viewController.view.button(identifier: "DashboardNav.overview"))

        let sidebarFrame = sidebar.convert(sidebar.bounds, to: viewController.view)
        let mainFrame = mainContent.convert(mainContent.bounds, to: viewController.view)
        let titleFrame = overviewTitle.convert(overviewTitle.bounds, to: viewController.view)
        let buttonFrame = overviewButton.convert(overviewButton.bounds, to: viewController.view)

        #expect(buttonFrame.minX <= sidebarFrame.minX + 28)
        #expect(titleFrame.minX <= mainFrame.minX + 48)
    }

    @MainActor
    @Test func dashboardNavigationItemsUsePencilIconSpacing() throws {
        let viewController = ViewController(languageSettings: zhHansLanguageSettings())
        viewController.loadViewIfNeeded()
        viewController.view.setFrameSize(MainWindowFactory.contentSize)
        viewController.view.layoutSubtreeIfNeeded()

        for item in ["overview", "timeline", "sessions", "models", "projects", "settings"] {
            let identifier = "DashboardNav.\(item)"
            let button = try #require(viewController.view.button(identifier: identifier))
            let icon = try #require(button.firstDescendant(identifier: "\(identifier).icon"))
            let title = try #require(button.firstDescendant(identifier: "\(identifier).title"))

            let iconFrame = icon.convert(icon.bounds, to: button)
            let titleFrame = title.convert(title.bounds, to: button)

            #expect(button.focusRingType == .none)
            #expect(iconFrame.minX >= 12)
            #expect(iconFrame.minX <= 16)
            #expect(titleFrame.minX - iconFrame.maxX >= 8)
            #expect(titleFrame.minX - iconFrame.maxX <= 12)
        }
    }

    @MainActor
    @Test func dashboardAnalysisPanelsStartAtLeadingEdge() throws {
        let viewController = ViewController(languageSettings: zhHansLanguageSettings())
        viewController.loadViewIfNeeded()
        viewController.view.setFrameSize(MainWindowFactory.contentSize)
        viewController.view.layoutSubtreeIfNeeded()

        let mainContent = try #require(viewController.view.firstDescendant(identifier: "DashboardMainContent"))
        let trendTitle = try #require(viewController.view.textField(stringValue: "每小时 Token 与缓存命中率"))

        let mainFrame = mainContent.convert(mainContent.bounds, to: viewController.view)
        let trendTitleFrame = trendTitle.convert(trendTitle.bounds, to: viewController.view)

        #expect(trendTitleFrame.minX <= mainFrame.minX + 64)
    }

    @MainActor
    @Test func dashboardRefreshButtonIsStableActionEntry() throws {
        let viewController = ViewController(languageSettings: zhHansLanguageSettings())
        viewController.loadViewIfNeeded()

        let refreshButton = try #require(viewController.view.button(identifier: "DashboardRefreshButton"))
        #expect(refreshButton.title == "刷新")
        #expect(refreshButton.action.map(NSStringFromSelector) == "refreshDashboard:")
        #expect(refreshButton.image != nil)
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
    @Test func dashboardKeepsPencilNavigationWhenLanguageIsEnglish() throws {
        try withTemporaryDefaults { defaults in
            let languageSettings = AppLanguageSettings(defaults: defaults, preferredLanguagesProvider: { ["zh-Hans-US"] })
            languageSettings.selectedPreference = .en
            let viewController = ViewController(languageSettings: languageSettings)
            viewController.loadViewIfNeeded()

            let navTitles: [String] = viewController.view.allDescendants(ofType: NSButton.self).compactMap { button -> String? in
                guard button.identifier?.rawValue.hasPrefix("DashboardNav.") == true else { return nil }
                return button.title
            }
            #expect(navTitles == ["总览", "时间线", "会话", "模型", "项目", "设置"])
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

    func firstDescendant(identifier: String) -> NSView? {
        if accessibilityIdentifier() == identifier || self.identifier?.rawValue == identifier {
            return self
        }
        for subview in subviews {
            if let match = subview.firstDescendant(identifier: identifier) {
                return match
            }
        }
        return nil
    }

    func button(identifier: String) -> NSButton? {
        allDescendants(ofType: NSButton.self).first {
            $0.identifier?.rawValue == identifier || $0.accessibilityIdentifier() == identifier
        }
    }

    func textField(stringValue: String) -> NSTextField? {
        allDescendants(ofType: NSTextField.self).first {
            $0.stringValue == stringValue
        }
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
