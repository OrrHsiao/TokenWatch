import Foundation
import Testing
@testable import TokenWatch

@MainActor
struct TokenStatsViewModelObserverTests {

    /// 多个 observer 都能收到通知
    @Test func multipleObserversAllReceiveNotification() async throws {
        let vm = TokenStatsViewModel()

        var firstReceived: [ProviderID] = []
        var secondReceived: [ProviderID] = []

        _ = vm.observe { id in firstReceived.append(id) }
        _ = vm.observe { id in secondReceived.append(id) }

        // 触发未授权路径,会同步 notify 一次
        await vm.loadStats(for: .claude)

        #expect(firstReceived.contains(.claude))
        #expect(secondReceived.contains(.claude))
    }

    /// removeObserver 之后该 observer 不再收到
    @Test func removedObserverStopsReceiving() async throws {
        let vm = TokenStatsViewModel()

        var received: [ProviderID] = []
        let token = vm.observe { id in received.append(id) }

        vm.removeObserver(token)

        await vm.loadStats(for: .claude)

        #expect(received.isEmpty)
    }

    /// 不同 observer 拿到的 token 不同(可独立移除)
    @Test func observeReturnsDistinctTokens() {
        let vm = TokenStatsViewModel()
        let t1 = vm.observe { _ in }
        let t2 = vm.observe { _ in }
        #expect(t1 != t2)
    }

