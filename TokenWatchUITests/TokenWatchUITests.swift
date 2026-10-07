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

    /// 会话表宽度不小于视口：默认窗口下两者相等（内容恰好铺满），窗口更窄时内容溢出。
    /// 这里只断言默认窗口下的两条不变量——分页控件贴着表格右缘且完整可见（等价于
    /// 「表格铺满视口、没有把分页顶到滚动区外」），以及不存在无法观察的「假滚动」。
    /// 表格恰好铺满视口时横向滚动范围为零，因此不能再要求「滚动必须移动内容」。
    @MainActor
    func testSessionTableFitsViewportWithoutHorizontalScroll() throws {
        let app = XCUIApplication()
        app.launchForUITesting()

        let sessionsButton = app.buttons["DashboardNav.sessions"]
        XCTAssertTrue(sessionsButton.waitForExistence(timeout: 5))
        sessionsButton.click()

        let tableScrollView = app.scrollViews["DashboardSessionsTableScrollView"]
        XCTAssertTrue(tableScrollView.waitForExistence(timeout: 5))

        let nextButton = app.buttons["DashboardSessionsPagination.next"]
        XCTAssertTrue(nextButton.waitForExistence(timeout: 5))

        let viewportFrame = tableScrollView.frame
        // 分页控件右对齐并距表格右缘 16pt：按钮右缘贴住视口右缘，说明表格宽度与视口一致。
        XCTAssertLessThanOrEqual(
            nextButton.frame.maxX,
            viewportFrame.maxX + 1,
            "分页按钮超出可见区，说明表格比视口宽"
        )
        XCTAssertGreaterThan(
            nextButton.frame.maxX,
            viewportFrame.maxX - 40,
            "分页按钮离视口右缘过远，说明表格比视口窄"
        )

        // 横向滚动不应移动内容：内容恰好铺满视口时没有可观察的滚动范围。
        let initialMinX = nextButton.frame.minX
        tableScrollView.scroll(byDeltaX: -400, deltaY: 0)
        var shiftedMinX = nextButton.frame.minX
        if shiftedMinX >= initialMinX - 1 {
            tableScrollView.scroll(byDeltaX: 400, deltaY: 0)
            shiftedMinX = nextButton.frame.minX
        }
        XCTAssertEqual(shiftedMinX, initialMinX, accuracy: 1)
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

    @MainActor
    func testWidgetPurchaseReviewCardShowsStorePriceAndRestoreAction() throws {
        let app = XCUIApplication()
        app.launchForUITesting(
            languagePreference: "en",
            widgetPurchaseReviewMode: "locked"
        )

        let widgetsButton = app.buttons["DashboardNav.widgets"]
        XCTAssertTrue(widgetsButton.waitForExistence(timeout: 5))
        widgetsButton.click()

        XCTAssertTrue(app.groups["WidgetPurchaseCard"].waitForExistence(timeout: 5))
        XCTAssertTrue(
            app.staticTexts["Unlock all 7 desktop widgets"]
                .waitForExistence(timeout: 5)
        )
        let purchaseButton = app.buttons["WidgetPurchaseButton"]
        let pricedButton = XCTNSPredicateExpectation(
            predicate: NSPredicate(
                format: "exists == true AND enabled == true AND label == %@",
                "Unlock forever for $2.99"
            ),
            object: purchaseButton
        )
        XCTAssertEqual(XCTWaiter.wait(for: [pricedButton], timeout: 5), .completed)
        XCTAssertEqual(
            app.buttons["WidgetRestorePurchaseButton"].label,
            "Restore Purchases"
        )

        // Element screenshots are cropped to the app window on macOS; app-level screenshots
        // otherwise include the whole desktop and can leak unrelated windows into review evidence.
        let reviewWindow = app.windows.firstMatch
        XCTAssertTrue(reviewWindow.exists)
        let screenshot = reviewWindow.screenshot()
        let attachment = XCTAttachment(screenshot: screenshot)
        attachment.name = "Widget lifetime purchase review"
        attachment.lifetime = .keepAlways
        add(attachment)

        if let outputPath = ProcessInfo.processInfo.environment[
            "TOKENWATCH_IAP_REVIEW_SCREENSHOT_PATH"
        ] {
            try screenshot.pngRepresentation.write(
                to: URL(fileURLWithPath: outputPath),
                options: .atomic
            )
        }
    }

    @MainActor
    func testWidgetPurchaseUnlockedStateHidesPurchaseActions() throws {
        let app = XCUIApplication()
        app.launchForUITesting(
            languagePreference: "en",
            widgetPurchaseReviewMode: "unlocked"
        )

        let widgetsButton = app.buttons["DashboardNav.widgets"]
        XCTAssertTrue(widgetsButton.waitForExistence(timeout: 5))
        widgetsButton.click()

        XCTAssertTrue(app.groups["WidgetPurchaseCard"].waitForExistence(timeout: 5))
        XCTAssertTrue(
            app.staticTexts["All widgets are unlocked"]
                .waitForExistence(timeout: 5)
        )
        XCTAssertFalse(app.buttons["WidgetPurchaseButton"].exists)
        XCTAssertFalse(app.buttons["WidgetRestorePurchaseButton"].exists)
    }
}

extension XCUIApplication {
    func launchForUITesting(
        languagePreference: String = "zh-CN",
        skipInitialDirectoryAuthorizationGuide: Bool = true,
        systemLanguage: String? = nil,
        widgetPurchaseReviewMode: String? = nil
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
        if let widgetPurchaseReviewMode {
            launchArguments += [
                "-TokenWatch.widgetPurchaseReviewMode", widgetPurchaseReviewMode,
            ]
        }
        launch()
    }
}
