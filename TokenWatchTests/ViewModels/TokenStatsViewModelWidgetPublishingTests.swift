import Foundation
import Testing
@testable import TokenWatch

@Suite("TokenStatsViewModel widget publication", .serialized)
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
        try await waitUntil {
            codex.isWaiting && claude.scanCount == 1
        }
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

    @Test("queued language drain rechecks a refresh that starts before it runs")
    func queuedLanguageChangeWaitsForRefreshGate() async throws {
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

        // refresh 先排入 MainActor，语言 observer 随后排入 drain；真正执行 drain 时必须重查 gate。
        let refresh = Task { await viewModel.loadAllStats() }
        fixture.settings.selectedPreference = .language(.en)
        try await waitUntil { codex.isWaiting }

        let callCountWhileRefreshIsBlocked = await publisher.callCount()
        #expect(callCountWhileRefreshIsBlocked == 0)

        codex.resume()
        await refresh.value

        let calls = await publisher.recordedCalls()
        #expect(calls.map(\.language) == [.en])
        #expect(claude.scanCount == 1)
        #expect(codex.scanCount == 1)
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

        fixture.settings.selectedPreference = .language(.en)
        try await waitUntil { await publisher.callCount() == 2 }

        let calls = await publisher.recordedCalls()
        #expect(calls.map(\.language) == [.zhHans, .en])
        #expect(claude.scanCount == claudeScans)
        #expect(codex.scanCount == codexScans)
    }

    @Test("monthly budget change republishes memory without rescanning")
    func monthlyBudgetChangeRepublishesWithoutRescanning() async throws {
        let fixture = makeLanguageSettings()
        defer { fixture.defaults.removePersistentDomain(forName: fixture.suiteName) }
        let budgetSettings = MonthlyBudgetSettings(defaults: fixture.defaults)
        let claude = MutableTestUsageProvider(id: .claude, totalTokens: 10)
        let codex = MutableTestUsageProvider(id: .codex, totalTokens: 20)
        let publisher = RecordingWidgetSnapshotPublisher()
        let viewModel = makeViewModel(
            settings: fixture.settings,
            monthlyBudgetSettings: budgetSettings,
            providers: [claude, codex],
            publisher: publisher
        )

        await viewModel.loadAllStats()
        let claudeScans = claude.scanCount
        let codexScans = codex.scanCount
        budgetSettings.monthlyBudgetUSD = 100
        try await waitUntil { await publisher.callCount() == 2 }

        let calls = await publisher.recordedCalls()
        #expect(calls.map(\.monthlyBudgetUSD) == [nil, 100])
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
        fixture.settings.selectedPreference = .language(.en)
        let countBeforeBlockedProviderFinishes = await publisher.callCount()
        #expect(countBeforeBlockedProviderFinishes == 0)

        codex.resume()
        try await waitUntil { await publisher.isPublishSuspended() }
        fixture.settings.selectedPreference = .language(.ja)
        await publisher.resumeSuspendedPublish()
        await refresh.value

        let calls = await publisher.recordedCalls()
        #expect(calls.map(\.language) == [.en, .ja])
        #expect(claude.scanCount == 1)
        #expect(codex.scanCount == 1)
    }

    @Test("idle language changes during publish share one drain and keep only the latest language")
    func idleLanguageChangesDuringPublishShareOneDrain() async throws {
        let fixture = makeLanguageSettings()
        defer { fixture.defaults.removePersistentDomain(forName: fixture.suiteName) }
        let claude = MutableTestUsageProvider(id: .claude, totalTokens: 10)
        let publisher = RecordingWidgetSnapshotPublisher()
        await publisher.suspendNextPublish()
        defer {
            Task { await publisher.resumeSuspendedPublish() }
        }
        let viewModel = makeViewModel(
            settings: fixture.settings,
            providers: [claude],
            publisher: publisher
        )
        let scansBeforeLanguageChanges = claude.scanCount

        fixture.settings.selectedPreference = .language(.en)
        try await waitUntil { await publisher.isPublishSuspended() }
        fixture.settings.selectedPreference = .language(.ja)
        fixture.settings.selectedPreference = .language(.ko)
        await waitForPreviouslyScheduledMainActorTasks()

        let callCountWhileFirstPublishIsSuspended = await publisher.callCount()
        #expect(callCountWhileFirstPublishIsSuspended == 1)

        await publisher.resumeSuspendedPublish()
        try await waitUntil { await publisher.callCount() >= 2 }
        await waitForPreviouslyScheduledMainActorTasks()

        let calls = await publisher.recordedCalls()
        #expect(calls.map(\.language) == [.en, .ko])
        #expect(claude.scanCount == scansBeforeLanguageChanges)
        withExtendedLifetime(viewModel) {}
    }

    @Test("idle publish finishing during refresh does not duplicate the complete refresh publish")
    func idlePublishFinishingDuringRefreshDoesNotDuplicateRefreshPublish() async throws {
        let fixture = makeLanguageSettings()
        defer { fixture.defaults.removePersistentDomain(forName: fixture.suiteName) }
        let claude = MutableTestUsageProvider(id: .claude, totalTokens: 10)
        let publisher = RecordingWidgetSnapshotPublisher()
        await publisher.suspendNextPublish()
        defer {
            Task { await publisher.resumeAllSuspendedPublishes() }
        }
        let viewModel = makeViewModel(
            settings: fixture.settings,
            providers: [claude],
            publisher: publisher
        )

        fixture.settings.selectedPreference = .language(.en)
        try await waitUntil { await publisher.suspendedPublishCount() == 1 }

        await publisher.suspendNextPublish()
        let refresh = Task { await viewModel.loadAllStats() }
        try await waitUntil { await publisher.suspendedPublishCount() == 2 }

        let callsWhileBothPublishesAreSuspended = await publisher.recordedCalls()
        #expect(callsWhileBothPublishesAreSuspended.map(\.language) == [.en, .en])
        #expect(claude.scanCount == 1)

        // 先恢复旧 idle publish；第二个 continuation 仍挂起，因此完整刷新 gate 仍开启。
        await publisher.resumeSuspendedPublish()
        try await waitUntil { await publisher.completedPublishCount() == 1 }
        await waitForPreviouslyScheduledMainActorTasks()

        let callCountBeforeRefreshPublishResumes = await publisher.callCount()
        #expect(callCountBeforeRefreshPublishResumes == 2)
        #expect(await publisher.suspendedPublishCount() == 1)
        #expect(fixture.settings.selectedPreference == .language(.en))

        await publisher.resumeSuspendedPublish()
        await refresh.value
        await waitForPreviouslyScheduledMainActorTasks()

        let calls = await publisher.recordedCalls()
        #expect(calls.map(\.language) == [.en, .en])
        #expect(claude.scanCount == 1)
        withExtendedLifetime(viewModel) {}
    }

    private func makeViewModel(
        settings: AppLanguageSettings,
        monthlyBudgetSettings: MonthlyBudgetSettings? = nil,
        providers: [any UsageProvider],
        publisher: RecordingWidgetSnapshotPublisher
    ) -> TokenStatsViewModel {
        TokenStatsViewModel(
            languageSettings: settings,
            monthlyBudgetSettings: monthlyBudgetSettings ?? .shared,
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
        let deadline = Date().addingTimeInterval(30)
        while !(await predicate()) {
            guard Date() < deadline else {
                throw WidgetPublishingTestTimeout()
            }
            try await Task.sleep(nanoseconds: 10_000_000)
        }
    }

    private func waitForPreviouslyScheduledMainActorTasks() async {
        let barrier = Task { @MainActor in () }
        await barrier.value
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
        let monthlyBudgetUSD: Double?
    }

    private var calls: [Call] = []
    private var pendingSuspensionCount = 0
    private var suspendedContinuations: [CheckedContinuation<Void, Never>] = []
    private var completedPublishes = 0

    func publish(
        states: [ProviderID: TokenStatsViewModel.ProviderState],
        language: AppLanguage,
        monthlyBudgetUSD: Double?
    ) async -> WidgetSnapshotPublishResult {
        calls.append(
            Call(
                states: states,
                language: language,
                monthlyBudgetUSD: monthlyBudgetUSD
            )
        )
        if pendingSuspensionCount > 0 {
            pendingSuspensionCount -= 1
            await withCheckedContinuation { continuation in
                suspendedContinuations.append(continuation)
            }
        }
        completedPublishes += 1
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
        completedPublishes = 0
    }

    func suspendNextPublish() {
        pendingSuspensionCount += 1
    }

    func isPublishSuspended() -> Bool {
        !suspendedContinuations.isEmpty
    }

    func suspendedPublishCount() -> Int {
        suspendedContinuations.count
    }

    func completedPublishCount() -> Int {
        completedPublishes
    }

    func resumeSuspendedPublish() {
        guard !suspendedContinuations.isEmpty else { return }
        suspendedContinuations.removeFirst().resume()
    }

    func resumeAllSuspendedPublishes() {
        let continuations = suspendedContinuations
        suspendedContinuations.removeAll()
        for continuation in continuations {
            continuation.resume()
        }
    }
}

private final class MutableTestUsageProvider: UsageProvider, @unchecked Sendable {
    let id: ProviderID
    let displayName: String
    let bookmarkKey: String
    let hasCacheWriteDimension = true
    let hasReasoningDimension = false

    var openPanelMessageKey: AppStringKey {
        switch id {
        case .claude: .claudeDataDirectoryOpenPanelMessage
        case .codex: .codexDataDirectoryOpenPanelMessage
        case .opencode: .openCodeDataDirectoryOpenPanelMessage
        case .antigravity: .antigravityDataDirectoryOpenPanelMessage
        }
    }

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
    let hasCacheWriteDimension = true
    let hasReasoningDimension = false

    var openPanelMessageKey: AppStringKey {
        switch id {
        case .claude: .claudeDataDirectoryOpenPanelMessage
        case .codex: .codexDataDirectoryOpenPanelMessage
        case .opencode: .openCodeDataDirectoryOpenPanelMessage
        case .antigravity: .antigravityDataDirectoryOpenPanelMessage
        }
    }

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
    ) async -> DirectoryAuthorizationResult {
        .authorized(rootURL)
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