    /// 用户目录授权是共享的:任一 provider 授权成功后,同 key 的其它 provider 也应退出未授权态
    @Test func sharedBookmarkAuthorizationUpdatesAllProviders() {
        let vm = TokenStatsViewModel()
        var received: [ProviderID] = []
        _ = vm.observe { id in received.append(id) }

        vm.markProvidersAuthorized(sharingBookmarkWith: ClaudeProvider())

        #expect(ProviderRegistry.allProviders.allSatisfy {
            vm.states[$0.id]?.needsAuthorization == false
        })
        #expect(Set(received) == Set(ProviderRegistry.allProviders.map(\.id)))
    }

    /// 同一 provider 已在刷新时,后续刷新请求应被挡掉;不同 provider 不互相影响
    @Test func providerLoadGateRejectsDuplicateInFlightLoads() {
        var gate = ProviderLoadGate()

        let firstClaudeEnter = gate.enter(.claude)
        let secondClaudeEnter = gate.enter(.claude)
        let codexEnter = gate.enter(.codex)

        #expect(firstClaudeEnter)
        #expect(!secondClaudeEnter)
        #expect(codexEnter)

        gate.leave(.claude)
        let thirdClaudeEnter = gate.enter(.claude)
        #expect(thirdClaudeEnter)
    }

    /// 用户可见错误信息应按当前语言生成,同时保留底层错误描述。
    @Test func localizedErrorMessagesUseAppStrings() {
        let error = StubLocalizedError(description: "disk read failed")

        #expect(TokenStatsViewModel.cannotAccessHomeMessage(language: .zhHans) == "无法访问用户目录,请重新授权")
        #expect(TokenStatsViewModel.cannotAccessHomeMessage(language: .en) == "Cannot access home folder. Please authorize again")
        #expect(TokenStatsViewModel.loadFailedMessage(error: error, language: .zhHans) == "数据加载失败: disk read failed")
        #expect(TokenStatsViewModel.loadFailedMessage(error: error, language: .en) == "Data load failed: disk read failed")
    }

    @Test func openCodeScannerErrorsUseAppLanguage() {
        let error = OpenCodeScannerError.openFailed(code: 14, message: "unable to open database file")

        #expect(
            TokenStatsViewModel.loadFailedMessage(error: error, language: .zhHans)
            == "数据加载失败: 无法打开 opencode.db (SQLite code=14): unable to open database file"
        )
        #expect(
            TokenStatsViewModel.loadFailedMessage(error: error, language: .en)
            == "Data load failed: Could not open opencode.db (SQLite code=14): unable to open database file"
        )
    }

    /// 静默刷新在数据未变化时不应重新聚合,也不应通知 UI 重绘。
    @Test func silentRefreshSkipsAggregationAndNotificationWhenEntriesAreUnchanged() async throws {
        let provider = StubUsageProvider(id: .claude)
        let bookmarkManager = StubBookmarkManager(rootURL: URL(fileURLWithPath: NSTemporaryDirectory()))
        let aggregator = CountingUsageAggregator()
        let vm = TokenStatsViewModel(
            providers: [provider],
            bookmarkManager: bookmarkManager,
            aggregator: aggregator
        )

        var received: [ProviderID] = []
        _ = vm.observe { id in received.append(id) }

        await vm.loadStats(for: .claude, mode: .silentIfUnchanged)

        #expect(aggregator.aggregateCallCount == 1)
        #expect(received == [.claude])

        received.removeAll()
        await vm.loadStats(for: .claude, mode: .silentIfUnchanged)

        #expect(aggregator.aggregateCallCount == 1)
        #expect(received.isEmpty)
    }

    /// cache creation 总量相同但 5m/1h 拆分变化时,计费会变化,静默刷新不能跳过聚合。
    @Test func silentRefreshReloadsWhenCacheCreationSplitChanges() async throws {
        let provider = MutableUsageProvider(
            id: .claude,
            usage: makeUsage(cacheCreation5m: 100, cacheCreation1h: 0)
        )
        let bookmarkManager = StubBookmarkManager(rootURL: URL(fileURLWithPath: NSTemporaryDirectory()))
        let aggregator = CountingUsageAggregator()
        let vm = TokenStatsViewModel(
            providers: [provider],
            bookmarkManager: bookmarkManager,
            aggregator: aggregator
        )

        var received: [ProviderID] = []
        _ = vm.observe { id in received.append(id) }

        await vm.loadStats(for: .claude, mode: .silentIfUnchanged)
        let firstCost = vm.states[.claude]?.stats?.overall.cost

        received.removeAll()
        provider.updateUsage(makeUsage(cacheCreation5m: 0, cacheCreation1h: 100))
        await vm.loadStats(for: .claude, mode: .silentIfUnchanged)
        let secondCost = vm.states[.claude]?.stats?.overall.cost

        #expect(aggregator.aggregateCallCount == 2)
        #expect(received == [.claude])
        #expect(firstCost != secondCost)
    }

    @Test func successfulLoadStoresLatestEntries() async throws {
        let provider = StubUsageProvider(id: .claude)
        let bookmarkManager = StubBookmarkManager(rootURL: URL(fileURLWithPath: NSTemporaryDirectory()))
        let aggregator = CountingUsageAggregator()
        let vm = TokenStatsViewModel(
            providers: [provider],
            bookmarkManager: bookmarkManager,
            aggregator: aggregator
        )

        await vm.loadStats(for: .claude)

        #expect(vm.states[.claude]?.entries?.count == 1)
        #expect(vm.states[.claude]?.entries?.first?.sessionID == "session-1")
        #expect(vm.states[.claude]?.stats != nil)
    }

    @Test func unchangedRefreshKeepsExistingEntries() async throws {
        let provider = StubUsageProvider(id: .claude)
        let bookmarkManager = StubBookmarkManager(rootURL: URL(fileURLWithPath: NSTemporaryDirectory()))
        let aggregator = CountingUsageAggregator()
        let vm = TokenStatsViewModel(
            providers: [provider],
            bookmarkManager: bookmarkManager,
            aggregator: aggregator
        )

        await vm.loadStats(for: .claude, mode: .silentIfUnchanged)
        let firstEntries = vm.states[.claude]?.entries

        await vm.loadStats(for: .claude, mode: .silentIfUnchanged)

        #expect(vm.states[.claude]?.entries == firstEntries)
        #expect(aggregator.aggregateCallCount == 1)
    }

    @Test func failedRefreshKeepsExistingEntries() async throws {
        let provider = FailingAfterFirstLoadProvider(id: .claude)
        let bookmarkManager = StubBookmarkManager(rootURL: URL(fileURLWithPath: NSTemporaryDirectory()))
        let aggregator = CountingUsageAggregator()
        let vm = TokenStatsViewModel(
            providers: [provider],
            bookmarkManager: bookmarkManager,
            aggregator: aggregator
        )

        await vm.loadStats(for: .claude)
        let firstEntries = vm.states[.claude]?.entries

        provider.failNextLoad()
        await vm.loadStats(for: .claude)

        #expect(vm.states[.claude]?.entries == firstEntries)
        #expect(vm.states[.claude]?.errorMessage != nil)
    }
}

private struct StubLocalizedError: LocalizedError {
    let description: String
    var errorDescription: String? { description }
}

