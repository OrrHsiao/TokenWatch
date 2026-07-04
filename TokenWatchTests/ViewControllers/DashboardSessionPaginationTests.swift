import AppKit
import Testing
@testable import TokenWatch

@Suite("Dashboard Session Pagination")
struct DashboardSessionPaginationTests {

    @Test("分页模型按 10 条一页计算当前范围")
    func paginationCalculatesVisibleRange() {
        let pagination = RecentSessionPagination(totalCount: 47, pageSize: 10, currentPage: 3)

        #expect(pagination.totalPages == 5)
        #expect(pagination.currentPage == 3)
        #expect(pagination.rowRange == 20..<30)
        #expect(pagination.displayRangeText == "显示 21-30 / 共 47 个会话")
        #expect(pagination.displayRangeText(language: .en) == "Showing 21-30 of 47 sessions")
        #expect(pagination.canGoPrevious)
        #expect(pagination.canGoNext)
    }

    @Test("分页模型按设计稿折叠页码")
    func paginationItemsCollapseLikeDesign() {
        let firstPage = RecentSessionPagination(totalCount: 1_284, pageSize: 10, currentPage: 1)
        let middlePage = RecentSessionPagination(totalCount: 1_284, pageSize: 10, currentPage: 65)
        let lastPage = RecentSessionPagination(totalCount: 1_284, pageSize: 10, currentPage: 129)

        #expect(firstPage.items == [.page(1), .page(2), .page(3), .ellipsis, .page(129)])
        #expect(firstPage.displayRangeText == "显示 1-10 / 共 1,284 个会话")
        #expect(middlePage.items == [.page(1), .ellipsis, .page(64), .page(65), .page(66), .ellipsis, .page(129)])
        #expect(lastPage.items == [.page(1), .ellipsis, .page(127), .page(128), .page(129)])
    }

    @MainActor
    @Test("会话页每页展示 10 条并用下一页按钮展示后续会话")
    func dashboardNextButtonShowsNextSessionPage() throws {
        let now = dateTime(2026, 7, 4, hour: 12, minute: 0)
        let languageSettings = zhHansLanguageSettings()
        let controller = DashboardViewController(
            settingsViewController: settingsViewController(languageSettings: languageSettings),
            stateProvider: { [
                .claude: .init(
                    stats: nil,
                    entries: makeEntries(count: 12, now: now),
                    isLoading: false,
                    errorMessage: nil,
                    needsAuthorization: false
                ),
            ] },
            nowProvider: { now },
            calendar: calendar(),
            languageSettings: languageSettings
        )

        controller.loadViewIfNeeded()
        try button(withIdentifier: "DashboardNav.sessions", in: controller.view).performClick(nil)

        let rangeLabel = try textField(withIdentifier: "DashboardSessionsPaginationRange", in: controller.view)
        #expect(rangeLabel.stringValue == "显示 1-10 / 共 12 个会话")
        #expect(visibleValues(in: controller.view).contains("session-01"))
        #expect(!visibleValues(in: controller.view).contains("session-11"))

        try button(withIdentifier: "DashboardSessionsPagination.next", in: controller.view).performClick(nil)

        #expect(rangeLabel.stringValue == "显示 11-12 / 共 12 个会话")
        #expect(visibleValues(in: controller.view).contains("session-11"))
        #expect(!visibleValues(in: controller.view).contains("session-01"))
    }

