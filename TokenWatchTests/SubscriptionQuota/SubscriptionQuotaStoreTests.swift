import Foundation
import Testing
@testable import TokenWatch

@MainActor
@Suite("SubscriptionQuotaStore")
struct SubscriptionQuotaStoreTests {

    @Test("两个来源都未授权时各自显示未授权，不读取任何文件")
    func unauthorizedSourcesStayIndependent() async {
        let bookmarks = FakeQuotaBookmarks()
        let store = makeStore(bookmarks: bookmarks)

        await store.refresh()

        #expect(store.state(for: .claude) == SubscriptionQuotaProviderState(result: .notAuthorized, lastReadFailed: false))
        #expect(store.state(for: .codex) == SubscriptionQuotaProviderState(result: .notAuthorized, lastReadFailed: false))
        #expect(bookmarks.restoredKeys.isEmpty)
    }

    @Test("Claude 读取失败时保留最后有效快照并标记失败，另一个工具不受影响")
    func failedReadKeepsLastSnapshot() async throws {
        let fixture = try QuotaFixture()
        defer { fixture.remove() }
        try fixture.writeClaudeConfig(used: 40, fetchedAtMs: 1_000_000, modificationDate: Date(timeIntervalSince1970: 100))
        let bookmarks = FakeQuotaBookmarks()
        bookmarks.urls[SubscriptionQuotaStore.claudeQuotaFileBookmarkKey] = fixture.claudeConfigURL
        let store = makeStore(bookmarks: bookmarks)

        await store.refresh()
        let first = store.state(for: .claude)
        guard case .snapshot(let snapshot) = first.result else {
            Issue.record("Expected Claude snapshot, got \(first)")
            return
        }
        #expect(snapshot.windows[.fiveHour]?.usedPercent == 40)
        #expect(!first.lastReadFailed)

        try Data(#"{"cachedUsageUtilization": {"fetchedAt"#.utf8).write(to: fixture.claudeConfigURL)
        try FileManager.default.setAttributes(
            [.modificationDate: Date(timeIntervalSince1970: 200)],
            ofItemAtPath: fixture.claudeConfigURL.path
        )
        await store.refresh()

        #expect(store.state(for: .claude) == SubscriptionQuotaProviderState(result: first.result, lastReadFailed: true))
        #expect(store.state(for: .codex).result == .notAuthorized)
        // 每轮刷新都成对释放 security-scoped 访问。
        #expect(bookmarks.activeAccessCount == 0)
    }

    @Test("成功读取到另一账号或无记录时替换旧值，不跨账号沿用最后成功值")
    func successfulReadReplacesPreviousAccount() async throws {
        let fixture = try QuotaFixture()
        defer { fixture.remove() }
        try fixture.writeClaudeConfig(used: 40, fetchedAtMs: 1_000_000, modificationDate: Date(timeIntervalSince1970: 100))
        let bookmarks = FakeQuotaBookmarks()
        bookmarks.urls[SubscriptionQuotaStore.claudeQuotaFileBookmarkKey] = fixture.claudeConfigURL
        let store = makeStore(bookmarks: bookmarks)
        await store.refresh()

        try fixture.writeClaudeConfig(
            used: 40,
            fetchedAtMs: 1_000_000,
            cacheAccountID: "account-old",
            currentAccountID: "account-new",
            modificationDate: Date(timeIntervalSince1970: 200)
        )
        await store.refresh()

        #expect(store.state(for: .claude) == SubscriptionQuotaProviderState(result: .noRecord, lastReadFailed: false))
    }

    @Test("内容未变化的刷新不通知 observer")
    func unchangedRefreshDoesNotNotify() async throws {
        let fixture = try QuotaFixture()
        defer { fixture.remove() }
        try fixture.writeClaudeConfig(used: 10, fetchedAtMs: 1_000_000, modificationDate: Date(timeIntervalSince1970: 100))
        let bookmarks = FakeQuotaBookmarks()
        bookmarks.urls[SubscriptionQuotaStore.claudeQuotaFileBookmarkKey] = fixture.claudeConfigURL
        let store = makeStore(bookmarks: bookmarks)
        var notifications = 0
        store.observe { notifications += 1 }

        await store.refresh()
        await store.refresh()

        #expect(notifications == 1)
    }

    @Test("Codex 复用已授权数据目录读取 rollout 额度")
    func codexUsesExistingDirectoryBookmark() async throws {
        let fixture = try QuotaFixture()
        defer { fixture.remove() }
        try fixture.writeCodexRollout(used: 12)
        let bookmarks = FakeQuotaBookmarks()
        bookmarks.urls[CodexProvider.dataDirectoryBookmarkKey] = fixture.codexRoot
        let store = makeStore(bookmarks: bookmarks)

        await store.refresh()

        guard case .snapshot(let snapshot) = store.state(for: .codex).result else {
            Issue.record("Expected Codex snapshot")
            return
        }
        #expect(snapshot.windows[.fiveHour]?.usedPercent == 12)
        #expect(store.state(for: .claude).result == .notAuthorized)
    }

    @Test("选择 Claude 额度文件：取消不保存，确认后保存单文件 bookmark 并刷新")
    func claudeFileAuthorizationPersistsBookmark() async throws {
        let fixture = try QuotaFixture()
        defer { fixture.remove() }
        try fixture.writeClaudeConfig(used: 25, fetchedAtMs: 1_000_000, modificationDate: Date(timeIntervalSince1970: 100))
        let bookmarks = FakeQuotaBookmarks()
        let panel = FakeClaudeQuotaFilePanel()
        let store = makeStore(bookmarks: bookmarks, panel: panel)

        panel.nextURL = nil
        #expect(!(await store.requestClaudeFileAuthorization()))
        #expect(bookmarks.persistedKeys.isEmpty)

        panel.nextURL = fixture.claudeConfigURL
        #expect(await store.requestClaudeFileAuthorization())
        #expect(bookmarks.persistedKeys == [SubscriptionQuotaStore.claudeQuotaFileBookmarkKey])
        guard case .snapshot(let snapshot) = store.state(for: .claude).result else {
            Issue.record("Expected Claude snapshot after authorization")
            return
        }
        #expect(snapshot.windows[.fiveHour]?.usedPercent == 25)
    }

    @Test("Demo 模式使用确定性额度")
    func demoModeUsesDeterministicQuota() async {
        let store = makeStore(bookmarks: FakeQuotaBookmarks(), isDemoMode: true)

        await store.refresh()

        guard case .snapshot(let claude) = store.state(for: .claude).result,
              case .snapshot(let codex) = store.state(for: .codex).result else {
            Issue.record("Expected demo snapshots")
            return
        }
        #expect(claude.windows[.fiveHour]?.remainingPercent == 68)
        #expect(claude.windows[.sevenDay]?.remainingPercent == 86)
        #expect(codex.windows[.fiveHour]?.remainingPercent == 88)
        #expect(codex.windows[.sevenDay]?.remainingPercent == 98)
    }

    private func makeStore(
        bookmarks: FakeQuotaBookmarks,
        panel: FakeClaudeQuotaFilePanel? = nil,
        isDemoMode: Bool = false
    ) -> SubscriptionQuotaStore {
        SubscriptionQuotaStore(
            bookmarkManager: bookmarks,
            filePanelPresenter: panel ?? FakeClaudeQuotaFilePanel(),
            languageProvider: { .zhHans },
            isDemoModeEnabled: { isDemoMode },
            nowProvider: { Date(timeIntervalSince1970: 1_793_170_000) }
        )
    }
}

@MainActor
private final class FakeQuotaBookmarks: SubscriptionQuotaBookmarkAccessing {
    var urls: [String: URL] = [:]
    private(set) var restoredKeys: [String] = []
    private(set) var persistedKeys: [String] = []
    private(set) var activeAccessCount = 0

