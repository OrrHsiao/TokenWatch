import Foundation
import Testing
@testable import TokenWatch

@Suite("TokenStatsViewModel widget publication")
@MainActor
struct TokenStatsViewModelWidgetPublishingTests {
    @Test("all-provider refresh publishes once after every provider finishes")
    func loadAllPublishesOnceAfterEveryProviderCompletes() async throws {
        let fixture = makeLanguageSettings()
        defer { fixture.defaults.removePersistentDomain(forName: fixture.suiteName) }
        let claude = MutableTestUsageProvider(id: .claude, totalTokens: 10)
        let codex = BlockingTestUsageProvider(id: .codex, totalTokens: 20)
        defer { codex.resume() }
        let publisher = RecordingWidgetSnapshotPublisher()
        let viewModel = makeViewModel(
            settings: fixture.settings,
            providers: [claude, codex],
            publisher: publisher
        )

        let refresh = Task { await viewModel.loadAllStats() }
        try await waitUntil {
            codex.isWaiting
                && viewModel.states[.claude]?.stats?.overall.totalTokens == 10
        }

        let countBeforeCodexFinishes = await publisher.callCount()
        #expect(countBeforeCodexFinishes == 0)
        codex.resume()
        await refresh.value

        let calls = await publisher.recordedCalls()
        let call = try #require(calls.first)
        #expect(calls.count == 1)
        #expect(call.states[.claude]?.stats?.overall.totalTokens == 10)
        #expect(call.states[.codex]?.stats?.overall.totalTokens == 20)
    }

    @Test("overlapping all-provider refresh never publishes an intermediate snapshot")
    func overlappingLoadAllDoesNotPublishIntermediateStates() async throws {
        let fixture = makeLanguageSettings()
        defer { fixture.defaults.removePersistentDomain(forName: fixture.suiteName) }
        let claude = MutableTestUsageProvider(id: .claude, totalTokens: 10)
        let codex = BlockingTestUsageProvider(id: .codex, totalTokens: 20)
        defer { codex.resume() }
        let publisher = RecordingWidgetSnapshotPublisher()
        let viewModel = makeViewModel(
            settings: fixture.settings,
            providers: [claude, codex],
            publisher: publisher
        )

        let firstRefresh = Task { await viewModel.loadAllStats() }
        try await waitUntil { codex.isWaiting }
        await viewModel.loadAllStats()

        #expect(claude.scanCount == 1)
        #expect(codex.scanCount == 1)
        let countBeforeFirstRefreshFinishes = await publisher.callCount()
        #expect(countBeforeFirstRefreshFinishes == 0)

        codex.resume()
        await firstRefresh.value

        #expect(claude.scanCount == 1)
        #expect(codex.scanCount == 1)
        let finalOverlapCount = await publisher.callCount()
        #expect(finalOverlapCount == 1)
    }

    @Test("partial failure publishes the retained valid provider state")
    func partialFailureStillPublishesAvailableStats() async throws {
        let fixture = makeLanguageSettings()
        defer { fixture.defaults.removePersistentDomain(forName: fixture.suiteName) }
        let claude = MutableTestUsageProvider(id: .claude, totalTokens: 10)
        let codex = MutableTestUsageProvider(id: .codex, totalTokens: 20)
        let publisher = RecordingWidgetSnapshotPublisher()
        let viewModel = makeViewModel(
            settings: fixture.settings,
            providers: [claude, codex],
            publisher: publisher
        )

        await viewModel.loadAllStats()
        await publisher.reset()
        claude.setTotalTokens(30)
        codex.failNextLoad()

        await viewModel.loadAllStats()

        let calls = await publisher.recordedCalls()
        let call = try #require(calls.first)
        #expect(calls.count == 1)
        #expect(call.states[.claude]?.stats?.overall.totalTokens == 30)
        #expect(call.states[.codex]?.stats?.overall.totalTokens == 20)
        #expect(call.states[.codex]?.errorMessage != nil)
        #expect(claude.scanCount == 2)
        #expect(codex.scanCount == 2)
    }

    @Test("language change republishes memory without rescanning")
    func languageChangeRepublishesWithoutRescanning() async throws {
        let fixture = makeLanguageSettings()
        defer { fixture.defaults.removePersistentDomain(forName: fixture.suiteName) }
        let claude = MutableTestUsageProvider(id: .claude, totalTokens: 10)
        let codex = MutableTestUsageProvider(id: .codex, totalTokens: 20)
        let publisher = RecordingWidgetSnapshotPublisher()
        let viewModel = makeViewModel(
            settings: fixture.settings,
            providers: [claude, codex],
            publisher: publisher
        )

        await viewModel.loadAllStats()
        let initialLanguagePublishCount = await publisher.callCount()
        #expect(initialLanguagePublishCount == 1)
        let claudeScans = claude.scanCount
        let codexScans = codex.scanCount

        fixture.settings.selectedPreference = .en
        try await waitUntil { await publisher.callCount() == 2 }

        let calls = await publisher.recordedCalls()
        #expect(calls.map(\.language) == [.zhHans, .en])
        #expect(claude.scanCount == claudeScans)
        #expect(codex.scanCount == codexScans)
    }

