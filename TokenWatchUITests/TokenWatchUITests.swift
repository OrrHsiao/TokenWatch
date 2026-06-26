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
    func testLaunchShowsSidebarAndTotalPage() throws {
        let app = XCUIApplication()
        app.launchForUITesting()

        XCTAssertTrue(app.windows.element(boundBy: 0).waitForExistence(timeout: 5))
        let sidebar = app.tables["MainSidebarTableView"]
        XCTAssertTrue(sidebar.waitForExistence(timeout: 5))
        XCTAssertTrue(sidebar.staticTexts["Total"].exists)
        XCTAssertTrue(sidebar.staticTexts["Last 12 Months"].exists)
        XCTAssertTrue(sidebar.staticTexts["Last 30 Days"].exists)
        XCTAssertTrue(sidebar.staticTexts["Today"].exists)
        XCTAssertTrue(sidebar.staticTexts["Settings"].exists)
        XCTAssertTrue(app.staticTexts["Model Usage"].waitForExistence(timeout: 5))
    }

    @MainActor
    func testSidebarNavigationShowsTimeWindowPages() throws {
        let app = XCUIApplication()
        app.launchForUITesting()

        let sidebar = app.tables["MainSidebarTableView"]
        XCTAssertTrue(sidebar.waitForExistence(timeout: 5))

        sidebar.staticTexts["Last 12 Months"].click()
        XCTAssertTrue(app.staticTexts["Last 12 Months"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Token Usage"].exists)

        sidebar.staticTexts["Last 30 Days"].click()
        XCTAssertTrue(app.staticTexts["Last 30 Days"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Token Usage"].exists)

        sidebar.staticTexts["Today"].click()
        XCTAssertTrue(app.staticTexts["Today"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Token Usage"].exists)
    }

    @MainActor
    func testSettingsPageExposesActionControls() throws {
        let app = XCUIApplication()
        app.launchForUITesting()

        let sidebar = app.tables["MainSidebarTableView"]
        XCTAssertTrue(sidebar.waitForExistence(timeout: 5))
        sidebar.staticTexts["Settings"].click()

        XCTAssertTrue(app.staticTexts["General Access"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.descendants(matching: .any)["AuthorizationActionButton"].exists)
        XCTAssertTrue(app.descendants(matching: .any)["RefreshAllDataButton"].exists)
        XCTAssertTrue(app.descendants(matching: .any)["AutoRefreshIntervalPopUpButton"].exists)
        XCTAssertTrue(app.descendants(matching: .any)["LaunchAtLoginSwitch"].exists)
        XCTAssertTrue(app.descendants(matching: .any)["LanguagePreferencePopUpButton"].exists)
    }
}

extension XCUIApplication {
    func launchForUITesting(languagePreference: String = "en") {
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
