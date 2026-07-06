//
//  TokenWatchTests.swift
//  TokenWatchTests
//
//  Created by OrrHsiao on 2026/6/13.
//

import Testing
import AppKit
import SwiftUI
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

    @Test func appBundleDoesNotDeclareMainStoryboard() throws {
        let appBundle = try #require(Bundle.allBundles.first {
            $0.bundleURL.pathExtension == "app"
                && ($0.object(forInfoDictionaryKey: "CFBundleIdentifier") as? String) == "com.xiaoao.tokenwatch"
        })

        #expect(appBundle.object(forInfoDictionaryKey: "NSMainStoryboardFile") == nil)
        #expect(appBundle.url(forResource: "Main", withExtension: "storyboardc", subdirectory: "Base.lproj") == nil)
    }

    @MainActor
    @Test func applicationLaunchShowsMainWindowWithoutStoryboard() throws {
        let openWindowKey = "TokenWatch.openMainWindowOnLaunch"
        let promptedKey = "TokenWatch.didPromptInitialHomeAuthorization"
        let previousOpenWindowValue = UserDefaults.standard.object(forKey: openWindowKey)
        let previousPromptedValue = UserDefaults.standard.object(forKey: promptedKey)
        let previousDelegate = NSApp.delegate
        NSApp.windows
            .filter { $0.contentViewController is ViewController }
            .forEach { $0.close() }

        UserDefaults.standard.removeObject(forKey: openWindowKey)
        UserDefaults.standard.set(true, forKey: promptedKey)

        let delegate = AppDelegate(languageSettings: zhHansLanguageSettings())
        NSApp.delegate = delegate
        defer {
            delegate.applicationWillTerminate(Notification(name: NSApplication.willTerminateNotification, object: NSApp))
            NSApp.delegate = previousDelegate
            restoreUserDefaultsValue(previousOpenWindowValue, forKey: openWindowKey)
            restoreUserDefaultsValue(previousPromptedValue, forKey: promptedKey)
            NSApp.windows
                .filter { $0.contentViewController is ViewController }
                .forEach { $0.close() }
        }

        delegate.applicationDidFinishLaunching(Notification(name: NSApplication.didFinishLaunchingNotification, object: NSApp))

        let mainWindow = NSApp.windows.first {
            $0.contentViewController is ViewController && $0.isVisible
        }
        #expect(mainWindow != nil)
    }

    @MainActor
    @Test func mainWindowFactoryBuildsVisibleMainWindowShape() throws {
        let windowController = MainWindowFactory.makeWindowController(languageSettings: zhHansLanguageSettings())
        let window = try #require(windowController.window)
        defer { window.close() }

        #expect(window.title == "")
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

        let brandIcon = try #require(viewController.view.allDescendants(ofType: NSImageView.self).first {
            $0.identifier?.rawValue == "DashboardBrandIcon.AppLogo"
        })
        #expect(brandIcon.image != nil)
        #expect(brandIcon.image?.isTemplate == false)

        let navTitles: [String] = viewController.view.allDescendants(ofType: NSButton.self).compactMap { button -> String? in
            guard button.identifier?.rawValue.hasPrefix("DashboardNav.") == true else { return nil }
            return button.title
        }
        #expect(navTitles == ["总览", "会话", "设置"])
        #expect(viewController.view.button(identifier: "DashboardNav.timeline") == nil)
        #expect(viewController.view.button(identifier: "DashboardNav.models") == nil)
        #expect(viewController.view.button(identifier: "DashboardNav.projects") == nil)

        let privacyButton = try #require(viewController.view.button(identifier: "DashboardPrivacyPolicyButton"))
        #expect(privacyButton.title == "隐私政策")
        #expect(privacyButton.action.map(NSStringFromSelector) == "openPrivacyPolicy:")
    }

    @MainActor
    @Test func dashboardPrivacyPolicyEntryStaysAtSidebarBottom() throws {
        let viewController = ViewController(languageSettings: zhHansLanguageSettings())
        viewController.loadViewIfNeeded()
        viewController.view.setFrameSize(MainWindowFactory.contentSize)
        viewController.view.layoutSubtreeIfNeeded()

        let sidebar = try #require(viewController.view.firstDescendant(identifier: "DashboardSidebar"))
        let settingsButton = try #require(viewController.view.button(identifier: "DashboardNav.settings"))
        let privacyButton = try #require(viewController.view.button(identifier: "DashboardPrivacyPolicyButton"))

        let sidebarFrame = sidebar.convert(sidebar.bounds, to: viewController.view)
        let settingsFrame = settingsButton.convert(settingsButton.bounds, to: viewController.view)
        let privacyFrame = privacyButton.convert(privacyButton.bounds, to: viewController.view)

        #expect(privacyFrame.minY <= sidebarFrame.minY + 40)
        #expect(privacyFrame.maxY < settingsFrame.minY)
    }

    @MainActor
    @Test func dashboardDataSourcesShowAuthorizationIndicatorsAndHoverStatus() throws {
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

        let claudeRow = try #require(viewController.view.firstDescendant(identifier: "DashboardDataSourceRow.claude"))
        let codexRow = try #require(viewController.view.firstDescendant(identifier: "DashboardDataSourceRow.codex"))
        #expect(claudeRow.toolTip == "已授权")
        #expect(codexRow.toolTip == "未授权")
    }

    @MainActor
    @Test func dashboardScanStatusShowsRelativeLocalRefreshTime() throws {
        let now = Date(timeIntervalSince1970: 2_000_000)
        let viewController = DashboardViewController(
            settingsViewController: SettingsViewController(languageSettings: zhHansLanguageSettings()),
            stateProvider: {
                [
                    .claude: .init(
                        stats: nil,
                        isLoading: false,
                        errorMessage: nil,
                        needsAuthorization: false,
                        lastRefreshedAt: now.addingTimeInterval(-37 * 60)
                    ),
                ]
            },
            refreshAction: {},
            nowProvider: { now },
            languageSettings: zhHansLanguageSettings()
        )
        viewController.loadViewIfNeeded()

        let labels = viewController.view.allDescendants(ofType: NSTextField.self).map(\.stringValue)
        #expect(labels.contains("37 分钟前更新。不依赖任何网络 API。"))
        #expect(!labels.contains("本地记录已就绪。不依赖任何网络 API。"))
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
        #expect(controlTitles == ["当天", "7天", "30天", "全部", "立即刷新"])
    }

    @MainActor
    @Test func dashboardRangeControlsAreCenteredPaddedAndRightAligned() throws {
        let viewController = ViewController(languageSettings: zhHansLanguageSettings())
        viewController.loadViewIfNeeded()
        viewController.view.setFrameSize(MainWindowFactory.contentSize)
        viewController.view.layoutSubtreeIfNeeded()

        let mainContent = try #require(viewController.view.firstDescendant(identifier: "DashboardMainContent"))
        let controls = try #require(viewController.view.firstDescendant(identifier: "DashboardHeaderControls"))
        let controlButtons = viewController.view.allDescendants(ofType: NSButton.self).filter { button in
            button.identifier?.rawValue.hasPrefix("DashboardRange.") == true
                || button.identifier?.rawValue == "DashboardRefreshButton"
        }

        #expect(controlButtons.count == 5)
        #expect(controlButtons.allSatisfy { $0.alignment == .center })

        for button in controlButtons {
            let titleWidth = (button.title as NSString).size(withAttributes: [.font: button.font as Any]).width
            #expect(button.frame.width >= titleWidth + 24)
        }

        let mainFrame = mainContent.convert(mainContent.bounds, to: viewController.view)
        let controlsFrame = controls.convert(controls.bounds, to: viewController.view)
        #expect(abs(controlsFrame.maxX - (mainFrame.maxX - 28)) <= 1)
    }

    @MainActor
    @Test func dashboardRangeButtonsDoNotBecomeFirstResponderOnStartup() throws {
        let viewController = ViewController(languageSettings: zhHansLanguageSettings())
        viewController.loadViewIfNeeded()

        for range in ["day", "sevenDays", "month", "all"] {
            let button = try #require(viewController.view.button(identifier: "DashboardRange.\(range)"))
            #expect(!button.acceptsFirstResponder)
        }
    }

    @MainActor
    @Test func dashboardShowsPencilMetricCardsAndPanels() throws {
        let viewController = ViewController(languageSettings: zhHansLanguageSettings())
        viewController.loadViewIfNeeded()

        let labels = viewController.view.allDescendants(ofType: NSTextField.self).map(\.stringValue)
        #expect(labels.contains("总 Token"))
        #expect(labels.contains("总费用"))
        #expect(labels.contains("会话数"))
        #expect(labels.contains("趋势"))
        #expect(labels.contains("展示 Token 消耗与费用变化"))
        #expect(!labels.contains("Token 与缓存命中率趋势"))
        #expect(viewController.view.firstDescendant(identifier: "DashboardTrendLegend.token") != nil)
        #expect(viewController.view.firstDescendant(identifier: "DashboardTrendLegend.cost") != nil)
        #expect(labels.contains("模型消耗排行"))
        #expect(labels.contains("来源占比"))
        #expect(labels.contains("项目消耗"))
        #expect(!labels.contains("最近明细"))
    }

    @MainActor
    @Test func dashboardTotalCostDetailMatchesPencilCostBreakdown() throws {
        let calendar = utcCalendar()
        let now = dateTime(2026, 6, 20, hour: 14, minute: 30, calendar: calendar)
        let viewController = DashboardViewController(
            settingsViewController: SettingsViewController(languageSettings: zhHansLanguageSettings()),
            stateProvider: {
                [
                    .claude: .init(
                        stats: makeDashboardStats(
                            byDay: [
                                "2026-06-20": makeDashboardSummary(
                                    input: 500,
                                    output: 400,
                                    reasoning: 300,
                                    cost: 120
                                ),
                            ]
                        ),
                        isLoading: false,
                        errorMessage: nil,
                        needsAuthorization: false
                    ),
                ]
            },
            refreshAction: {},
            nowProvider: { now },
            calendar: calendar,
            languageSettings: zhHansLanguageSettings()
        )

        viewController.loadViewIfNeeded()

        let labels = viewController.view.allDescendants(ofType: NSTextField.self).map(\.stringValue)
        #expect(labels.contains("输入 $50.00 / 输出 $40.00 / 推理 $30.00"))
        #expect(!labels.contains { $0.contains("来源已载入") })
    }

    @MainActor
    @Test func dashboardTotalTokenDetailShowsAllTokenBuckets() throws {
        let calendar = utcCalendar()
        let now = dateTime(2026, 6, 20, hour: 14, minute: 30, calendar: calendar)
        let viewController = DashboardViewController(
            settingsViewController: SettingsViewController(languageSettings: zhHansLanguageSettings()),
            stateProvider: {
                [
                    .claude: .init(
                        stats: makeDashboardStats(
                            byDay: [
                                "2026-06-20": makeDashboardSummary(
                                    input: 500_000,
                                    output: 400_000,
                                    reasoning: 300_000,
                                    cacheRead: 600_000,
                                    cacheCreation: 100_000
                                ),
                            ]
                        ),
                        isLoading: false,
                        errorMessage: nil,
                        needsAuthorization: false
                    ),
                ]
            },
            refreshAction: {},
            nowProvider: { now },
            calendar: calendar,
            languageSettings: zhHansLanguageSettings()
        )

        viewController.loadViewIfNeeded()

        let labels = viewController.view.allDescendants(ofType: NSTextField.self).map(\.stringValue)
        #expect(labels.contains("1.9M"))
        #expect(labels.contains("输入 0.5M / 输出 0.4M / 缓存 0.7M（36.8%） / 推理 0.3M"))
        #expect(!labels.contains { $0.contains("缓存命中率") })
    }

    @MainActor
    @Test func dashboardZeroTokenDetailStillShowsCacheBucket() throws {
        let viewController = DashboardViewController(
            settingsViewController: SettingsViewController(languageSettings: zhHansLanguageSettings()),
            stateProvider: { [:] },
            refreshAction: {},
            languageSettings: zhHansLanguageSettings()
        )

        viewController.loadViewIfNeeded()

        let labels = viewController.view.allDescendants(ofType: NSTextField.self).map(\.stringValue)
        #expect(labels.contains("输入 0.0M / 输出 0.0M / 缓存 0.0M（0%）"))
    }

    @MainActor
    @Test func dashboardTrendLegendAlignsWithDescription() throws {
        let viewController = ViewController(languageSettings: zhHansLanguageSettings())
        viewController.loadViewIfNeeded()
        viewController.view.setFrameSize(MainWindowFactory.contentSize)
        viewController.view.layoutSubtreeIfNeeded()

        let description = try #require(viewController.view.textField(stringValue: "展示 Token 消耗与费用变化"))
        let tokenLegend = try #require(viewController.view.firstDescendant(identifier: "DashboardTrendLegend.token"))
        let costLegend = try #require(viewController.view.firstDescendant(identifier: "DashboardTrendLegend.cost"))

        let descriptionFrame = description.convert(description.bounds, to: viewController.view)
        let tokenLegendFrame = tokenLegend.convert(tokenLegend.bounds, to: viewController.view)
        let costLegendFrame = costLegend.convert(costLegend.bounds, to: viewController.view)

        #expect(tokenLegendFrame.width >= 74)
        #expect(tokenLegendFrame.height >= 12)
        #expect(costLegendFrame.width >= 34)
        #expect(costLegendFrame.height >= 12)
        #expect(abs(tokenLegendFrame.midY - descriptionFrame.midY) <= 1)
        #expect(abs(costLegendFrame.midY - descriptionFrame.midY) <= 1)
        #expect(costLegendFrame.minX > tokenLegendFrame.maxX)
    }

    @MainActor
    @Test func dashboardSourceLegendKeepsPositionAcrossRanges() throws {
        let calendar = utcCalendar()
        let now = dateTime(2026, 6, 20, hour: 14, minute: 30, calendar: calendar)
        let viewController = DashboardViewController(
            settingsViewController: SettingsViewController(languageSettings: zhHansLanguageSettings()),
            stateProvider: {
                [
                    .claude: .init(
                        stats: makeDashboardStats(
                            byDay: [
                                "2026-06-20": makeDashboardSummary(total: 1_000),
                            ]
                        ),
                        isLoading: false,
                        errorMessage: nil,
                        needsAuthorization: false
                    ),
                    .codex: .init(
                        stats: makeDashboardStats(
                            byDay: [
                                "2026-06-05": makeDashboardSummary(total: 800),
                            ]
                        ),
                        isLoading: false,
                        errorMessage: nil,
                        needsAuthorization: false
                    ),
                    .opencode: .init(
                        stats: makeDashboardStats(
                            byDay: [
                                "2026-06-02": makeDashboardSummary(total: 700),
                            ]
                        ),
                        isLoading: false,
                        errorMessage: nil,
                        needsAuthorization: false
                    ),
                ]
            },
            refreshAction: {},
            nowProvider: { now },
            calendar: calendar,
            languageSettings: zhHansLanguageSettings()
        )
        viewController.loadViewIfNeeded()
        viewController.view.setFrameSize(MainWindowFactory.contentSize)
        viewController.view.layoutSubtreeIfNeeded()

        let sevenDayLegend = try textField("Claude Code", inPanelTitled: "来源占比", root: viewController.view)
        let sevenDayValue = try textField("100.0%", inPanelTitled: "来源占比", root: viewController.view)
        let sevenDayTitleFrame = sevenDayLegend.convert(sevenDayLegend.bounds, to: viewController.view)
        let sevenDayValueFrame = sevenDayValue.convert(sevenDayValue.bounds, to: viewController.view)

        try clickDashboardRange("month", in: viewController)
        viewController.view.layoutSubtreeIfNeeded()

        let monthLegend = try textField("Claude Code", inPanelTitled: "来源占比", root: viewController.view)
        let monthValue = try textField("40.0%", inPanelTitled: "来源占比", root: viewController.view)
        let monthTitleFrame = monthLegend.convert(monthLegend.bounds, to: viewController.view)
        let monthValueFrame = monthValue.convert(monthValue.bounds, to: viewController.view)

        #expect(abs(monthTitleFrame.minX - sevenDayTitleFrame.minX) <= 1)
        #expect(abs(monthTitleFrame.maxY - sevenDayTitleFrame.maxY) <= 1)
        #expect(abs(monthValueFrame.maxX - sevenDayValueFrame.maxX) <= 1)
    }

    @MainActor
    @Test func dashboardTextUsesLeftAlignment() throws {
        let viewController = ViewController(languageSettings: zhHansLanguageSettings())
        viewController.loadViewIfNeeded()

        let labels = viewController.view
            .allDescendants(ofType: NSTextField.self)
            .filter { !$0.stringValue.isEmpty }

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

        for item in ["overview", "sessions", "settings"] {
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
    @Test func dashboardSessionsNavigationShowsPencilSessionDetailsPage() throws {
        let appearance = try #require(NSAppearance(named: .aqua))
        let viewController = ViewController(languageSettings: zhHansLanguageSettings())
        appearance.performAsCurrentDrawingAppearance {
            viewController.loadViewIfNeeded()
        }

        let sessionsButton = try #require(viewController.view.button(identifier: "DashboardNav.sessions"))
        appearance.performAsCurrentDrawingAppearance {
            _ = sessionsButton.sendAction(sessionsButton.action, to: sessionsButton.target)
        }

        let labels = viewController.view.allDescendants(ofType: NSTextField.self).map(\.stringValue)
        #expect(labels.contains("会话"))
        #expect(labels.contains("按最近时间倒序查看会话聚合、成本与使用记录"))
        #expect(labels.contains("最近时间 ↓"))
        #expect(labels.contains("会话 ID"))
        #expect(labels.contains("主模型"))
        #expect(labels.contains("记录数"))
        #expect(!labels.contains("用量总览"))
        #expect(!labels.contains("趋势"))
        #expect(viewController.view.button(identifier: "DashboardRange.sevenDays") == nil)
        #expect(viewController.view.button(identifier: "DashboardRefreshButton") == nil)
        #expect(viewController.view.firstDescendant(identifier: "DashboardSessionsPage") != nil)
        #expect(viewController.view.firstDescendant(identifier: "DashboardSessionsTable") != nil)
    }

    @MainActor
    @Test func dashboardSessionsPageRendersSelectedDaySessionRowsAndSummaries() throws {
        let calendar = utcCalendar()
        let now = dateTime(2026, 6, 20, hour: 14, minute: 30, calendar: calendar)
        let recentEntry = makeDashboardEntry(
            sessionID: "session-recent",
            date: dateTime(2026, 6, 20, hour: 10, minute: 0, calendar: calendar),
            model: "model-recent",
            input: 700,
            cwd: "/work/recent-app"
        )
        let olderEntry = makeDashboardEntry(
            sessionID: "session-older",
            date: dateTime(2026, 6, 19, hour: 9, minute: 0, calendar: calendar),
            model: "model-older",
            input: 500,
            cwd: "/work/older-app"
        )
        let outOfRangeEntry = makeDashboardEntry(
            sessionID: "session-out-of-range",
            date: dateTime(2026, 6, 1, hour: 9, minute: 0, calendar: calendar),
            model: "model-legacy",
            input: 9_000,
            cwd: "/work/legacy-app"
        )
        let entries = [recentEntry, olderEntry, outOfRangeEntry]
        let stats = UsageAggregator().aggregate(entries)
        let viewController = DashboardViewController(
            settingsViewController: SettingsViewController(languageSettings: zhHansLanguageSettings()),
            stateProvider: {
                [.claude: .init(
                    stats: stats,
                    entries: entries,
                    isLoading: false,
                    errorMessage: nil,
                    needsAuthorization: false
                )]
            },
            refreshAction: {},
            nowProvider: { now },
            calendar: calendar,
            languageSettings: zhHansLanguageSettings()
        )
        viewController.loadViewIfNeeded()

        let sessionsButton = try #require(viewController.view.button(identifier: "DashboardNav.sessions"))
        _ = sessionsButton.sendAction(sessionsButton.action, to: sessionsButton.target)

        let labels = try labels(inContainer: "DashboardSessionsPage", root: viewController.view)
        #expect(labels.contains("显示 1-1 / 共 1 个会话"))
        #expect(labels.contains("700"))
        #expect(labels.contains("$0.00"))
        #expect(labels.contains("session-recent"))
        #expect(!labels.contains("session-older"))
        #expect(!labels.contains("session-out-of-range"))
        #expect(labels.contains("recent-app"))
        #expect(!labels.contains("older-app"))
        #expect(labels.contains("Claude Code"))
    }

    @MainActor
    @Test func dashboardSessionsPageUsesPencilLightAndDarkColors() throws {
        let aqua = try #require(NSAppearance(named: .aqua))
        let lightController = ViewController(languageSettings: zhHansLanguageSettings())
        aqua.performAsCurrentDrawingAppearance {
            lightController.loadViewIfNeeded()
        }
        let lightSessionsButton = try #require(lightController.view.button(identifier: "DashboardNav.sessions"))
        aqua.performAsCurrentDrawingAppearance {
            _ = lightSessionsButton.sendAction(lightSessionsButton.action, to: lightSessionsButton.target)
        }

        let lightTable = try #require(lightController.view.firstDescendant(identifier: "DashboardSessionsTable"))
        let lightHeader = try #require(lightController.view.firstDescendant(identifier: "DashboardSessionsTableHeader"))
        let lightRow = try #require(lightController.view.firstDescendant(identifier: "DashboardSessionsRow.0"))
        #expect(rgbHex(try #require(lightTable.layer?.backgroundColor)) == 0xFFFFFF)
        #expect(rgbHex(try #require(lightHeader.layer?.backgroundColor)) == 0xF1F5F9)
        #expect(rgbHex(try #require(lightRow.layer?.backgroundColor)) == 0xFFFFFF)

        let dark = try #require(NSAppearance(named: .darkAqua))
        let darkController = ViewController(languageSettings: zhHansLanguageSettings())
        dark.performAsCurrentDrawingAppearance {
            darkController.loadViewIfNeeded()
        }
        let darkSessionsButton = try #require(darkController.view.button(identifier: "DashboardNav.sessions"))
        dark.performAsCurrentDrawingAppearance {
            _ = darkSessionsButton.sendAction(darkSessionsButton.action, to: darkSessionsButton.target)
        }

        let darkTable = try #require(darkController.view.firstDescendant(identifier: "DashboardSessionsTable"))
        let darkHeader = try #require(darkController.view.firstDescendant(identifier: "DashboardSessionsTableHeader"))
        let darkRow = try #require(darkController.view.firstDescendant(identifier: "DashboardSessionsRow.0"))
        #expect(rgbHex(try #require(darkTable.layer?.backgroundColor)) == 0x151B23)
        #expect(rgbHex(try #require(darkHeader.layer?.backgroundColor)) == 0x202936)
        #expect(rgbHex(try #require(darkRow.layer?.backgroundColor)) == 0x151B23)
    }

    @MainActor
    @Test func dashboardSessionsPageUsesPencilLightDetailColors() throws {
        let calendar = utcCalendar()
        let now = dateTime(2026, 6, 20, hour: 14, minute: 30, calendar: calendar)
        let entry = makeDashboardEntry(
            sessionID: "session-recent",
            date: dateTime(2026, 6, 20, hour: 10, minute: 0, calendar: calendar),
            model: "model-recent",
            input: 700,
            cwd: "/work/recent-app"
        )
        let stats = UsageAggregator().aggregate([entry])
        let appearance = try #require(NSAppearance(named: .aqua))
        let viewController = DashboardViewController(
            settingsViewController: SettingsViewController(languageSettings: zhHansLanguageSettings()),
            stateProvider: {
                [.claude: .init(
                    stats: stats,
                    entries: [entry],
                    isLoading: false,
                    errorMessage: nil,
                    needsAuthorization: false
                )]
            },
            refreshAction: {},
            nowProvider: { now },
            calendar: calendar,
            languageSettings: zhHansLanguageSettings()
        )
        appearance.performAsCurrentDrawingAppearance {
            viewController.loadViewIfNeeded()
        }

        let sessionsButton = try #require(viewController.view.button(identifier: "DashboardNav.sessions"))
        appearance.performAsCurrentDrawingAppearance {
            _ = sessionsButton.sendAction(sessionsButton.action, to: sessionsButton.target)
        }

        let dateBadge = try #require(viewController.view.firstDescendant(identifier: "DashboardSessionsDateBadge"))
        let sessionMetricCard = try roundedAncestor(containingText: "会话数", root: viewController.view)
        let table = try #require(viewController.view.firstDescendant(identifier: "DashboardSessionsTable"))
        let pagination = try #require(viewController.view.firstDescendant(identifier: "DashboardSessionsPagination"))
        let row = try #require(viewController.view.firstDescendant(identifier: "DashboardSessionsRow.0"))
        let providerBadge = try #require(row.firstDescendant(identifier: "DashboardSessionsProviderBadge.claude"))
        let copyButton = try #require(row.button(identifier: "DashboardSessionsCopy.0"))
        let modelLabel = try #require(row.textField(stringValue: "model-recent"))
        let costLabel = try #require(row.textField(stringValue: "$0.00"))

        #expect(rgbHex(try #require(dateBadge.layer?.backgroundColor)) == 0xFFFFFF)
        #expect(rgbHex(try #require(dateBadge.layer?.borderColor)) == 0xD8DEE8)
        #expect(rgbHex(try #require(sessionMetricCard.layer?.backgroundColor)) == 0xFFFFFF)
        #expect(rgbHex(try #require(sessionMetricCard.layer?.borderColor)) == 0xD8DEE8)
        #expect(rgbHex(try #require(table.layer?.borderColor)) == 0xD8DEE8)
        #expect(rgbHex(try #require(pagination.layer?.backgroundColor)) == 0xF4F6FA)
        #expect(rgbHex(try #require(providerBadge.layer?.backgroundColor)) == 0xEAF2FF)
        #expect(try rgbHex(try #require(copyButton.contentTintColor), appearance: .aqua) == 0x111827)
        #expect(try rgbHex(try #require(modelLabel.textColor), appearance: .aqua) == 0x6B7280)
        #expect(try rgbHex(try #require(costLabel.textColor), appearance: .aqua) == 0x6B7280)
    }

    @MainActor
    @Test func dashboardLayerColorsReapplyPencilLightColorsAfterAppearanceChangesToAqua() throws {
        let dark = try #require(NSAppearance(named: .darkAqua))
        let aqua = try #require(NSAppearance(named: .aqua))
        let viewController = ViewController(languageSettings: zhHansLanguageSettings())
        dark.performAsCurrentDrawingAppearance {
            viewController.loadViewIfNeeded()
        }
        let sessionsButton = try #require(viewController.view.button(identifier: "DashboardNav.sessions"))
        dark.performAsCurrentDrawingAppearance {
            _ = sessionsButton.sendAction(sessionsButton.action, to: sessionsButton.target)
        }

        viewController.view.appearance = aqua
        refreshEffectiveAppearance(in: viewController.view)

        let root = viewController.view
        let sidebar = try #require(root.firstDescendant(identifier: "DashboardSidebar"))
        let mainContent = try #require(root.firstDescendant(identifier: "DashboardMainContent"))
        let overviewButton = try #require(root.button(identifier: "DashboardNav.overview"))
        let table = try #require(root.firstDescendant(identifier: "DashboardSessionsTable"))
        let tableHeader = try #require(root.firstDescendant(identifier: "DashboardSessionsTableHeader"))
        let tableRow = try #require(root.firstDescendant(identifier: "DashboardSessionsRow.0"))
        let paginationButton = try #require(root.button(identifier: "DashboardSessionsPagination.page.1"))

        #expect(rgbHex(try #require(root.layer?.backgroundColor)) == 0xF4F6FA)
        #expect(rgbHex(try #require(sidebar.layer?.backgroundColor)) == 0xFFFFFF)
        #expect(rgbHex(try #require(mainContent.layer?.backgroundColor)) == 0xF4F6FA)
        #expect(rgbHex(try #require(sessionsButton.layer?.backgroundColor)) == 0xEAF2FF)
        #expect(rgbHex(try #require(overviewButton.layer?.backgroundColor)) == 0xFFFFFF)
        #expect(rgbHex(try #require(table.layer?.backgroundColor)) == 0xFFFFFF)
        #expect(rgbHex(try #require(tableHeader.layer?.backgroundColor)) == 0xF1F5F9)
        #expect(rgbHex(try #require(tableRow.layer?.backgroundColor)) == 0xFFFFFF)
        #expect(rgbHex(try #require(paginationButton.layer?.backgroundColor)) == 0x2563EB)
        #expect(rgbHex(try #require(paginationButton.layer?.borderColor)) == 0x2563EB)
    }

    @MainActor
    @Test func dashboardSessionsPageReappliesLightColorsWhenOpenedAfterAppearanceOverride() throws {
        let dark = try #require(NSAppearance(named: .darkAqua))
        let aqua = try #require(NSAppearance(named: .aqua))
        let viewController = ViewController(languageSettings: zhHansLanguageSettings())
        dark.performAsCurrentDrawingAppearance {
            viewController.loadViewIfNeeded()
        }

        viewController.view.appearance = aqua
        refreshEffectiveAppearance(in: viewController.view)

        let sessionsButton = try #require(viewController.view.button(identifier: "DashboardNav.sessions"))
        dark.performAsCurrentDrawingAppearance {
            _ = sessionsButton.sendAction(sessionsButton.action, to: sessionsButton.target)
        }

        let table = try #require(viewController.view.firstDescendant(identifier: "DashboardSessionsTable"))
        let tableHeader = try #require(viewController.view.firstDescendant(identifier: "DashboardSessionsTableHeader"))
        let tableRow = try #require(viewController.view.firstDescendant(identifier: "DashboardSessionsRow.0"))
        let dateBadge = try #require(viewController.view.firstDescendant(identifier: "DashboardSessionsDateBadge"))
        let pagination = try #require(viewController.view.firstDescendant(identifier: "DashboardSessionsPagination"))
        let previousButton = try #require(viewController.view.button(identifier: "DashboardSessionsPagination.previous"))
        let selectedPageButton = try #require(viewController.view.button(identifier: "DashboardSessionsPagination.page.1"))
        let nextButton = try #require(viewController.view.button(identifier: "DashboardSessionsPagination.next"))
        let previousTitleLabel = try #require(previousButton.textField(stringValue: "上一页"))
        let nextTitleLabel = try #require(nextButton.textField(stringValue: "下一页"))

        #expect(rgbHex(try #require(table.layer?.backgroundColor)) == 0xFFFFFF)
        #expect(rgbHex(try #require(table.layer?.borderColor)) == 0xD8DEE8)
        #expect(rgbHex(try #require(tableHeader.layer?.backgroundColor)) == 0xF1F5F9)
        #expect(rgbHex(try #require(tableRow.layer?.backgroundColor)) == 0xFFFFFF)
        #expect(rgbHex(try #require(dateBadge.layer?.backgroundColor)) == 0xFFFFFF)
        #expect(rgbHex(try #require(dateBadge.layer?.borderColor)) == 0xD8DEE8)
        #expect(rgbHex(try #require(pagination.layer?.backgroundColor)) == 0xF4F6FA)
        #expect(rgbHex(try #require(previousButton.layer?.backgroundColor)) == 0xFFFFFF)
        #expect(rgbHex(try #require(previousButton.layer?.borderColor)) == 0xD8DEE8)
        #expect(rgbHex(try #require(selectedPageButton.layer?.backgroundColor)) == 0x2563EB)
        #expect(rgbHex(try #require(nextButton.layer?.backgroundColor)) == 0xFFFFFF)
        #expect(rgbHex(try #require(nextButton.layer?.borderColor)) == 0xD8DEE8)
        #expect(try rgbHex(try #require(previousTitleLabel.textColor), appearance: .aqua) == 0x6B7280)
        #expect(try rgbHex(try #require(nextTitleLabel.textColor), appearance: .aqua) == 0x6B7280)
    }

    @MainActor
    @Test func dashboardSessionRowsUseLightTextWhenOpenedAfterAppearanceOverride() throws {
        let calendar = utcCalendar()
        let dark = try #require(NSAppearance(named: .darkAqua))
        let aqua = try #require(NSAppearance(named: .aqua))
        let entry = makeDashboardEntry(
            sessionID: "session-light-row",
            date: dateTime(2026, 6, 20, hour: 10, minute: 0, calendar: calendar),
            model: "model-light-row",
            input: 700,
            cwd: "/work/light-row"
        )
        let stats = UsageAggregator().aggregate([entry])
        let viewController = DashboardViewController(
            settingsViewController: SettingsViewController(languageSettings: zhHansLanguageSettings()),
            stateProvider: {
                [.claude: .init(
                    stats: stats,
                    entries: [entry],
                    isLoading: false,
                    errorMessage: nil,
                    needsAuthorization: false
                )]
            },
            refreshAction: {},
            nowProvider: { dateTime(2026, 6, 20, hour: 14, minute: 30, calendar: calendar) },
            calendar: calendar,
            languageSettings: zhHansLanguageSettings()
        )
        dark.performAsCurrentDrawingAppearance {
            viewController.loadViewIfNeeded()
        }

        viewController.view.appearance = aqua
        refreshEffectiveAppearance(in: viewController.view)

        let sessionsButton = try #require(viewController.view.button(identifier: "DashboardNav.sessions"))
        dark.performAsCurrentDrawingAppearance {
            _ = sessionsButton.sendAction(sessionsButton.action, to: sessionsButton.target)
        }

        let row = try #require(viewController.view.firstDescendant(identifier: "DashboardSessionsRow.0"))
        let copyButton = try #require(row.button(identifier: "DashboardSessionsCopy.0"))
        let copyButtonBackgroundColor = try #require(copyButton.layer?.backgroundColor)
        let copyButtonTitleLabel = try #require(copyButton.textField(stringValue: "session-light-row"))

        #expect(rgbHex(try #require(row.layer?.backgroundColor)) == 0xFFFFFF)
        #expect(alphaValue(copyButtonBackgroundColor) == 0)
        #expect(try rgbHex(try #require(copyButton.contentTintColor), appearance: .aqua) == 0x111827)
        #expect(try rgbHex(try #require(copyButtonTitleLabel.textColor), appearance: .aqua) == 0x111827)
    }

    @MainActor
    @Test func dashboardSessionDataRowsUseCompactItemHeight() throws {
        let calendar = utcCalendar()
        let entry = makeDashboardEntry(
            sessionID: "session-compact-row",
            date: dateTime(2026, 6, 20, hour: 10, minute: 0, calendar: calendar),
            model: "model-compact-row",
            input: 700,
            cwd: "/work/compact-row"
        )
        let stats = UsageAggregator().aggregate([entry])
        let viewController = DashboardViewController(
            settingsViewController: SettingsViewController(languageSettings: zhHansLanguageSettings()),
            stateProvider: {
                [.claude: .init(
                    stats: stats,
                    entries: [entry],
                    isLoading: false,
                    errorMessage: nil,
                    needsAuthorization: false
                )]
            },
            refreshAction: {},
            nowProvider: { dateTime(2026, 6, 20, hour: 14, minute: 30, calendar: calendar) },
            calendar: calendar,
            languageSettings: zhHansLanguageSettings()
        )
        viewController.loadViewIfNeeded()

        let sessionsButton = try #require(viewController.view.button(identifier: "DashboardNav.sessions"))
        _ = sessionsButton.sendAction(sessionsButton.action, to: sessionsButton.target)

        let row = try #require(viewController.view.firstDescendant(identifier: "DashboardSessionsRow.0"))

        #expect(row.fixedHeightConstant == 48)
    }

    @MainActor
    @Test func settingsPageReappliesLightColorsWhenOpenedAfterAppearanceOverride() throws {
        let dark = try #require(NSAppearance(named: .darkAqua))
        let aqua = try #require(NSAppearance(named: .aqua))
        let viewController = ViewController(languageSettings: zhHansLanguageSettings())
        dark.performAsCurrentDrawingAppearance {
            viewController.loadViewIfNeeded()
        }

        viewController.view.appearance = aqua
        refreshEffectiveAppearance(in: viewController.view)

        let settingsButton = try #require(viewController.view.button(identifier: "DashboardNav.settings"))
        dark.performAsCurrentDrawingAppearance {
            _ = settingsButton.sendAction(settingsButton.action, to: settingsButton.target)
        }

        let settingsPanel = try #require(viewController.view.firstDescendant(identifier: "SettingsPanel"))
        let authorizeButton = try #require(viewController.view.button(identifier: "AuthorizationActionButton"))
        let refreshButton = try #require(viewController.view.button(identifier: "RefreshAllDataButton"))
        let autoRefreshPopUp = try #require(viewController.view.popUpButton(identifier: "AutoRefreshIntervalPopUpButton"))
        let languagePopUp = try #require(viewController.view.popUpButton(identifier: "LanguagePreferencePopUpButton"))

        #expect(rgbHex(try #require(settingsPanel.layer?.backgroundColor)) == 0xFFFFFF)
        #expect(rgbHex(try #require(settingsPanel.layer?.borderColor)) == 0xD8DEE8)
        #expect(rgbHex(try #require(authorizeButton.layer?.backgroundColor)) == 0x2563EB)
        #expect(rgbHex(try #require(authorizeButton.layer?.borderColor)) == 0x2563EB)
        #expect(rgbHex(try #require(refreshButton.layer?.backgroundColor)) == 0xFFFFFF)
        #expect(rgbHex(try #require(refreshButton.layer?.borderColor)) == 0xD8DEE8)
        #expect(rgbHex(try #require(autoRefreshPopUp.layer?.backgroundColor)) == 0xFFFFFF)
        #expect(rgbHex(try #require(autoRefreshPopUp.layer?.borderColor)) == 0xD8DEE8)
        #expect(rgbHex(try #require(languagePopUp.layer?.backgroundColor)) == 0xFFFFFF)
        #expect(rgbHex(try #require(languagePopUp.layer?.borderColor)) == 0xD8DEE8)
    }

    @MainActor
    @Test func dashboardTabSwitchDoesNotManuallyInvokeAppKitAppearanceCallbacksOnArbitrarySubviews() throws {
        let aqua = try #require(NSAppearance(named: .aqua))
        let viewController = ViewController(languageSettings: zhHansLanguageSettings())
        viewController.view.appearance = aqua
        viewController.loadViewIfNeeded()

        let sessionsButton = try #require(viewController.view.button(identifier: "DashboardNav.sessions"))
        _ = sessionsButton.sendAction(sessionsButton.action, to: sessionsButton.target)

        let sessionPage = try #require(viewController.view.firstDescendant(identifier: "DashboardSessionsPage"))
        let sentinel = AppearanceCallbackSentinelView()
        sessionPage.addSubview(sentinel)

        let overviewButton = try #require(viewController.view.button(identifier: "DashboardNav.overview"))
        _ = overviewButton.sendAction(overviewButton.action, to: overviewButton.target)
        sentinel.appearanceCallbackCount = 0

        _ = sessionsButton.sendAction(sessionsButton.action, to: sessionsButton.target)

        #expect(sentinel.appearanceCallbackCount == 0)
    }

    @MainActor
    @Test func dashboardRefreshStillInvokesActionAfterAppearanceOverrideAndTabSwitch() async throws {
        let dark = try #require(NSAppearance(named: .darkAqua))
        let aqua = try #require(NSAppearance(named: .aqua))
        var refreshCount = 0
        let viewController = DashboardViewController(
            settingsViewController: SettingsViewController(languageSettings: zhHansLanguageSettings()),
            stateProvider: { [:] },
            refreshAction: { refreshCount += 1 },
            languageSettings: zhHansLanguageSettings()
        )
        dark.performAsCurrentDrawingAppearance {
            viewController.loadViewIfNeeded()
        }

        viewController.view.appearance = aqua
        refreshEffectiveAppearance(in: viewController.view)
        try clickDashboardNavigation("sessions", in: viewController)
        try clickDashboardNavigation("overview", in: viewController)

        let refreshButton = try #require(viewController.view.button(identifier: "DashboardRefreshButton"))
        dark.performAsCurrentDrawingAppearance {
            _ = refreshButton.sendAction(refreshButton.action, to: refreshButton.target)
        }
        try await Task.sleep(nanoseconds: 50_000_000)

        #expect(refreshCount == 1)
    }

    @MainActor
    @Test func dashboardAnalysisPanelsStartAtLeadingEdge() throws {
        let viewController = ViewController(languageSettings: zhHansLanguageSettings())
        viewController.loadViewIfNeeded()
        viewController.view.setFrameSize(MainWindowFactory.contentSize)
        viewController.view.layoutSubtreeIfNeeded()

        let mainContent = try #require(viewController.view.firstDescendant(identifier: "DashboardMainContent"))
        let trendTitle = try #require(viewController.view.textField(stringValue: "趋势"))

        let mainFrame = mainContent.convert(mainContent.bounds, to: viewController.view)
        let trendTitleFrame = trendTitle.convert(trendTitle.bounds, to: viewController.view)

        #expect(trendTitleFrame.minX <= mainFrame.minX + 64)
    }

    @MainActor
    @Test func dashboardTrendUsesStatusBarLineChartStyle() throws {
        let viewController = ViewController(languageSettings: zhHansLanguageSettings())
        viewController.loadViewIfNeeded()

        let trendView = try #require(viewController.view.firstDescendant(ofType: DashboardTrendView.self))
        #expect(trendView.debugLineInterpolationMethodName == "catmullRom")
        #expect(trendView.debugAreaGradientScaleModeName == "dailyMaximum")
        #expect(trendView.debugAreaStackingModeName == "unstacked")
        #expect(trendView.debugAreaLayerOrder == ["Token", "Cost"])
        #expect(trendView.debugTrendSeriesKeys == ["Token", "Cost"])
        #expect(trendView.debugChartLegendVisibilityName == "hidden")
        #expect(trendView.debugTrendLegendPlacementName == "subtitleHeaderTrailing")
        #expect(trendView.debugTrendLegendTitles == ["Token 消耗", "费用"])
        #expect(trendView.debugCostLineDashPattern.isEmpty)
        #expect(trendView.debugCostYAxisPositionName == "trailing")
        #expect(trendView.debugCostPlotY(forNormalizedCostHeight: 1, maxTokens: 100) == 120)
        #expect(trendView.debugChartYScaleUpperBound(maxTokens: 100) == 120)
        #expect(trendView.debugCostYAxisLabel(forScaledValue: 120, maxTokens: 100, maxCost: 12.5) == "$13")
        #expect(trendView.debugCostYAxisLabel(forScaledValue: 60, maxTokens: 100, maxCost: 12.5) == "$6")
        #expect(trendView.debugTokenAreaGradientLightRGBAComponents == [0.145, 0.388, 0.922, 1.0])
        #expect(trendView.debugCostAreaGradientLightRGBAComponents == [0.086, 0.639, 0.29, 1.0])
        #expect(trendView.allDescendants(ofType: NSHostingView<AnyView>.self).count == 1)
    }

    @MainActor
    @Test func dashboardPaletteUsesPencilLightColorsInAquaAppearance() throws {
        #expect(try rgbHex(DashboardPalette.appBackground, appearance: .aqua) == 0xF4F6FA)
        #expect(try rgbHex(DashboardPalette.sidebarBackground, appearance: .aqua) == 0xFFFFFF)
        #expect(try rgbHex(DashboardPalette.panelBackground, appearance: .aqua) == 0xFFFFFF)
        #expect(try rgbHex(DashboardPalette.deepPanelBackground, appearance: .aqua) == 0xFFFFFF)
        #expect(try rgbHex(DashboardPalette.scanCardBackground, appearance: .aqua) == 0xF8FAFC)
        #expect(try rgbHex(DashboardPalette.border, appearance: .aqua) == 0xD8DEE8)
        #expect(try rgbHex(DashboardPalette.primaryText, appearance: .aqua) == 0x111827)
        #expect(try rgbHex(DashboardPalette.secondaryText, appearance: .aqua) == 0x6B7280)
        #expect(try rgbHex(DashboardPalette.mutedText, appearance: .aqua) == 0x94A3B8)
        #expect(try rgbHex(DashboardPalette.accent, appearance: .aqua) == 0x2563EB)
        #expect(try rgbHex(DashboardPalette.green, appearance: .aqua) == 0x16A34A)
        #expect(try rgbHex(DashboardPalette.costLine, appearance: .aqua) == 0x16A34A)
        #expect(try rgbHex(DashboardPalette.statusInactive, appearance: .aqua) == 0xDC2626)
    }

    @MainActor
    @Test func dashboardSelectedRangeButtonUsesReadableLightAccentStyle() throws {
        let appearance = try #require(NSAppearance(named: .aqua))
        let viewController = ViewController(languageSettings: zhHansLanguageSettings())
        appearance.performAsCurrentDrawingAppearance {
            viewController.loadViewIfNeeded()
        }
        let selectedButton = try #require(viewController.view.button(identifier: "DashboardRange.sevenDays"))
        let backgroundColor = try #require(selectedButton.layer?.backgroundColor)
        let tintColor = try #require(selectedButton.contentTintColor)

        #expect(rgbHex(backgroundColor) == 0x2563EB)
        #expect(try rgbHex(tintColor, appearance: .aqua) == 0xFFFFFF)
    }

    @MainActor
    @Test func dashboardAnalysisPanelsUsePencilLightPanelBorders() throws {
        let appearance = try #require(NSAppearance(named: .aqua))
        let viewController = ViewController(languageSettings: zhHansLanguageSettings())
        appearance.performAsCurrentDrawingAppearance {
            viewController.loadViewIfNeeded()
        }

        for title in ["趋势", "模型消耗排行", "来源占比", "项目消耗"] {
            let panel = try panelTitled(title, root: viewController.view)
            #expect(rgbHex(try #require(panel.layer?.backgroundColor)) == 0xFFFFFF)
            #expect(panel.layer?.borderWidth == 1)
            #expect(rgbHex(try #require(panel.layer?.borderColor)) == 0xD8DEE8)
        }
    }

    @MainActor
    @Test func dashboardSourceLegendUsesPencilLightChartColors() throws {
        let calendar = utcCalendar()
        let now = dateTime(2026, 6, 20, hour: 14, minute: 30, calendar: calendar)
        let appearance = try #require(NSAppearance(named: .aqua))
        let viewController = DashboardViewController(
            settingsViewController: SettingsViewController(languageSettings: zhHansLanguageSettings()),
            stateProvider: {
                [
                    .claude: .init(
                        stats: makeDashboardStats(byDay: ["2026-06-20": makeDashboardSummary(total: 1_000)]),
                        isLoading: false,
                        errorMessage: nil,
                        needsAuthorization: false
                    ),
                    .codex: .init(
                        stats: makeDashboardStats(byDay: ["2026-06-20": makeDashboardSummary(total: 800)]),
                        isLoading: false,
                        errorMessage: nil,
                        needsAuthorization: false
                    ),
                    .opencode: .init(
                        stats: makeDashboardStats(byDay: ["2026-06-20": makeDashboardSummary(total: 600)]),
                        isLoading: false,
                        errorMessage: nil,
                        needsAuthorization: false
                    ),
                ]
            },
            refreshAction: {},
            nowProvider: { now },
            calendar: calendar,
            languageSettings: zhHansLanguageSettings()
        )
        appearance.performAsCurrentDrawingAppearance {
            viewController.loadViewIfNeeded()
        }

        let firstDot = try #require(viewController.view.firstDescendant(identifier: "DashboardSourceLegendDot.0"))
        let secondDot = try #require(viewController.view.firstDescendant(identifier: "DashboardSourceLegendDot.1"))
        let thirdDot = try #require(viewController.view.firstDescendant(identifier: "DashboardSourceLegendDot.2"))

        #expect(rgbHex(try #require(firstDot.layer?.backgroundColor)) == 0x5AA2FF)
        #expect(rgbHex(try #require(secondDot.layer?.backgroundColor)) == 0x4ADE80)
        #expect(rgbHex(try #require(thirdDot.layer?.backgroundColor)) == 0xFBBF24)
    }

    @MainActor
    @Test func dashboardTrendHoverShowsTokenAndCostInsteadOfCacheHitRate() throws {
        let trendView = DashboardTrendView()
        trendView.configure(buckets: [
            DashboardTrendBucket(
                id: "2026-06-20T14",
                key: "2026-06-20T14",
                label: "14时",
                totalTokens: 1_720_000,
                totalCost: 24.60,
                normalizedHeight: 1,
                normalizedCostHeight: 1,
                isCurrent: true
            ),
        ])

        trendView.debugSimulateHover(bucketKey: "2026-06-20T14")

        #expect(trendView.debugHoverText == "14时 · 1.7M · 费用 $24.60")
        #expect(!trendView.debugHoverText.contains("缓存"))
    }

    @MainActor
    @Test func dashboardTrendBucketsFollowSelectedRangeGranularity() throws {
        let calendar = utcCalendar()
        let now = dateTime(2026, 6, 20, hour: 14, minute: 30, calendar: calendar)
        let viewController = DashboardViewController(
            settingsViewController: SettingsViewController(languageSettings: zhHansLanguageSettings()),
            stateProvider: {
                [
                    .claude: .init(
                        stats: makeDashboardStats(
                            byHour: [
                                "2026-06-20T14": makeDashboardSummary(total: 120, cost: 1.25),
                            ],
                            byDay: [
                                "2026-06-14": makeDashboardSummary(total: 40, cost: 0.40),
                                "2026-06-20": makeDashboardSummary(total: 300, cost: 2.50),
                            ],
                            byMonth: [
                                "2026-04": makeDashboardSummary(total: 90, cost: 0.90),
                                "2026-05": makeDashboardSummary(total: 180, cost: 1.80),
                                "2026-06": makeDashboardSummary(total: 300, cost: 2.50),
                            ]
                        ),
                        isLoading: false,
                        errorMessage: nil,
                        needsAuthorization: false
                    ),
                ]
            },
            refreshAction: {},
            nowProvider: { now },
            calendar: calendar,
            languageSettings: zhHansLanguageSettings()
        )
        viewController.loadViewIfNeeded()
        let trendView = try #require(viewController.view.firstDescendant(ofType: DashboardTrendView.self))

        #expect(trendView.debugBucketKeys == [
            "2026-06-14", "2026-06-15", "2026-06-16", "2026-06-17",
            "2026-06-18", "2026-06-19", "2026-06-20",
        ])

        try clickDashboardRange("day", in: viewController)
        #expect(trendView.debugBucketKeys.first == "2026-06-20T00")
        #expect(trendView.debugBucketKeys.last == "2026-06-20T23")
        #expect(trendView.debugBucketKeys.count == 24)

        try clickDashboardRange("month", in: viewController)
        #expect(trendView.debugBucketKeys.first == "2026-05-22")
        #expect(trendView.debugBucketKeys.last == "2026-06-20")
        #expect(trendView.debugBucketKeys.count == 30)

        try clickDashboardRange("all", in: viewController)
        #expect(trendView.debugBucketKeys == ["2026-04", "2026-05", "2026-06"])
    }

    @MainActor
    @Test func dashboardProjectPanelUsesSelectedRangeProjectsInsteadOfModels() throws {
        let calendar = utcCalendar()
        let now = dateTime(2026, 6, 20, hour: 14, minute: 30, calendar: calendar)
        let stats = UsageAggregator().aggregate([
            makeDashboardEntry(
                sessionID: "s1",
                date: dateTime(2026, 6, 20, hour: 9, minute: 0, calendar: calendar),
                model: "model-alpha",
                input: 700,
                cwd: "/work/alpha-app"
            ),
            makeDashboardEntry(
                sessionID: "s2",
                date: dateTime(2026, 6, 19, hour: 10, minute: 0, calendar: calendar),
                model: "model-beta",
                input: 500,
                cwd: "/work/beta-app"
            ),
            makeDashboardEntry(
                sessionID: "legacy",
                date: dateTime(2026, 6, 1, hour: 10, minute: 0, calendar: calendar),
                model: "legacy-model",
                input: 9_000,
                cwd: "/work/legacy-app"
            ),
        ])
        let viewController = DashboardViewController(
            settingsViewController: SettingsViewController(languageSettings: zhHansLanguageSettings()),
            stateProvider: {
                [.claude: .init(
                    stats: stats,
                    isLoading: false,
                    errorMessage: nil,
                    needsAuthorization: false
                )]
            },
            refreshAction: {},
            nowProvider: { now },
            calendar: calendar,
            languageSettings: zhHansLanguageSettings()
        )
        viewController.loadViewIfNeeded()

        let projectPanelLabels = try labels(inPanelTitled: "项目消耗", root: viewController.view)
        #expect(projectPanelLabels.contains("alpha-app"))
        #expect(projectPanelLabels.contains("beta-app"))
        #expect(!projectPanelLabels.contains("model-alpha"))
        #expect(!projectPanelLabels.contains("model-beta"))
        #expect(!projectPanelLabels.contains("legacy-app"))
    }

    @MainActor
    @Test func dashboardProjectPanelMergesProjectsWithSameDisplayName() throws {
        let calendar = utcCalendar()
        let now = dateTime(2026, 6, 20, hour: 14, minute: 30, calendar: calendar)
        let stats = UsageAggregator().aggregate([
            makeDashboardEntry(
                sessionID: "s1",
                date: dateTime(2026, 6, 20, hour: 9, minute: 0, calendar: calendar),
                model: "model-alpha",
                input: 700,
                cwd: "/Users/orrhsiao/Desktop/Code/TokenWatch"
            ),
            makeDashboardEntry(
                sessionID: "s2",
                date: dateTime(2026, 6, 19, hour: 10, minute: 0, calendar: calendar),
                model: "model-beta",
                input: 500,
                cwd: "/private/tmp/TokenWatch"
            ),
        ])
        let viewController = DashboardViewController(
            settingsViewController: SettingsViewController(languageSettings: zhHansLanguageSettings()),
            stateProvider: {
                [.claude: .init(
                    stats: stats,
                    isLoading: false,
                    errorMessage: nil,
                    needsAuthorization: false
                )]
            },
            refreshAction: {},
            nowProvider: { now },
            calendar: calendar,
            languageSettings: zhHansLanguageSettings()
        )
        viewController.loadViewIfNeeded()

        var projectPanelLabels = try labels(inPanelTitled: "项目消耗", root: viewController.view)
        #expect(projectPanelLabels.filter { $0 == "TokenWatch" }.count == 1)
        #expect(projectPanelLabels.contains("1,200"))

        try clickDashboardRange("all", in: viewController)
        projectPanelLabels = try labels(inPanelTitled: "项目消耗", root: viewController.view)
        #expect(projectPanelLabels.filter { $0 == "TokenWatch" }.count == 1)
        #expect(projectPanelLabels.contains("1,200"))
    }

    @MainActor
    @Test func dashboardProjectPanelNormalizesGeneratedWorkspacePaths() throws {
        let calendar = utcCalendar()
        let now = dateTime(2026, 6, 20, hour: 14, minute: 30, calendar: calendar)
        let stats = UsageAggregator().aggregate([
            makeDashboardEntry(
                sessionID: "main",
                date: dateTime(2026, 6, 20, hour: 9, minute: 0, calendar: calendar),
                model: "model-alpha",
                input: 700,
                cwd: "/Users/orrhsiao/Desktop/Code/TokenWatch"
            ),
            makeDashboardEntry(
                sessionID: "agent",
                date: dateTime(2026, 6, 20, hour: 10, minute: 0, calendar: calendar),
                model: "model-beta",
                input: 500,
                cwd: "/Users/orrhsiao/Desktop/Code/TokenWatch/.claude/worktrees/agent-a43c08f58c97cbaed"
            ),
            makeDashboardEntry(
                sessionID: "pencil",
                date: dateTime(2026, 6, 20, hour: 11, minute: 0, calendar: calendar),
                model: "model-gamma",
                input: 4_000,
                cwd: "/Users/orrhsiao/.pencil/documents/687dce51-3ca3-4a6a-86db-814dae59f68d"
            ),
            makeDashboardEntry(
                sessionID: "temp",
                date: dateTime(2026, 6, 20, hour: 12, minute: 0, calendar: calendar),
                model: "model-delta",
                input: 8_000,
                cwd: "/var/folders/r_/g4y4wqs13sx3z39kb7gtyzpw0000gn/T"
            ),
        ])
        let viewController = DashboardViewController(
            settingsViewController: SettingsViewController(languageSettings: zhHansLanguageSettings()),
            stateProvider: {
                [.claude: .init(
                    stats: stats,
                    isLoading: false,
                    errorMessage: nil,
                    needsAuthorization: false
                )]
            },
            refreshAction: {},
            nowProvider: { now },
            calendar: calendar,
            languageSettings: zhHansLanguageSettings()
        )
        viewController.loadViewIfNeeded()

        var projectPanelLabels = try labels(inPanelTitled: "项目消耗", root: viewController.view)
        #expect(projectPanelLabels.filter { $0 == "TokenWatch" }.count == 1)
        #expect(projectPanelLabels.contains("1,200"))
        #expect(!projectPanelLabels.contains("agent-a43c08f58c97cbaed"))
        #expect(!projectPanelLabels.contains("687dce51-3ca3-4a6a-86db-814dae59f68d"))
        #expect(!projectPanelLabels.contains("T"))

        try clickDashboardRange("all", in: viewController)
        projectPanelLabels = try labels(inPanelTitled: "项目消耗", root: viewController.view)
        #expect(projectPanelLabels.filter { $0 == "TokenWatch" }.count == 1)
        #expect(projectPanelLabels.contains("1,200"))
        #expect(!projectPanelLabels.contains("agent-a43c08f58c97cbaed"))
        #expect(!projectPanelLabels.contains("687dce51-3ca3-4a6a-86db-814dae59f68d"))
        #expect(!projectPanelLabels.contains("T"))
    }

    @MainActor
    @Test func dashboardOverviewOmitsRecentDetailsForSelectedRange() throws {
        let calendar = utcCalendar()
        let now = dateTime(2026, 6, 20, hour: 14, minute: 30, calendar: calendar)
        let recentEntry = makeDashboardEntry(
            sessionID: "session-recent",
            date: dateTime(2026, 6, 20, hour: 10, minute: 0, calendar: calendar),
            model: "model-recent",
            input: 700,
            cwd: "/work/recent-app"
        )
        let olderEntry = makeDashboardEntry(
            sessionID: "session-older",
            date: dateTime(2026, 6, 19, hour: 9, minute: 0, calendar: calendar),
            model: "model-older",
            input: 500,
            cwd: "/work/older-app"
        )
        let outOfRangeEntry = makeDashboardEntry(
            sessionID: "session-out-of-range",
            date: dateTime(2026, 6, 1, hour: 9, minute: 0, calendar: calendar),
            model: "model-legacy",
            input: 9_000,
            cwd: "/work/legacy-app"
        )
        let entries = [recentEntry, olderEntry, outOfRangeEntry]
        let stats = UsageAggregator().aggregate(entries)
        let viewController = DashboardViewController(
            settingsViewController: SettingsViewController(languageSettings: zhHansLanguageSettings()),
            stateProvider: {
                [.claude: .init(
                    stats: stats,
                    entries: entries,
                    isLoading: false,
                    errorMessage: nil,
                    needsAuthorization: false
                )]
            },
            refreshAction: {},
            nowProvider: { now },
            calendar: calendar,
            languageSettings: zhHansLanguageSettings()
        )
        viewController.loadViewIfNeeded()

        let labels = viewController.view.allDescendants(ofType: NSTextField.self).map(\.stringValue)
        #expect(!labels.contains("最近明细"))
        #expect(!labels.contains("session-recent"))
        #expect(!labels.contains("session-older"))
        #expect(!labels.contains("session-out-of-range"))
        #expect(!labels.contains("汇总"))
        #expect(!labels.contains("全部项目"))
    }

    @MainActor
    @Test func dashboardRefreshButtonIsStableActionEntry() throws {
        let viewController = ViewController(languageSettings: zhHansLanguageSettings())
        viewController.loadViewIfNeeded()

        let refreshButton = try #require(viewController.view.button(identifier: "DashboardRefreshButton"))
        #expect(refreshButton.title == "立即刷新")
        #expect(refreshButton.action.map(NSStringFromSelector) == "refreshDashboard:")
        #expect(refreshButton.image != nil)
        #expect(refreshButton.imageHugsTitle)
    }

    @MainActor
    @Test func mainMenuSettingsCommandShowsSettingsActions() throws {
        let viewController = ViewController(languageSettings: zhHansLanguageSettings())
        viewController.loadViewIfNeeded()

        viewController.showSettingsFromMainMenu(nil)

        let mainContent = try #require(viewController.view.firstDescendant(identifier: "DashboardMainContent"))
        let buttonTitles = mainContent.allDescendants(ofType: NSButton.self).map(\.title)
        #expect(buttonTitles.contains("去授权") || buttonTitles.contains("已授权"))
        #expect(buttonTitles.contains("刷新全部数据"))
        #expect(!buttonTitles.contains("隐私政策"))
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
            #expect(AutoRefreshSettings(defaults: defaults).selectedOption == .minutes5)
            #expect(popUpButton.titleOfSelectedItem == "5 分钟")
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
            popUpButton.selectItem(withTitle: "15 分钟")
            _ = popUpButton.sendAction(popUpButton.action, to: popUpButton.target)

            #expect(defaults.string(forKey: "TokenWatch.autoRefreshInterval") == "minutes15")
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
            #expect(buttons.first { $0.title == "隐私政策" } == nil)
            #expect(settingsViewController.view.button(identifier: "PrivacyPolicyButton") == nil)

            let autoRefreshPopUp = try #require(settingsViewController.view.popUpButton(identifier: "AutoRefreshIntervalPopUpButton"))
            #expect(autoRefreshPopUp.accessibilityIdentifier() == "AutoRefreshIntervalPopUpButton")

            let launchAtLoginSwitch = try #require(settingsViewController.view.switchControl(identifier: "LaunchAtLoginSwitch"))
            #expect(launchAtLoginSwitch.accessibilityIdentifier() == "LaunchAtLoginSwitch")

            let languagePopUp = try #require(settingsViewController.view.popUpButton(identifier: "LanguagePreferencePopUpButton"))
            #expect(languagePopUp.accessibilityIdentifier() == "LanguagePreferencePopUpButton")
        }
    }

    @MainActor
    @Test func settingsPageUsesPencilLightColors() throws {
        try withTemporaryDefaults { defaults in
            let appearance = try #require(NSAppearance(named: .aqua))
            let settingsViewController = SettingsViewController(
                isAuthorized: { false },
                autoRefreshSettings: AutoRefreshSettings(defaults: defaults),
                languageSettings: zhHansLanguageSettings(defaults: defaults)
            )
            appearance.performAsCurrentDrawingAppearance {
                settingsViewController.loadViewIfNeeded()
            }

            let panel = try #require(settingsViewController.view.firstDescendant(identifier: "SettingsPanel"))
            let titleLabel = try #require(settingsViewController.view.textField(stringValue: "设置"))
            let descriptionLabel = try #require(settingsViewController.view.textField(stringValue: "管理 TokenWatch 的通用访问权限和数据刷新。"))
            let authorizationLabel = try #require(settingsViewController.view.textField(stringValue: "通用访问权限"))
            let authorizeButton = try #require(settingsViewController.view.button(identifier: "AuthorizationActionButton"))
            let refreshButton = try #require(settingsViewController.view.button(identifier: "RefreshAllDataButton"))
            let autoRefreshPopUp = try #require(settingsViewController.view.popUpButton(identifier: "AutoRefreshIntervalPopUpButton"))
            let languagePopUp = try #require(settingsViewController.view.popUpButton(identifier: "LanguagePreferencePopUpButton"))

            #expect(rgbHex(try #require(settingsViewController.view.layer?.backgroundColor)) == 0xF4F6FA)
            #expect(rgbHex(try #require(panel.layer?.backgroundColor)) == 0xFFFFFF)
            #expect(rgbHex(try #require(panel.layer?.borderColor)) == 0xD8DEE8)
            #expect(try rgbHex(try #require(titleLabel.textColor), appearance: .aqua) == 0x111827)
            #expect(try rgbHex(try #require(descriptionLabel.textColor), appearance: .aqua) == 0x6B7280)
            #expect(try rgbHex(try #require(authorizationLabel.textColor), appearance: .aqua) == 0x111827)
            #expect(rgbHex(try #require(authorizeButton.layer?.backgroundColor)) == 0x2563EB)
            #expect(rgbHex(try #require(authorizeButton.layer?.borderColor)) == 0x2563EB)
            #expect(try rgbHex(try #require(authorizeButton.contentTintColor), appearance: .aqua) == 0xFFFFFF)
            #expect(rgbHex(try #require(refreshButton.layer?.backgroundColor)) == 0xFFFFFF)
            #expect(rgbHex(try #require(refreshButton.layer?.borderColor)) == 0xD8DEE8)
            #expect(rgbHex(try #require(autoRefreshPopUp.layer?.backgroundColor)) == 0xFFFFFF)
            #expect(rgbHex(try #require(autoRefreshPopUp.layer?.borderColor)) == 0xD8DEE8)
            #expect(rgbHex(try #require(languagePopUp.layer?.backgroundColor)) == 0xFFFFFF)
            #expect(rgbHex(try #require(languagePopUp.layer?.borderColor)) == 0xD8DEE8)
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
    @Test func dashboardUsesEnglishCopyWhenLanguageIsEnglish() throws {
        withTemporaryDefaults { defaults in
            let languageSettings = AppLanguageSettings(defaults: defaults, preferredLanguagesProvider: { ["zh-Hans-US"] })
            languageSettings.selectedPreference = .en
            let viewController = ViewController(languageSettings: languageSettings)
            viewController.loadViewIfNeeded()

            let navTitles: [String] = viewController.view.allDescendants(ofType: NSButton.self).compactMap { button -> String? in
                guard button.identifier?.rawValue.hasPrefix("DashboardNav.") == true else { return nil }
                return button.title
            }
            let labels = viewController.view.allDescendants(ofType: NSTextField.self).map(\.stringValue)

            #expect(navTitles == ["Overview", "Sessions", "Settings"])
            #expect(labels.contains("Usage Overview"))
            #expect(labels.contains("Summarizes local records from Claude Code, Codex rollout, and opencode SQLite"))
            #expect(labels.contains("Data Sources"))
            #expect(labels.contains("Last Local Scan"))
            #expect(labels.contains("Trend"))
            #expect(labels.contains("Model Usage Ranking"))
            #expect(labels.contains("Source Share"))
            #expect(labels.contains("Project Usage"))
            #expect(!labels.contains("Recent Details"))
            #expect(!labels.contains("用量总览"))
        }
    }

    @MainActor
    @Test func dashboardRefreshesVisibleCopyAfterLanguageChange() throws {
        withTemporaryDefaults { defaults in
            let languageSettings = AppLanguageSettings(defaults: defaults, preferredLanguagesProvider: { ["zh-Hans-US"] })
            let viewController = ViewController(languageSettings: languageSettings)
            viewController.loadViewIfNeeded()

            languageSettings.selectedPreference = .en

            let navTitles: [String] = viewController.view.allDescendants(ofType: NSButton.self).compactMap { button -> String? in
                guard button.identifier?.rawValue.hasPrefix("DashboardNav.") == true else { return nil }
                return button.title
            }
            let labels = viewController.view.allDescendants(ofType: NSTextField.self).map(\.stringValue)

            #expect(navTitles == ["Overview", "Sessions", "Settings"])
            #expect(labels.contains("Usage Overview"))
            #expect(!labels.contains("用量总览"))
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

    func firstAncestor(where predicate: (NSView) -> Bool) -> NSView? {
        var current = superview
        while let view = current {
            if predicate(view) {
                return view
            }
            current = view.superview
        }
        return nil
    }

    var fixedHeightConstant: CGFloat? {
        constraints.first {
            $0.firstAttribute == .height
                && $0.relation == .equal
                && $0.secondItem == nil
        }?.constant
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

private func utcCalendar() -> Calendar {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(secondsFromGMT: 0)!
    calendar.firstWeekday = 2
    return calendar
}

private func dateTime(
    _ year: Int,
    _ month: Int,
    _ day: Int,
    hour: Int,
    minute: Int,
    calendar: Calendar
) -> Date {
    calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour, minute: minute))!
}

private func rgbHex(_ color: NSColor, appearance: NSAppearance.Name) throws -> Int {
    let appearance = try #require(NSAppearance(named: appearance))
    var components: [CGFloat]?
    appearance.performAsCurrentDrawingAppearance {
        components = color.cgColor.components
    }
    let rgba = try #require(components)
    #expect(rgba.count >= 3)

    return Int((rgba[0] * 255).rounded()) << 16
        | Int((rgba[1] * 255).rounded()) << 8
        | Int((rgba[2] * 255).rounded())
}

private func rgbHex(_ color: CGColor) -> Int {
    let convertedColor = color.converted(
        to: CGColorSpace(name: CGColorSpace.sRGB)!,
        intent: .defaultIntent,
        options: nil
    ) ?? color
    let components = convertedColor.components ?? [0, 0, 0, 1]
    return Int((components[0] * 255).rounded()) << 16
        | Int((components[1] * 255).rounded()) << 8
        | Int((components[2] * 255).rounded())
}

private func alphaValue(_ color: CGColor) -> Int {
    let convertedColor = color.converted(
        to: CGColorSpace(name: CGColorSpace.sRGB)!,
        intent: .defaultIntent,
        options: nil
    ) ?? color
    return Int(((convertedColor.components?.last ?? 1) * 255).rounded())
}

private func refreshEffectiveAppearance(in view: NSView) {
    view.viewDidChangeEffectiveAppearance()
    view.subviews.forEach(refreshEffectiveAppearance)
}

private final class AppearanceCallbackSentinelView: NSView {
    var appearanceCallbackCount = 0

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        appearanceCallbackCount += 1
    }
}

@MainActor
private func clickDashboardRange(_ rawValue: String, in viewController: DashboardViewController) throws {
    let button = try #require(viewController.view.button(identifier: "DashboardRange.\(rawValue)"))
    _ = button.sendAction(button.action, to: button.target)
}

@MainActor
private func clickDashboardNavigation(_ rawValue: String, in viewController: NSViewController) throws {
    let button = try #require(viewController.view.button(identifier: "DashboardNav.\(rawValue)"))
    _ = button.sendAction(button.action, to: button.target)
}

private func makeDashboardStats(
    byHour: [String: UsageSummary] = [:],
    byDay: [String: UsageSummary] = [:],
    byMonth: [String: UsageSummary] = [:]
) -> AggregatedStats {
    var overall = UsageSummary.zero
    for summary in byMonth.values {
        overall = mergeDashboardSummaries(overall, summary)
    }
    for summary in byDay.values {
        overall = mergeDashboardSummaries(overall, summary)
    }
    for summary in byHour.values {
        overall = mergeDashboardSummaries(overall, summary)
    }
    return AggregatedStats(
        overall: overall,
        byHour: byHour,
        byDay: byDay,
        byWeek: [:],
        byMonth: byMonth,
        bySession: [:],
        byModel: [:],
        byProject: [:],
        dataSourceCount: 1
    )
}

private func makeDashboardEntry(
    sessionID: String,
    date: Date,
    model: String,
    input: Int,
    cwd: String
) -> ParsedUsageEntry {
    let id = UUID().uuidString
    return ParsedUsageEntry(
        recordUUID: id,
        messageId: id,
        requestId: nil,
        sessionID: sessionID,
        timestamp: date,
        model: model,
        cwd: cwd,
        agentId: nil,
        usage: TokenUsage(
            inputTokens: input,
            cacheCreationInputTokens: 0,
            cacheReadInputTokens: 0,
            outputTokens: 0,
            reasoningTokens: 0,
            serverToolUse: ServerToolUse(webSearchRequests: 0, webFetchRequests: 0),
            serviceTier: "standard",
            cacheCreation: CacheCreation(ephemeral1hInputTokens: 0, ephemeral5mInputTokens: 0),
            inferenceGeo: "",
            iterations: [],
            speed: "standard"
        ),
        isSubagent: false,
        provider: .claude,
        upstreamProviderID: nil,
        upstreamCost: nil
    )
}

@MainActor
private func labels(inPanelTitled title: String, root: NSView) throws -> [String] {
    try panelTitled(title, root: root).allDescendants(ofType: NSTextField.self).map(\.stringValue)
}

@MainActor
private func textField(_ value: String, inPanelTitled title: String, root: NSView) throws -> NSTextField {
    let panel = try panelTitled(title, root: root)
    return try #require(panel.textField(stringValue: value))
}

@MainActor
private func panelTitled(_ title: String, root: NSView) throws -> NSView {
    let titleLabel = try #require(root.textField(stringValue: title))
    return try #require(titleLabel.firstAncestor { view in
        guard let cornerRadius = view.layer?.cornerRadius else { return false }
        return abs(cornerRadius - 8) < 0.1
    })
}

