//
//  TokenWatchUITests.swift
//  TokenWatchUITests
//
//  Created by OrrHsiao on 2026/6/13.
//

import XCTest

final class TokenWatchUITests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testLaunchShowsPencilDashboardOverview() throws {
        let app = XCUIApplication()
        app.launchForUITesting()

        XCTAssertTrue(app.windows.element(boundBy: 0).waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["AI Token Watch"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["本地 AI 用量监控"].exists)
        XCTAssertTrue(app.staticTexts["用量总览"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["总 Tokens"].exists)
        XCTAssertTrue(app.staticTexts["总费用"].exists)
        XCTAssertTrue(app.staticTexts["会话数"].exists)
        XCTAssertTrue(app.staticTexts["模型消耗排行"].exists)
        XCTAssertFalse(app.staticTexts["最近明细"].exists)
    }

    @MainActor
    func testDashboardAnalysisPanelsAreLeadingAligned() throws {
        let app = XCUIApplication()
        app.launchForUITesting()

        let overviewTitle = app.staticTexts["用量总览"]
        XCTAssertTrue(overviewTitle.waitForExistence(timeout: 5))

        let trendTitle = app.staticTexts["趋势"]
        XCTAssertTrue(trendTitle.waitForExistence(timeout: 5))
        XCTAssertLessThanOrEqual(trendTitle.frame.minX, overviewTitle.frame.minX + 32)
    }

    @MainActor
    func testDashboardNavigationKeepsPencilSidebar() throws {
        let app = XCUIApplication()
        app.launchForUITesting()

        XCTAssertTrue(app.windows.element(boundBy: 0).waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["用量总览"].waitForExistence(timeout: 5))

        XCTAssertTrue(app.buttons["DashboardNav.overview"].waitForExistence(timeout: 5))

        let sessionsButton = app.buttons["DashboardNav.sessions"]
        XCTAssertTrue(sessionsButton.waitForExistence(timeout: 5))
        sessionsButton.click()
        XCTAssertTrue(app.scrollViews["DashboardSessionsTableScrollView"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["DashboardNav.settings"].exists)
    }

    @MainActor
    func testSessionTableScrollsHorizontally() throws {
        let app = XCUIApplication()
        app.launchForUITesting()

        let sessionsButton = app.buttons["DashboardNav.sessions"]
        XCTAssertTrue(sessionsButton.waitForExistence(timeout: 5))
        sessionsButton.click()

        let tableScrollView = app.scrollViews["DashboardSessionsTableScrollView"]
        XCTAssertTrue(tableScrollView.waitForExistence(timeout: 5))

        let nextButton = app.buttons["DashboardSessionsPagination.next"]
        XCTAssertTrue(nextButton.waitForExistence(timeout: 5))
        let initialMinX = nextButton.frame.minX

        // 优先按一个方向滚动；若已在该方向的边界则反向滚动，必须观察到内容位置改变。
        tableScrollView.scroll(byDeltaX: -400, deltaY: 0)
        var shiftedMinX = nextButton.frame.minX
        if shiftedMinX >= initialMinX - 1 {
            tableScrollView.scroll(byDeltaX: 400, deltaY: 0)
            shiftedMinX = nextButton.frame.minX
        }
        XCTAssertLessThan(shiftedMinX, initialMinX - 1)
    }

    @MainActor
    func testForcedInitialAuthorizationGuideNavigatesToSettings() throws {
        let app = XCUIApplication()
        app.launchForUITesting(
            languagePreference: "en",
            skipInitialDirectoryAuthorizationGuide: false
        )

        XCTAssertTrue(app.windows.firstMatch.waitForExistence(timeout: 5))
        XCTAssertTrue(
            app.staticTexts["Set Up Data Folders"].waitForExistence(timeout: 5)
        )

        let authorizationGuide = app.dialogs.element(boundBy: 0)
        XCTAssertTrue(authorizationGuide.waitForExistence(timeout: 5))

        let openSettingsButton = authorizationGuide.buttons["Go to Settings"]
        XCTAssertTrue(openSettingsButton.waitForExistence(timeout: 5))
        openSettingsButton.click()

        let claudeDirectoryButton = app.buttons["ProviderDirectoryAction.claude"]
        let claudeButtonReady = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "exists == true AND enabled == true"),
            object: claudeDirectoryButton
        )
        XCTAssertEqual(
            XCTWaiter.wait(for: [claudeButtonReady], timeout: 5),
            .completed
        )
        XCTAssertTrue(app.staticTexts["Settings"].exists)
    }

    @MainActor
    func testSettingsExposeThreeProviderDirectoryControls() throws {
        let app = XCUIApplication()
        app.launchForUITesting(languagePreference: "en")

        let settingsButton = app.buttons["DashboardNav.settings"]
        XCTAssertTrue(settingsButton.waitForExistence(timeout: 5))
        settingsButton.click()

        for id in ["claude", "codex", "opencode"] {
            XCTAssertTrue(
                app.buttons["ProviderDirectoryAction.\(id)"]
                    .waitForExistence(timeout: 5)
            )
        }
    }

    @MainActor
    func testArabicLaunchUsesLocalizedCopyAndKeepsLTRLayout() throws {
        let app = XCUIApplication()
        app.launchForUITesting(languagePreference: "ar", systemLanguage: "ar")

        let overviewButton = app.buttons["DashboardNav.overview"]
        let dashboardTitle = app.staticTexts["نظرة عامة على الاستخدام"]
        XCTAssertTrue(overviewButton.waitForExistence(timeout: 5))
        XCTAssertTrue(dashboardTitle.waitForExistence(timeout: 5))
        XCTAssertLessThan(overviewButton.frame.minX, dashboardTitle.frame.minX)

        let settingsButton = app.buttons["DashboardNav.settings"]
        XCTAssertTrue(settingsButton.waitForExistence(timeout: 5))
        settingsButton.click()
        XCTAssertTrue(app.staticTexts["الإعدادات"].waitForExistence(timeout: 5))
    }
}

extension XCUIApplication {
    func launchForUITesting(
        languagePreference: String = "zh-CN",
        skipInitialDirectoryAuthorizationGuide: Bool = true,
        systemLanguage: String? = nil
    ) {
        let existingApp = XCUIApplication(bundleIdentifier: "com.xiaoao.tokenwatch")
        if existingApp.state != .notRunning {
            existingApp.terminate()
            _ = existingApp.wait(for: .notRunning, timeout: 5)
        }
        if state != .notRunning {
            terminate()
            _ = wait(for: .notRunning, timeout: 5)
        }
        launchArguments += [
            "-ClaudeDataDirectoryBookmark", "absent",
            "-CodexDataDirectoryBookmark", "absent",
            "-OpenCodeDataDirectoryBookmark", "absent",
            "-TokenWatch.languagePreference", languagePreference,
            "-TokenWatch.openMainWindowOnLaunch", "YES",
        ]
        if skipInitialDirectoryAuthorizationGuide {
            launchArguments += [
                "-TokenWatch.didPresentInitialDirectoryAuthorizationGuide", "YES",
            ]
        } else {
            launchArguments += [
                "--force-initial-directory-authorization-guide",
            ]
        }
        if let systemLanguage {
            launchArguments += [
                "-AppleLanguages", "(\(systemLanguage))",
                "-AppleLocale", systemLanguage,
            ]
        }
        launch()
    }
}
