//
//  TokenWatchUITestsLaunchTests.swift
//  TokenWatchUITests
//
//  Created by OrrHsiao on 2026/6/13.
//

import XCTest

final class TokenWatchUITestsLaunchTests: XCTestCase {

    override class var runsForEachTargetApplicationUIConfiguration: Bool {
        true
    }

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testLaunch() throws {
        let app = XCUIApplication()
        app.launchForUITesting(languagePreference: "en")

        XCTAssertTrue(app.windows.firstMatch.waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Usage Overview"].waitForExistence(timeout: 5))
        XCTAssertFalse(
            app.windows.element(boundBy: 1).waitForExistence(timeout: 2)
        )
        XCTAssertEqual(app.windows.count, 1)

        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = "Launch Screen"
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