    @Test("language changes before and during publish use a final republish loop")
    func languageChangeDuringLoadIsDeferred() async throws {
        let fixture = makeLanguageSettings()
        defer { fixture.defaults.removePersistentDomain(forName: fixture.suiteName) }
        let claude = MutableTestUsageProvider(id: .claude, totalTokens: 10)
        let codex = BlockingTestUsageProvider(id: .codex, totalTokens: 20)
        defer { codex.resume() }
        let publisher = RecordingWidgetSnapshotPublisher()
        await publisher.suspendNextPublish()
        let viewModel = makeViewModel(
            settings: fixture.settings,
            providers: [claude, codex],
            publisher: publisher
        )

        let refresh = Task { await viewModel.loadAllStats() }
        try await waitUntil { codex.isWaiting }
        fixture.settings.selectedPreference = .en
        let countBeforeBlockedProviderFinishes = await publisher.callCount()
        #expect(countBeforeBlockedProviderFinishes == 0)

        codex.resume()
        try await waitUntil { await publisher.isPublishSuspended() }
        fixture.settings.selectedPreference = .ja
        await publisher.resumeSuspendedPublish()
        await refresh.value

        let calls = await publisher.recordedCalls()
        #expect(calls.map(\.language) == [.en, .ja])
        #expect(claude.scanCount == 1)
        #expect(codex.scanCount == 1)
    }

    private func makeViewModel(
        settings: AppLanguageSettings,
        providers: [any UsageProvider],
        publisher: RecordingWidgetSnapshotPublisher
    ) -> TokenStatsViewModel {
        TokenStatsViewModel(
            languageSettings: settings,
            providers: providers,
            bookmarkManager: AlwaysAuthorizedBookmarkManager(),
            aggregator: UsageAggregator(),
            widgetSnapshotPublisher: publisher
        )
    }

    private func makeLanguageSettings() -> (
        settings: AppLanguageSettings,
        defaults: UserDefaults,
        suiteName: String
    ) {
        let suiteName = "TokenStatsViewModelWidgetPublishingTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        return (
            AppLanguageSettings(
                defaults: defaults,
                preferredLanguagesProvider: { ["zh-Hans"] }
            ),
            defaults,
            suiteName
        )
    }

    private func waitUntil(
        _ predicate: @escaping @MainActor () async -> Bool
    ) async throws {
        // 这是防止测试永久挂起的安全上限，不是产品时序断言；并行回归会延后后台 provider 调度。
        let deadline = Date().addingTimeInterval(10)
        while !(await predicate()) {
            guard Date() < deadline else {
                throw WidgetPublishingTestTimeout()
            }
            try await Task.sleep(nanoseconds: 10_000_000)
        }
    }
}

private struct WidgetPublishingTestTimeout: Error {}

private struct WidgetPublishingInjectedLoadError: LocalizedError {
    var errorDescription: String? { "injected provider failure" }
}

private actor RecordingWidgetSnapshotPublisher: WidgetSnapshotPublishing {
    struct Call: Sendable {
        let states: [ProviderID: TokenStatsViewModel.ProviderState]
        let language: AppLanguage
    }

    private var calls: [Call] = []
    private var shouldSuspendNextPublish = false
    private var publishIsSuspended = false
    private var continuation: CheckedContinuation<Void, Never>?

    func publish(
        states: [ProviderID: TokenStatsViewModel.ProviderState],
        language: AppLanguage
    ) async -> WidgetSnapshotPublishResult {
        calls.append(Call(states: states, language: language))
        if shouldSuspendNextPublish {
            shouldSuspendNextPublish = false
            publishIsSuspended = true
            await withCheckedContinuation { continuation in
                self.continuation = continuation
            }
            publishIsSuspended = false
        }
        return .published
    }

    func callCount() -> Int {
        calls.count
    }

    func recordedCalls() -> [Call] {
        calls
    }

    func reset() {
        calls.removeAll()
    }

    func suspendNextPublish() {
        shouldSuspendNextPublish = true
    }

    func isPublishSuspended() -> Bool {
        publishIsSuspended
    }

    func resumeSuspendedPublish() {
        let continuation = continuation
        self.continuation = nil
        continuation?.resume()
    }
}