    func hasBookmark(forKey key: String) -> Bool {
        urls[key] != nil
    }

    func restoreBookmarkAndAccess(forKey key: String) -> URL? {
        restoredKeys.append(key)
        guard let url = urls[key] else { return nil }
        activeAccessCount += 1
        return url
    }

    func stopAccessing(forKey key: String) {
        activeAccessCount -= 1
    }

    func persistSelectedDirectory(_ url: URL, forKey key: String) -> Bool {
        persistedKeys.append(key)
        urls[key] = url
        return true
    }
}

@MainActor
private final class FakeClaudeQuotaFilePanel: ClaudeQuotaFilePanelPresenting {
    var nextURL: URL?

    func chooseClaudeConfigFile(language: AppLanguage) async -> URL? {
        nextURL
    }
}

private struct QuotaFixture {
    let root: URL
    var claudeConfigURL: URL { root.appendingPathComponent(".claude.json") }
    var codexRoot: URL { root.appendingPathComponent("codex", isDirectory: true) }

    init() throws {
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("SubscriptionQuotaStoreTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    func remove() {
        try? FileManager.default.removeItem(at: root)
    }

    func writeClaudeConfig(
        used: Double,
        fetchedAtMs: Int,
        cacheAccountID: String? = nil,
        currentAccountID: String? = nil,
        modificationDate: Date
    ) throws {
        let cacheAccount = cacheAccountID.map { #""accountUuid": "\#($0)","# } ?? ""
        let currentAccount = currentAccountID.map { #", "oauthAccount": {"accountUuid": "\#($0)"}"# } ?? ""
        let json = #"{"cachedUsageUtilization": {\#(cacheAccount)"fetchedAtMs": \#(fetchedAtMs), "utilization": {"five_hour": {"utilization": \#(used), "resets_at": null}}}\#(currentAccount)}"#
        try Data(json.utf8).write(to: claudeConfigURL)
        try FileManager.default.setAttributes([.modificationDate: modificationDate], ofItemAtPath: claudeConfigURL.path)
    }

    func writeCodexRollout(used: Double) throws {
        let directory = codexRoot.appendingPathComponent("sessions/2026/10/28", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let lines = [
            #"{"timestamp":"2026-10-28T05:00:00.000Z","type":"session_meta","payload":{"id":"s","creator_account_id":"account-a"}}"#,
            #"{"timestamp":"2026-10-28T06:00:00.000Z","type":"event_msg","payload":{"type":"token_count","info":null,"rate_limits":{"limit_id":"codex","primary":{"used_percent":\#(used),"window_minutes":300,"resets_at":1793188826},"secondary":null}}}"#,
        ]
        try Data((lines.joined(separator: "\n") + "\n").utf8).write(
            to: directory.appendingPathComponent("rollout-2026-10-28T10-00-00-00000000-0000-0000-0000-000000000001.jsonl")
        )
    }
}