    @MainActor
    @Test("会话行短显 ID、复制完整 ID，并展示具体工具与有效项目")
    func dashboardSessionRowDisplaysCompactIDCopiesFullIDAndCleansProject() throws {
        let now = dateTime(2026, 7, 4, hour: 12, minute: 0)
        let fullSessionID = "019df220-aaaa-bbbb-cccc-ddddeeeeffff"
        let languageSettings = zhHansLanguageSettings()
        let controller = DashboardViewController(
            settingsViewController: settingsViewController(languageSettings: languageSettings),
            stateProvider: { [
                .claude: .init(
                    stats: nil,
                    entries: [
                        makeEntry(
                            sessionID: fullSessionID,
                            timestamp: dateTime(2026, 7, 4, hour: 10, minute: 0),
                            inputTokens: 120,
                            cwd: "/Users/orrhsiao/.pencil/documents/687dce51-3ca3-4a6a-86db-814dae59f68d"
                        ),
                    ],
                    isLoading: false,
                    errorMessage: nil,
                    needsAuthorization: false
                ),
            ] },
            nowProvider: { now },
            calendar: calendar(),
            languageSettings: languageSettings
        )

        controller.loadViewIfNeeded()
        try button(withIdentifier: "DashboardNav.sessions", in: controller.view).performClick(nil)
        controller.view.layoutSubtreeIfNeeded()

        let row = try #require(findView(withIdentifier: "DashboardSessionsRow.0", in: controller.view))
        let rowLabels = textValues(in: row)
        let copyButton = try button(withIdentifier: "DashboardSessionsCopy.0", in: row)
        let toolLabel = try textField(withString: "Claude Code", in: row)
        let toolAncestorViews = ancestorViews(from: toolLabel, stoppingBefore: row)
        let toolAncestors = toolAncestorViews.map { String(describing: type(of: $0)) }
        #expect(copyButton.title == "019df220...eeeffff")
        #expect(copyButton.image != nil)
        #expect(!rowLabels.contains(fullSessionID))
        #expect(rowLabels.contains("Claude Code"))
        #expect(toolLabel.frame.width >= toolLabel.fittingSize.width)
        #expect(!toolAncestors.contains { $0.contains("DashboardRoundedView") })
        #expect(!toolAncestorViews.contains { ($0.layer?.cornerRadius ?? 0) > 0 })
        #expect(!toolAncestorViews.contains { ($0.layer?.borderWidth ?? 0) > 0 })
        #expect(rowLabels.contains("unknown"))
        #expect(!rowLabels.contains("687dce51-3ca3-4a6a-86db-814dae59f68d"))

        NSPasteboard.general.clearContents()
        copyButton.performClick(nil)
        #expect(NSPasteboard.general.string(forType: .string) == fullSessionID)
    }

    @MainActor
    @Test("会话页只展示选中日期当天的全部会话")
    func dashboardSessionsOnlyUseSelectedDayEntries() throws {
        let now = dateTime(2026, 7, 4, hour: 12, minute: 0)
        let languageSettings = zhHansLanguageSettings()
        let controller = DashboardViewController(
            settingsViewController: settingsViewController(languageSettings: languageSettings),
            stateProvider: { [
                .claude: .init(
                    stats: nil,
                    entries: [
                        makeEntry(
                            sessionID: "same-session",
                            timestamp: dateTime(2026, 7, 4, hour: 10, minute: 0),
                            inputTokens: 120
                        ),
                        makeEntry(
                            sessionID: "same-session",
                            timestamp: dateTime(2026, 7, 3, hour: 23, minute: 0),
                            inputTokens: 900
                        ),
                        makeEntry(
                            sessionID: "today-only",
                            timestamp: dateTime(2026, 7, 4, hour: 9, minute: 0),
                            inputTokens: 80
                        ),
                        makeEntry(
                            sessionID: "yesterday-only",
                            timestamp: dateTime(2026, 7, 3, hour: 9, minute: 0),
                            inputTokens: 70
                        ),
                    ],
                    isLoading: false,
                    errorMessage: nil,
                    needsAuthorization: false
                ),
            ] },
            nowProvider: { now },
            calendar: calendar(),
            languageSettings: languageSettings
        )

        controller.loadViewIfNeeded()
        try button(withIdentifier: "DashboardNav.sessions", in: controller.view).performClick(nil)

        let labels = visibleValues(in: controller.view)
        #expect(labels.contains("same-session"))
        #expect(labels.contains("today-only"))
        #expect(!labels.contains("yesterday-only"))
        #expect(labels.contains("2"))
        #expect(labels.contains("200"))
        #expect(!labels.contains("1.2k"))
    }

    @MainActor
    private func button(withIdentifier identifier: String, in root: NSView) throws -> NSButton {
        let view = try #require(findView(withIdentifier: identifier, in: root))
        return try #require(view as? NSButton)
    }

    @MainActor
    private func textField(withIdentifier identifier: String, in root: NSView) throws -> NSTextField {
        let view = try #require(findView(withIdentifier: identifier, in: root))
        return try #require(view as? NSTextField)
    }

    @MainActor
    private func textField(withString value: String, in root: NSView) throws -> NSTextField {
        try #require(findTextField(withString: value, in: root))
    }