private func makeUsage(cacheCreation5m: Int, cacheCreation1h: Int) -> TokenUsage {
    TokenUsage(
        inputTokens: 100,
        cacheCreationInputTokens: cacheCreation5m + cacheCreation1h,
        cacheReadInputTokens: 0,
        outputTokens: 50,
        serverToolUse: ServerToolUse(webSearchRequests: 0, webFetchRequests: 0),
        serviceTier: "standard",
        cacheCreation: CacheCreation(
            ephemeral1hInputTokens: cacheCreation1h,
            ephemeral5mInputTokens: cacheCreation5m
        ),
        inferenceGeo: "",
        iterations: [],
        speed: "standard"
    )
}

private struct StubUsageProvider: UsageProvider {
    let id: ProviderID
    let displayName = "Stub Provider"
    let bookmarkKey = "StubBookmark"
    let defaultDirectoryPath = NSTemporaryDirectory()
    let openPanelMessage = "Select a folder"
    let hasCacheWriteDimension = true
    let hasReasoningDimension = false

    func loadEntries(from rootURL: URL) throws -> [ParsedUsageEntry] {
        [makeEntry(id: id, usage: makeUsage(cacheCreation5m: 0, cacheCreation1h: 0))]
    }
}

private final class MutableUsageProvider: UsageProvider, @unchecked Sendable {
    let id: ProviderID
    let displayName = "Mutable Provider"
    let bookmarkKey = "MutableBookmark"
    let defaultDirectoryPath = NSTemporaryDirectory()
    let openPanelMessage = "Select a folder"
    let hasCacheWriteDimension = true
    let hasReasoningDimension = false

    private let lock = NSLock()
    private var usage: TokenUsage

    init(id: ProviderID, usage: TokenUsage) {
        self.id = id
        self.usage = usage
    }

    func updateUsage(_ usage: TokenUsage) {
        lock.lock()
        self.usage = usage
        lock.unlock()
    }

    func loadEntries(from rootURL: URL) throws -> [ParsedUsageEntry] {
        lock.lock()
        let usage = usage
        lock.unlock()
        return [makeEntry(id: id, usage: usage)]
    }
}

private final class FailingAfterFirstLoadProvider: UsageProvider, @unchecked Sendable {
    let id: ProviderID
    let displayName = "Failing Provider"
    let bookmarkKey = "FailingBookmark"
    let defaultDirectoryPath = NSTemporaryDirectory()
    let openPanelMessage = "Select a folder"
    let hasCacheWriteDimension = true
    let hasReasoningDimension = false

    private let lock = NSLock()
    private var shouldFail = false

    init(id: ProviderID) {
        self.id = id
    }

    func failNextLoad() {
        lock.lock()
        shouldFail = true
        lock.unlock()
    }

    func loadEntries(from rootURL: URL) throws -> [ParsedUsageEntry] {
        lock.lock()
        let fail = shouldFail
        shouldFail = false
        lock.unlock()

        if fail {
            throw StubLoadError()
        }
        return [makeEntry(id: id, usage: makeUsage(cacheCreation5m: 0, cacheCreation1h: 0))]
    }
}

private struct StubLoadError: LocalizedError {
    var errorDescription: String? { "stub load failed" }
}

private func makeEntry(id: ProviderID, usage: TokenUsage) -> ParsedUsageEntry {
    ParsedUsageEntry(
        recordUUID: "record-1",
        messageId: "message-1",
        requestId: nil,
        sessionID: "session-1",
        timestamp: Date(timeIntervalSince1970: 1_800_000_000),
        model: "claude-sonnet-4-5",
        cwd: "/test",
        agentId: nil,
        usage: usage,
        isSubagent: false,
        provider: id,
        upstreamProviderID: nil,
        upstreamCost: nil
    )
}

@MainActor
private final class StubBookmarkManager: BookmarkAccessManaging {
    private let rootURL: URL

    init(rootURL: URL) {
        self.rootURL = rootURL
    }

    func hasBookmark(forKey key: String) -> Bool {
        true
    }

    func promptUserToSelectDirectory(forProvider provider: any UsageProvider) async -> URL? {
        rootURL
    }

    func restoreBookmarkAndAccess(forKey key: String) -> URL? {
        rootURL
    }

    func stopAccessing(forKey key: String) {}
}

private final class CountingUsageAggregator: UsageAggregating, @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0

    var aggregateCallCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return count
    }

    func aggregate(_ entries: [ParsedUsageEntry]) -> AggregatedStats {
        lock.lock()
        count += 1
        lock.unlock()
        return UsageAggregator().aggregate(entries)
    }
}