private final class MutableTestUsageProvider: UsageProvider, @unchecked Sendable {
    let id: ProviderID
    let displayName: String
    let bookmarkKey: String
    let openPanelMessage = "Select a folder"
    let hasCacheWriteDimension = true
    let hasReasoningDimension = false

    private let lock = NSLock()
    private var storedTotalTokens: Int
    private var shouldFailNextLoad = false
    private var storedScanCount = 0

    init(id: ProviderID, totalTokens: Int) {
        self.id = id
        self.displayName = "Test \(id.rawValue)"
        self.bookmarkKey = "TestBookmark.\(id.rawValue)"
        self.storedTotalTokens = totalTokens
    }

    var scanCount: Int {
        withLock { storedScanCount }
    }

    func setTotalTokens(_ totalTokens: Int) {
        withLock { storedTotalTokens = totalTokens }
    }

    func failNextLoad() {
        withLock { shouldFailNextLoad = true }
    }

    func loadEntries(from rootURL: URL) throws -> [ParsedUsageEntry] {
        let result: (totalTokens: Int, shouldFail: Bool) = withLock {
            storedScanCount += 1
            let failure = shouldFailNextLoad
            shouldFailNextLoad = false
            return (storedTotalTokens, failure)
        }
        if result.shouldFail {
            throw WidgetPublishingInjectedLoadError()
        }
        return [makeWidgetPublishingEntry(
            provider: id,
            totalTokens: result.totalTokens
        )]
    }

    private func withLock<T>(_ body: () -> T) -> T {
        lock.lock()
        defer { lock.unlock() }
        return body()
    }
}

private final class BlockingTestUsageProvider: UsageProvider, @unchecked Sendable {
    let id: ProviderID
    let displayName: String
    let bookmarkKey: String
    let openPanelMessage = "Select a folder"
    let hasCacheWriteDimension = true
    let hasReasoningDimension = false

    private let condition = NSCondition()
    private let totalTokens: Int
    private var released = false
    private var waiting = false
    private var storedScanCount = 0

    init(id: ProviderID, totalTokens: Int) {
        self.id = id
        self.displayName = "Blocking \(id.rawValue)"
        self.bookmarkKey = "BlockingBookmark.\(id.rawValue)"
        self.totalTokens = totalTokens
    }

    var scanCount: Int {
        condition.lock()
        defer { condition.unlock() }
        return storedScanCount
    }

    var isWaiting: Bool {
        condition.lock()
        defer { condition.unlock() }
        return waiting
    }

    func resume() {
        condition.lock()
        released = true
        condition.broadcast()
        condition.unlock()
    }

    func loadEntries(from rootURL: URL) throws -> [ParsedUsageEntry] {
        condition.lock()
        storedScanCount += 1
        waiting = true
        condition.broadcast()
        while !released {
            condition.wait()
        }
        waiting = false
        condition.unlock()
        return [makeWidgetPublishingEntry(
            provider: id,
            totalTokens: totalTokens
        )]
    }
}

@MainActor
private final class AlwaysAuthorizedBookmarkManager: BookmarkAccessManaging {
    private let rootURL = FileManager.default.temporaryDirectory

    func hasBookmark(forKey key: String) -> Bool {
        true
    }

    func promptUserToSelectDirectory(
        forProvider provider: any UsageProvider
    ) async -> URL? {
        rootURL
    }

    func restoreBookmarkAndAccess(forKey key: String) -> URL? {
        rootURL
    }

    func stopAccessing(forKey key: String) {}
}

private func makeWidgetPublishingEntry(
    provider: ProviderID,
    totalTokens: Int
) -> ParsedUsageEntry {
    ParsedUsageEntry(
        recordUUID: "record-\(provider.rawValue)",
        messageId: "message-\(provider.rawValue)",
        requestId: nil,
        sessionID: "session-\(provider.rawValue)",
        timestamp: Date(timeIntervalSince1970: 1_800_000_000),
        model: "claude-sonnet-4-5",
        upstreamModelID: nil,
        cwd: "/test",
        agentId: nil,
        usage: TokenUsage(
            inputTokens: totalTokens,
            cacheCreationInputTokens: 0,
            cacheReadInputTokens: 0,
            outputTokens: 0,
            reasoningTokens: 0,
            serverToolUse: ServerToolUse(
                webSearchRequests: 0,
                webFetchRequests: 0
            ),
            serviceTier: "standard",
            cacheCreation: nil,
            inferenceGeo: "",
            iterations: [],
            speed: "standard"
        ),
        isSubagent: false,
        provider: provider,
        upstreamProviderID: nil,
        upstreamCost: nil
    )
}