@MainActor
private func roundedAncestor(containingText text: String, root: NSView) throws -> NSView {
    let label = try #require(root.textField(stringValue: text))
    return try #require(label.firstAncestor { view in
        guard let cornerRadius = view.layer?.cornerRadius else { return false }
        return abs(cornerRadius - 8) < 0.1
    })
}

@MainActor
private func labels(inContainer identifier: String, root: NSView) throws -> [String] {
    let container = try #require(root.firstDescendant(identifier: identifier))
    return container.visibleTextValues()
}

private extension NSView {
    func visibleTextValues() -> [String] {
        var values: [String] = []
        if let textField = self as? NSTextField {
            values.append(textField.stringValue)
        }
        if let button = self as? NSButton, !button.title.isEmpty {
            values.append(button.title)
        }
        for subview in subviews {
            values.append(contentsOf: subview.visibleTextValues())
        }
        return values
    }
}

private func restoreUserDefaultsValue(_ value: Any?, forKey key: String) {
    if let value {
        UserDefaults.standard.set(value, forKey: key)
    } else {
        UserDefaults.standard.removeObject(forKey: key)
    }
}

private func mergeDashboardSummaries(_ lhs: UsageSummary, _ rhs: UsageSummary) -> UsageSummary {
    UsageSummary(
        inputTokens: lhs.inputTokens + rhs.inputTokens,
        outputTokens: lhs.outputTokens + rhs.outputTokens,
        cacheReadTokens: lhs.cacheReadTokens + rhs.cacheReadTokens,
        cacheCreationTokens: lhs.cacheCreationTokens + rhs.cacheCreationTokens,
        reasoningTokens: lhs.reasoningTokens + rhs.reasoningTokens,
        totalTokens: lhs.totalTokens + rhs.totalTokens,
        cost: lhs.cost + rhs.cost,
        entryCount: lhs.entryCount + rhs.entryCount,
        modelBreakdown: [:]
    )
}

private func makeDashboardSummary(
    total: Int? = nil,
    input: Int? = nil,
    output: Int = 0,
    reasoning: Int = 0,
    cacheRead: Int = 0,
    cacheCreation: Int = 0,
    cost: Double = 0
) -> UsageSummary {
    let inputTokens = input ?? total ?? 0
    let totalTokens = total ?? (inputTokens + output + reasoning + cacheRead + cacheCreation)
    return UsageSummary(
        inputTokens: inputTokens,
        outputTokens: output,
        cacheReadTokens: cacheRead,
        cacheCreationTokens: cacheCreation,
        reasoningTokens: reasoning,
        totalTokens: totalTokens,
        cost: cost,
        entryCount: totalTokens > 0 ? 1 : 0,
        modelBreakdown: [:]
    )
}
