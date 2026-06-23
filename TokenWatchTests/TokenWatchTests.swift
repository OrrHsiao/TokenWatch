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
    @Test func mainStoryboardUsesRoomierDefaultWindowSize() throws {
        let storyboard = NSStoryboard(name: "Main", bundle: Bundle.main)
        let windowController = try #require(storyboard.instantiateInitialController() as? NSWindowController)
        let contentSize = try #require(windowController.window?.contentView?.frame.size)

        #expect(contentSize == NSSize(width: 900, height: 640))
    }

    @MainActor
    @Test func mainWindowUsesNativeSidebarSplitLayout() throws {
        let viewController = ViewController()
        viewController.loadViewIfNeeded()

        let splitView = try #require(viewController.view.firstDescendant(ofType: NSSplitView.self))
        #expect(splitView.isVertical)
        #expect(splitView.arrangedSubviews.count == 2)
    }

    @MainActor
    @Test func sidebarListsAggregatePagesAndSettingsOnly() throws {
        let viewController = ViewController()
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
    @Test func initialSelectionShowsTotalStatsPage() throws {
        let viewController = ViewController()
        viewController.loadViewIfNeeded()

        let labels = viewController.view.allDescendants(ofType: NSTextField.self).map(\.stringValue)
        #expect(!labels.contains("总 token"))
        #expect(!labels.contains("总费用"))
        #expect(labels.contains("模型消耗"))
    }

    @MainActor
    @Test func selectingTotalShowsTotalStatsPage() throws {
        let viewController = ViewController()
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
        let viewController = ViewController()
        viewController.loadViewIfNeeded()

        let sidebar = try #require(viewController.view.firstDescendant(ofType: NSTableView.self))
        sidebar.selectRowIndexes(IndexSet(integer: sidebar.numberOfRows - 4), byExtendingSelection: false)

        let labels = viewController.view.allDescendants(ofType: NSTextField.self).map(\.stringValue)
        #expect(labels.contains("最近 12 个月"))
        #expect(labels.contains("最近 12 个月,跨 provider 汇总"))
        #expect(viewController.view.firstDescendant(ofType: MonthlyTokenChartView.self) != nil)
    }

    @MainActor
    @Test func selectingRecentThirtyDaysShowsDailyChartPage() throws {
        let viewController = ViewController()
        viewController.loadViewIfNeeded()

        let sidebar = try #require(viewController.view.firstDescendant(ofType: NSTableView.self))
        sidebar.selectRowIndexes(IndexSet(integer: sidebar.numberOfRows - 3), byExtendingSelection: false)

        let labels = viewController.view.allDescendants(ofType: NSTextField.self).map(\.stringValue)
        #expect(labels.contains("最近 30 天"))
        #expect(labels.contains("最近 30 天,跨 provider 汇总"))
        #expect(viewController.view.firstDescendant(ofType: MonthlyTokenChartView.self) != nil)
    }

    @MainActor
    @Test func selectingTodayShowsTodayChartPage() throws {
        let viewController = ViewController()
        viewController.loadViewIfNeeded()

        let sidebar = try #require(viewController.view.firstDescendant(ofType: NSTableView.self))
        sidebar.selectRowIndexes(IndexSet(integer: sidebar.numberOfRows - 2), byExtendingSelection: false)

        let labels = viewController.view.allDescendants(ofType: NSTextField.self).map(\.stringValue)
        #expect(labels.contains("本日"))
        #expect(labels.contains("本日,跨 provider 汇总"))
        #expect(viewController.view.firstDescendant(ofType: MonthlyTokenChartView.self) != nil)
    }

    @MainActor
    @Test func selectingSettingsShowsSettingsActions() throws {
        let viewController = ViewController()
        viewController.loadViewIfNeeded()

        let sidebar = try #require(viewController.view.firstDescendant(ofType: NSTableView.self))
        sidebar.selectRowIndexes(IndexSet(integer: sidebar.numberOfRows - 1), byExtendingSelection: false)

        let buttonTitles = viewController.view.allDescendants(ofType: NSButton.self).map(\.title)
        #expect(buttonTitles.contains("去授权") || buttonTitles.contains("已授权"))
        #expect(buttonTitles.contains("刷新全部数据"))
    }

    @MainActor
    @Test func settingsAuthorizationRowReflectsExistingAuthorization() throws {
        let settingsViewController = SettingsViewController(isAuthorized: { true })
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
        let settingsViewController = SettingsViewController(isAuthorized: { false })
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
            let settingsViewController = SettingsViewController(isAuthorized: { false }, defaults: defaults)
            settingsViewController.loadViewIfNeeded()

            let labels = settingsViewController.view.allDescendants(ofType: NSTextField.self).map(\.stringValue)
            #expect(labels.contains("自动刷新间隔"))

            let popUpButton = try #require(settingsViewController.view.firstDescendant(ofType: NSPopUpButton.self))
            #expect(popUpButton.itemTitles == ["30 秒", "1 分钟", "5 分钟", "15 分钟", "关闭自动刷新"])
            #expect(popUpButton.titleOfSelectedItem == "30 秒")
        }
    }

    @MainActor
    @Test func changingAutoRefreshIntervalPersistsSelection() throws {
        try withTemporaryDefaults { defaults in
            let settingsViewController = SettingsViewController(isAuthorized: { false }, defaults: defaults)
            settingsViewController.loadViewIfNeeded()

            let popUpButton = try #require(settingsViewController.view.firstDescendant(ofType: NSPopUpButton.self))
            popUpButton.selectItem(withTitle: "5 分钟")
            _ = popUpButton.sendAction(popUpButton.action, to: popUpButton.target)

            #expect(defaults.string(forKey: "TokenWatch.autoRefreshInterval") == "minutes5")
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
}

private func withTemporaryDefaults(_ body: (UserDefaults) throws -> Void) rethrows {
    let suiteName = "TokenWatchTests.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suiteName)!
    defer { defaults.removePersistentDomain(forName: suiteName) }
    try body(defaults)
}
