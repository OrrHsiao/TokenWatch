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
        XCTAssertTrue(app.staticTexts["总 Token"].exists)
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
        XCTAssertTrue(app.staticTexts["按最近时间倒序查看会话聚合、成本与使用记录"].waitForExistence(timeout: 5))
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

        let openSettingsButton = app.buttons["Go to Settings"]
        XCTAssertTrue(openSettingsButton.waitForExistence(timeout: 5))
        openSettingsButton.click()

        XCTAssertTrue(
            app.buttons["ProviderDirectoryAction.claude"].waitForExistence(timeout: 5)
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
    func testCancellingOneProviderPanelLeavesAllRowsUnselected() throws {
        let app = XCUIApplication()
        app.launchForUITesting(languagePreference: "en")

        let settingsButton = app.buttons["DashboardNav.settings"]
        XCTAssertTrue(settingsButton.waitForExistence(timeout: 5))
        settingsButton.click()

        let claudeButton = app.buttons["ProviderDirectoryAction.claude"]
        let buttonReady = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "exists == true AND enabled == true"),
            object: claudeButton
        )
        XCTAssertEqual(
            XCTWaiter.wait(for: [buttonReady], timeout: 5),
            .completed
        )
        claudeButton.click()

        let panelMessageText = "Choose the Claude Code data folder"
        let panelMessage = app.staticTexts.matching(
            NSPredicate(
                format: "label == %@ OR value == %@",
                panelMessageText,
                panelMessageText
            )
        ).firstMatch
        XCTAssertTrue(panelMessage.waitForExistence(timeout: 5))
        XCTAssertEqual(app.windows.count, 2)

        app.typeKey(.escape, modifierFlags: [])
        XCTAssertTrue(panelMessage.waitForNonExistence(timeout: 2))

        let buttonReadyAfterCancellation = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "exists == true AND enabled == true"),
            object: claudeButton
        )
        XCTAssertEqual(
            XCTWaiter.wait(for: [buttonReadyAfterCancellation], timeout: 5),
            .completed
        )
        XCTAssertEqual(app.windows.count, 1)

        for (id, providerName) in [
            ("claude", "Claude Code"),
            ("codex", "Codex"),
            ("opencode", "opencode"),
        ] {
            let action = app.buttons["ProviderDirectoryAction.\(id)"]
            XCTAssertTrue(action.exists)
            XCTAssertEqual(
                action.label,
                "\(providerName), Authorize"
            )
        }
    }
}

extension XCUIApplication {
    func launchForUITesting(
        languagePreference: String = "zh-Hans",
        skipInitialDirectoryAuthorizationGuide: Bool = true
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
        launch()
    }
}
