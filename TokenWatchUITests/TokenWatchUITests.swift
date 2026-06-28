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
        XCTAssertTrue(app.staticTexts["TokenWatch"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["本地 AI 用量监控"].exists)
        XCTAssertTrue(app.staticTexts["用量总览"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["总 Token"].exists)
        XCTAssertTrue(app.staticTexts["总费用"].exists)
        XCTAssertTrue(app.staticTexts["会话数"].exists)
        XCTAssertTrue(app.staticTexts["模型消耗排行"].exists)
        XCTAssertTrue(app.staticTexts["最近明细"].exists)
    }

    @MainActor
    func testDashboardAnalysisPanelsAreLeadingAligned() throws {
        let app = XCUIApplication()
        app.launchForUITesting()

        let overviewTitle = app.staticTexts["用量总览"]
        XCTAssertTrue(overviewTitle.waitForExistence(timeout: 5))

        let trendTitle = app.staticTexts["每小时 Token 与缓存命中率"]
        XCTAssertTrue(trendTitle.waitForExistence(timeout: 5))
        XCTAssertLessThanOrEqual(trendTitle.frame.minX, overviewTitle.frame.minX + 32)
    }

    @MainActor
    func testDashboardNavigationKeepsPencilSidebar() throws {
        let app = XCUIApplication()
        app.launchForUITesting()

        XCTAssertTrue(app.windows.element(boundBy: 0).waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["用量总览"].waitForExistence(timeout: 5))

        let timelineButton = app.buttons["DashboardNav.timeline"]
        XCTAssertTrue(timelineButton.waitForExistence(timeout: 5))
        timelineButton.click()
        XCTAssertTrue(app.staticTexts["每小时 Token 与缓存命中率"].waitForExistence(timeout: 5))

        let modelsButton = app.buttons["DashboardNav.models"]
        XCTAssertTrue(modelsButton.waitForExistence(timeout: 5))
        modelsButton.click()
        XCTAssertTrue(app.staticTexts["模型消耗排行"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["DashboardNav.settings"].exists)
    }

    @MainActor
    func testSettingsPageExposesActionControls() throws {
        let app = XCUIApplication()
        app.launchForUITesting()

        let settingsButton = app.buttons["DashboardNav.settings"]
        XCTAssertTrue(settingsButton.waitForExistence(timeout: 5))
        settingsButton.click()

        XCTAssertTrue(app.staticTexts["通用访问权限"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.descendants(matching: .any)["AuthorizationActionButton"].exists)
        XCTAssertTrue(app.descendants(matching: .any)["RefreshAllDataButton"].exists)
        XCTAssertTrue(app.descendants(matching: .any)["AutoRefreshIntervalPopUpButton"].exists)
        XCTAssertTrue(app.descendants(matching: .any)["LaunchAtLoginSwitch"].exists)
        XCTAssertTrue(app.descendants(matching: .any)["LanguagePreferencePopUpButton"].exists)
    }
}

extension XCUIApplication {
    func launchForUITesting(languagePreference: String = "zh-Hans") {
        let existingApp = XCUIApplication(bundleIdentifier: "com.xiaoao.TokenWatch")
        if existingApp.state != .notRunning {
            existingApp.terminate()
            _ = existingApp.wait(for: .notRunning, timeout: 5)
        }
        if state != .notRunning {
            terminate()
            _ = wait(for: .notRunning, timeout: 5)
        }
        launchArguments += [
            "-TokenWatch.didPromptInitialHomeAuthorization", "YES",
            "-TokenWatch.languagePreference", languagePreference,
            "-TokenWatch.openMainWindowOnLaunch", "YES",
        ]
        launch()
    }
}