    @MainActor
    private func findTextField(withString value: String, in root: NSView) -> NSTextField? {
        if let textField = root as? NSTextField, textField.stringValue == value {
            return textField
        }
        for subview in root.subviews {
            if let match = findTextField(withString: value, in: subview) {
                return match
            }
        }
        return nil
    }

    @MainActor
    private func findView(withIdentifier identifier: String, in root: NSView) -> NSView? {
        if root.accessibilityIdentifier() == identifier || root.identifier?.rawValue == identifier {
            return root
        }
        for subview in root.subviews {
            if let match = findView(withIdentifier: identifier, in: subview) {
                return match
            }
        }
        return nil
    }

    @MainActor
    private func textValues(in root: NSView) -> [String] {
        var values: [String] = []
        if let textField = root as? NSTextField {
            values.append(textField.stringValue)
        }
        for subview in root.subviews {
            values.append(contentsOf: textValues(in: subview))
        }
        return values
    }

    @MainActor
    private func ancestorViews(from view: NSView, stoppingBefore root: NSView) -> [NSView] {
        var views: [NSView] = []
        var current = view.superview
        while let candidate = current, candidate !== root {
            views.append(candidate)
            current = candidate.superview
        }
        return views
    }

    @MainActor
    private func visibleValues(in root: NSView) -> [String] {
        var values: [String] = []
        if let textField = root as? NSTextField {
            values.append(textField.stringValue)
        }
        if let button = root as? NSButton, !button.title.isEmpty {
            values.append(button.title)
        }
        for subview in root.subviews {
            values.append(contentsOf: visibleValues(in: subview))
        }
        return values
    }

    private func makeEntries(count: Int, now: Date) -> [ParsedUsageEntry] {
        (1...count).map { index in
            makeEntry(
                sessionID: String(format: "session-%02d", index),
                timestamp: now.addingTimeInterval(TimeInterval(-(index - 1) * 60)),
                inputTokens: index,
                cwd: "/tmp/project-\(index)",
                recordSuffix: "\(index)"
            )
        }
    }

    private func makeEntry(
        sessionID: String,
        timestamp: Date,
        inputTokens: Int,
        cwd: String = "/tmp/project",
        recordSuffix: String? = nil
    ) -> ParsedUsageEntry {
        let suffix = recordSuffix ?? "\(sessionID)-\(Int(timestamp.timeIntervalSince1970))-\(inputTokens)"
        return ParsedUsageEntry(
            recordUUID: "record-\(suffix)",
            messageId: "message-\(suffix)",
            requestId: nil,
            sessionID: sessionID,
            timestamp: timestamp,
            model: "test-model",
            cwd: cwd,
            agentId: nil,
            usage: TokenUsage(
                inputTokens: inputTokens,
                cacheCreationInputTokens: 0,
                cacheReadInputTokens: 0,
                outputTokens: 0,
                reasoningTokens: 0,
                serverToolUse: ServerToolUse(webSearchRequests: 0, webFetchRequests: 0),
                serviceTier: "",
                cacheCreation: CacheCreation(ephemeral1hInputTokens: 0, ephemeral5mInputTokens: 0),
                inferenceGeo: "",
                iterations: [],
                speed: ""
            ),
            isSubagent: false,
            provider: .claude,
            upstreamProviderID: nil,
            upstreamCost: nil
        )
    }

    private func dateTime(_ year: Int, _ month: Int, _ day: Int, hour: Int, minute: Int) -> Date {
        DateComponents(
            calendar: Self.calendar(),
            timeZone: TimeZone(secondsFromGMT: 0),
            year: year,
            month: month,
            day: day,
            hour: hour,
            minute: minute
        ).date!
    }

    private static func calendar() -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }

    private func calendar() -> Calendar {
        Self.calendar()
    }

    private func temporaryDefaults() -> UserDefaults {
        let suiteName = "DashboardSessionPaginationTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        return defaults
    }

    @MainActor
    private func zhHansLanguageSettings() -> AppLanguageSettings {
        AppLanguageSettings(defaults: temporaryDefaults(), preferredLanguagesProvider: { ["zh-Hans-US"] })
    }

    @MainActor
    private func settingsViewController(languageSettings: AppLanguageSettings) -> SettingsViewController {
        SettingsViewController(
            isAuthorized: { true },
            autoRefreshSettings: AutoRefreshSettings(defaults: temporaryDefaults()),
            languageSettings: languageSettings
        )
    }
}
