//
//  AppStoreScreenshotUITests.swift
//  TokenWatchUITests
//
//  Created for automated App Store screenshot generation.
//

import XCTest

final class AppStoreScreenshotUITests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testCaptureAppStoreScreenshotsZhHans() throws {
        try captureScreenshots(
            languagePreference: "zh-CN",
            systemLanguage: "zh-CN",
            localeDir: "zh-Hans"
        )
    }

    @MainActor
    func testCaptureAppStoreScreenshotsEnUS() throws {
        try captureScreenshots(
            languagePreference: "en",
            systemLanguage: "en",
            localeDir: "en-US"
        )
    }

    @MainActor
    private func captureScreenshots(
        languagePreference: String,
        systemLanguage: String,
        localeDir: String
    ) throws {
        let app = XCUIApplication()
        app.launchForUITesting(
            languagePreference: languagePreference,
            skipInitialDirectoryAuthorizationGuide: true,
            systemLanguage: systemLanguage,
            widgetPurchaseReviewMode: "unlocked",
            useDemoData: true,
            showPopoverForScreenshots: true
        )

        let targetDir = outputDirectory(for: localeDir)
        try FileManager.default.createDirectory(at: targetDir, withIntermediateDirectories: true)

        // 0. Status Popover
        let popoverWindow = app.windows["StatusPopoverWindow"]
        if popoverWindow.waitForExistence(timeout: 8) {
            Thread.sleep(forTimeInterval: 0.8)
            try saveWindowScreenshot(popoverWindow, named: "01-menu-bar-popover.png", in: targetDir)
            popoverWindow.typeKey("w", modifierFlags: .command)
            Thread.sleep(forTimeInterval: 0.3)
        }

        let mainWindow = app.windows["TokenWatchMainWindow"].exists ? app.windows["TokenWatchMainWindow"] : app.windows.firstMatch
        XCTAssertTrue(mainWindow.waitForExistence(timeout: 10))

        // 1. Overview Tab
        let overviewButton = app.buttons["DashboardNav.overview"]
        if overviewButton.waitForExistence(timeout: 5) {
            overviewButton.click()
            Thread.sleep(forTimeInterval: 0.5)
            try saveWindowScreenshot(mainWindow, named: "02-overview.png", in: targetDir)
        }

        // 2. Sessions Tab
        let sessionsButton = app.buttons["DashboardNav.sessions"]
        if sessionsButton.waitForExistence(timeout: 5) {
            sessionsButton.click()
            Thread.sleep(forTimeInterval: 0.5)
            try saveWindowScreenshot(mainWindow, named: "03-sessions.png", in: targetDir)
        }

        // 3. Widgets Tab
        let widgetsButton = app.buttons["DashboardNav.widgets"]
        if widgetsButton.waitForExistence(timeout: 5) {
            widgetsButton.click()
            Thread.sleep(forTimeInterval: 0.5)
            try saveWindowScreenshot(mainWindow, named: "04-widgets.png", in: targetDir)
        }
    }

    @MainActor
    private func saveWindowScreenshot(_ element: XCUIElement, named fileName: String, in directory: URL) throws {
        let screenshot = element.screenshot()
        let fileURL = directory.appendingPathComponent(fileName)
        try screenshot.pngRepresentation.write(to: fileURL, options: .atomic)

        let attachment = XCTAttachment(screenshot: screenshot)
        attachment.name = fileName
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    private func outputDirectory(for locale: String) -> URL {
        if let customPath = ProcessInfo.processInfo.environment["TOKENWATCH_SCREENSHOT_DIR"] {
            return URL(fileURLWithPath: customPath).appendingPathComponent(locale)
        }
        let tempBase = FileManager.default.temporaryDirectory.appendingPathComponent("tokenwatch_screenshots/raw")
        return tempBase.appendingPathComponent(locale)
    }
}
