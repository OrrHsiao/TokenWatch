import Dispatch
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

    @Test("授权只更新并加载用户选择的 provider")
    func authorizationOnlyUpdatesAndLoadsSelectedProvider() async {
        let claudeKey = "ClaudeDataDirectoryBookmark"
        let codexKey = "CodexDataDirectoryBookmark"
        let selectedURL = URL(
            fileURLWithPath: "/chosen-claude",
            isDirectory: true
        )
        let claude = DirectoryTestUsageProvider(
            id: .claude,
            bookmarkKey: claudeKey
        )
        let codex = DirectoryTestUsageProvider(
            id: .codex,
            bookmarkKey: codexKey
        )
        let manager = DirectoryTestBookmarkManager(
            promptResult: .authorized(selectedURL)
        )
        let vm = TokenStatsViewModel(
            providers: [claude, codex],
            bookmarkManager: manager
        )

        #expect(await vm.requestAuthorization(for: .claude))
        #expect(claude.loadCount == 1)
        #expect(codex.loadCount == 0)
        #expect(vm.states[.claude]?.directoryState == .selected)
        #expect(vm.states[.claude]?.needsAuthorization == false)
        #expect(vm.states[.codex]?.directoryState == .notSelected)
        #expect(vm.states[.codex]?.needsAuthorization == true)
        #expect(manager.promptedProviderIDs == [.claude])
        #expect(manager.restoredKeys == [claudeKey])
        #expect(manager.stoppedKeys == [claudeKey])
        #expect(manager.hasBookmark(forKey: claudeKey))
        #expect(!manager.hasBookmark(forKey: codexKey))
    }

    @Test("取消授权不会改变任一 provider 的持久状态")
    func cancelledAuthorizationLeavesProviderStatesUnchanged() async {
        let claude = DirectoryTestUsageProvider(
            id: .claude,
            bookmarkKey: "ClaudeDataDirectoryBookmark"
        )
        let codex = DirectoryTestUsageProvider(
            id: .codex,
            bookmarkKey: "CodexDataDirectoryBookmark"
        )
        let manager = DirectoryTestBookmarkManager(promptResult: .cancelled)
        let vm = TokenStatsViewModel(
            providers: [claude, codex],
            bookmarkManager: manager
        )
        let beforeClaudeState = vm.states[.claude]?.directoryState
        let beforeClaudeNeedsAuthorization =
            vm.states[.claude]?.needsAuthorization
        let beforeClaudeDirectoryError =
            vm.states[.claude]?.directoryAuthorizationErrorMessage
        let beforeCodexState = vm.states[.codex]?.directoryState
        let beforeCodexNeedsAuthorization =
            vm.states[.codex]?.needsAuthorization
        let beforeCodexDirectoryError =
            vm.states[.codex]?.directoryAuthorizationErrorMessage

        #expect(!(await vm.requestAuthorization(for: .claude)))
        #expect(vm.states[.claude]?.directoryState == beforeClaudeState)
        #expect(
            vm.states[.claude]?.needsAuthorization
                == beforeClaudeNeedsAuthorization
        )
        #expect(
            vm.states[.claude]?.directoryAuthorizationErrorMessage
                == beforeClaudeDirectoryError
        )
        #expect(vm.states[.claude]?.stats == nil)
        #expect(vm.states[.claude]?.entries == nil)
        #expect(vm.states[.claude]?.errorMessage == nil)
        #expect(vm.states[.claude]?.isAuthorizing == false)
        #expect(vm.states[.codex]?.directoryState == beforeCodexState)
        #expect(
            vm.states[.codex]?.needsAuthorization
                == beforeCodexNeedsAuthorization
        )
        #expect(
            vm.states[.codex]?.directoryAuthorizationErrorMessage
                == beforeCodexDirectoryError
        )
        #expect(vm.states[.codex]?.stats == nil)
        #expect(vm.states[.codex]?.entries == nil)
        #expect(codex.loadCount == 0)
    }

    @Test("重新选择失败保留旧授权和旧数据")
    func failedReselectionPreservesOldAuthorizationAndData() async {
        let key = "ClaudeDataDirectoryBookmark"
        let provider = DirectoryTestUsageProvider(
            id: .claude,
            bookmarkKey: key
        )
        let manager = DirectoryTestBookmarkManager(
            promptResult: .failed,
            authorizedRoots: [
                key: URL(fileURLWithPath: "/claude", isDirectory: true),
            ]
        )
        let vm = TokenStatsViewModel(
            languageSettings: directoryTestEnglishLanguageSettings(),
            providers: [provider],
            bookmarkManager: manager
        )
        await vm.loadStats(for: .claude)
        let oldTotalTokens =
            vm.states[.claude]?.stats?.overall.totalTokens
        let oldEntries = vm.states[.claude]?.entries
        let oldDirectoryState = vm.states[.claude]?.directoryState

        #expect(!(await vm.requestAuthorization(for: .claude)))
        #expect(vm.states[.claude]?.directoryState == oldDirectoryState)
        #expect(vm.states[.claude]?.directoryState == .selected)
        #expect(vm.states[.claude]?.needsAuthorization == false)
        #expect(
            vm.states[.claude]?.stats?.overall.totalTokens
                == oldTotalTokens
        )
        #expect(vm.states[.claude]?.entries == oldEntries)
        #expect(vm.states[.claude]?.errorMessage == nil)
        #expect(
            vm.states[.claude]?.directoryAuthorizationErrorMessage
                == TokenStatsViewModel.authorizationFailedMessage(
                    providerName: "Claude Code",
                    language: .en
                )
        )
        #expect(manager.hasBookmark(forKey: key))
        #expect(provider.loadCount == 1)
        #expect(manager.restoredKeys == [key])
        #expect(manager.stoppedKeys == [key])
    }

    @Test("空目录仍保持已选择并显示无数据状态")
    func selectedDirectoryWithoutEntriesRemainsAuthorized() async {
        let key = "OpenCodeDataDirectoryBookmark"
        let provider = DirectoryTestUsageProvider(
            id: .opencode,
            bookmarkKey: key,
            entries: []
        )
        let manager = DirectoryTestBookmarkManager(
            authorizedRoots: [
                key: URL(fileURLWithPath: "/opencode", isDirectory: true),
            ]
        )
        let vm = TokenStatsViewModel(
            providers: [provider],
            bookmarkManager: manager
        )

        await vm.loadStats(for: .opencode)

        #expect(
            vm.states[.opencode]?.directoryState == .selectedNoData
        )
        #expect(vm.states[.opencode]?.needsAuthorization == false)
        #expect(vm.states[.opencode]?.entries == [])
        #expect(
            vm.states[.opencode]?.stats?.overall.entryCount == 0
        )
        #expect(vm.states[.opencode]?.errorMessage == nil)
        #expect(
            vm.states[.opencode]?.directoryAuthorizationErrorMessage
                == nil
        )
    }

    @Test("恢复失败只清除当前 provider 数据")
    func restoreFailureClearsOnlyCurrentProviderData() async {
        let claudeKey = "ClaudeDataDirectoryBookmark"
        let codexKey = "CodexDataDirectoryBookmark"
        let claude = DirectoryTestUsageProvider(
            id: .claude,
            bookmarkKey: claudeKey
        )
        let codex = DirectoryTestUsageProvider(
            id: .codex,
            bookmarkKey: codexKey
        )
        let manager = DirectoryTestBookmarkManager(
            authorizedRoots: [
                claudeKey: URL(
                    fileURLWithPath: "/claude",
                    isDirectory: true
                ),
                codexKey: URL(
                    fileURLWithPath: "/codex",
                    isDirectory: true
                ),
            ]
        )
        let vm = TokenStatsViewModel(
            languageSettings: directoryTestEnglishLanguageSettings(),
            providers: [claude, codex],
            bookmarkManager: manager
        )
        await vm.loadStats(for: .claude)
        await vm.loadStats(for: .codex)
        let oldCodexTotalTokens =
            vm.states[.codex]?.stats?.overall.totalTokens
        let oldCodexEntries = vm.states[.codex]?.entries

        manager.failRestoration(forKey: claudeKey)
        await vm.loadStats(for: .claude)

        #expect(
            vm.states[.claude]?.directoryState == .needsReselection
        )
        #expect(vm.states[.claude]?.needsAuthorization == true)
        #expect(vm.states[.claude]?.stats == nil)
        #expect(vm.states[.claude]?.entries == nil)
        #expect(vm.states[.claude]?.lastRefreshedAt == nil)
        #expect(vm.states[.claude]?.errorMessage == nil)
        #expect(
            vm.states[.claude]?.directoryAuthorizationErrorMessage
                == TokenStatsViewModel.cannotAccessDataDirectoryMessage(
                    providerName: "Claude Code",
                    language: .en
                )
        )
        #expect(!manager.hasBookmark(forKey: claudeKey))
        #expect(manager.hasBookmark(forKey: codexKey))
        #expect(vm.states[.codex]?.directoryState == .selected)
        #expect(vm.states[.codex]?.needsAuthorization == false)
        #expect(
            vm.states[.codex]?.stats?.overall.totalTokens
                == oldCodexTotalTokens
        )
        #expect(vm.states[.codex]?.entries == oldCodexEntries)
        #expect(
            vm.states[.codex]?.directoryAuthorizationErrorMessage
                == nil
        )
        #expect(claude.loadCount == 1)
        #expect(codex.loadCount == 1)
    }

    @Test("恢复失败后的下一次静默加载保持需要重新选择")
    func subsequentSilentLoadPreservesNeedsReselectionAfterRestoreFailure()
        async
    {
        let key = "ClaudeDataDirectoryBookmark"
        let provider = DirectoryTestUsageProvider(
            id: .claude,
            bookmarkKey: key
        )
        let manager = DirectoryTestBookmarkManager(
            authorizedRoots: [
                key: URL(fileURLWithPath: "/claude", isDirectory: true),
            ]
        )
        manager.failRestoration(forKey: key)
        let vm = TokenStatsViewModel(
            providers: [provider],
            bookmarkManager: manager
        )
        var received: [ProviderID] = []
        _ = vm.observe { received.append($0) }

        await vm.loadStats(for: .claude)
        let originalDirectoryError =
            vm.states[.claude]?.directoryAuthorizationErrorMessage
        received.removeAll()

        await vm.loadStats(
            for: .claude,
            mode: .silentIfUnchanged
        )

        #expect(
            vm.states[.claude]?.directoryState == .needsReselection
        )
        #expect(vm.states[.claude]?.needsAuthorization == true)
        #expect(
            vm.states[.claude]?.directoryAuthorizationErrorMessage
                == originalDirectoryError
        )
        #expect(originalDirectoryError != nil)
        #expect(vm.states[.claude]?.stats == nil)
        #expect(vm.states[.claude]?.entries == nil)
        #expect(vm.states[.claude]?.errorMessage == nil)
        #expect(manager.restoredKeys == [key])
        #expect(received.isEmpty)
    }

    @Test("bookmark 恢复成功但 parser 失败仍保持目录已选择")
    func parserFailureAfterSuccessfulRestoreKeepsDirectorySelected()
        async
    {
        let key = "CodexDataDirectoryBookmark"
        let provider = DirectoryTestUsageProvider(
            id: .codex,
            bookmarkKey: key,
            throwsOnLoad: true
        )
        let manager = DirectoryTestBookmarkManager(
            authorizedRoots: [
                key: URL(fileURLWithPath: "/codex", isDirectory: true),
            ]
        )
        let vm = TokenStatsViewModel(
            providers: [provider],
            bookmarkManager: manager
        )

        await vm.loadStats(for: .codex)

        #expect(vm.states[.codex]?.directoryState == .selected)
        #expect(vm.states[.codex]?.needsAuthorization == false)
        #expect(
            vm.states[.codex]?.directoryAuthorizationErrorMessage
                == nil
        )
        #expect(
            vm.states[.codex]?.errorMessage?
                .contains("stub load failed") == true
        )
        #expect(vm.states[.codex]?.stats == nil)
        #expect(vm.states[.codex]?.entries == nil)
        #expect(vm.states[.codex]?.lastRefreshedAt != nil)
        #expect(manager.restoredKeys == [key])
        #expect(manager.stoppedKeys == [key])
    }

    @Test("同一 provider 的授权和加载不会重叠", .timeLimit(.minutes(1)))
    func authorizationAndLoadingDoNotOverlapForSameProvider() async {
        let authorizationKey = "ClaudeDataDirectoryBookmark"
        let authorizationProvider = DirectoryTestUsageProvider(
            id: .claude,
            bookmarkKey: authorizationKey
        )
        let authorizationManager = DirectoryTestBookmarkManager(
            promptResult: .cancelled,
            suspendsPrompt: true
        )
        let authorizationVM = TokenStatsViewModel(
            providers: [authorizationProvider],
            bookmarkManager: authorizationManager
        )

        let authorizationTask = Task { @MainActor in
            await authorizationVM.requestAuthorization(for: .claude)
        }
        await authorizationManager.waitUntilPromptStarts()
        #expect(
            authorizationVM.states[.claude]?.isAuthorizing == true
        )

        await authorizationVM.loadStats(for: .claude)

        #expect(authorizationProvider.loadCount == 0)
        #expect(authorizationManager.restoredKeys.isEmpty)
        authorizationManager.resumePrompt(with: .cancelled)
        #expect(await authorizationTask.value == false)
        #expect(
            authorizationVM.states[.claude]?.isAuthorizing == false
        )

        let loadingKey = "CodexDataDirectoryBookmark"
        let loadingProvider = DirectoryTestUsageProvider(
            id: .codex,
            bookmarkKey: loadingKey,
            suspendsLoads: true
        )
        let loadingManager = DirectoryTestBookmarkManager(
            promptResult: .failed,
            authorizedRoots: [
                loadingKey: URL(
                    fileURLWithPath: "/codex",
                    isDirectory: true
                ),
            ]
        )
        let loadingVM = TokenStatsViewModel(
            providers: [loadingProvider],
            bookmarkManager: loadingManager
        )

        let loadTask = Task { @MainActor in
            await loadingVM.loadStats(for: .codex)
        }
        await loadingProvider.waitUntilLoadStarts()
        #expect(loadingVM.states[.codex]?.isLoading == true)

        #expect(
            !(await loadingVM.requestAuthorization(for: .codex))
        )
        #expect(loadingManager.promptedProviderIDs.isEmpty)

        loadingProvider.resumeLoad()
        await loadTask.value
        #expect(loadingProvider.loadCount == 1)
        #expect(loadingVM.states[.codex]?.directoryState == .selected)
    }

    @Test("授权成功交接给加载门禁时不会发布空闲窗口", .timeLimit(.minutes(1)))
    func successfulAuthorizationHandoffNeverPublishesIdleGap() async {
        let key = "ClaudeDataDirectoryBookmark"
        let provider = DirectoryTestUsageProvider(
            id: .claude,
            bookmarkKey: key,
            suspendsLoads: true
        )
        let manager = DirectoryTestBookmarkManager(
            promptResult: .authorized(
                URL(fileURLWithPath: "/claude", isDirectory: true)
            )
        )
        let vm = TokenStatsViewModel(
            providers: [provider],
            bookmarkManager: manager
        )
        var publishedTransitions: [String] = []
        _ = vm.observe { id in
            guard id == .claude, let state = vm.states[id] else { return }
            publishedTransitions.append(
                "authorizing=\(state.isAuthorizing),loading=\(state.isLoading)"
            )
        }

        let authorizationTask = Task { @MainActor in
            await vm.requestAuthorization(for: .claude)
        }
        await provider.waitUntilLoadStarts()

        #expect(publishedTransitions.contains(
            "authorizing=true,loading=false"
        ))
        #expect(publishedTransitions.contains(
            "authorizing=false,loading=true"
        ))
        #expect(!publishedTransitions.contains(
            "authorizing=false,loading=false"
        ))

        provider.resumeLoad()
        #expect(await authorizationTask.value)
    }

    @Test func failedAuthorizationDoesNotMarkAuthorizedOrRefresh() async {
        let provider = StubUsageProvider(id: .claude)
        let bookmarkManager = StubBookmarkManager(
            rootURL: URL(fileURLWithPath: NSTemporaryDirectory()),
            promptResult: .failed
        )
        let aggregator = CountingUsageAggregator()
        let vm = TokenStatsViewModel(
            providers: [provider],
            bookmarkManager: bookmarkManager,
            aggregator: aggregator
        )

        let didAuthorize = await vm.requestAuthorization(for: .claude)

        #expect(!didAuthorize)
        #expect(vm.states[.claude]?.needsAuthorization == true)
        #expect(aggregator.aggregateCallCount == 0)
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

    @Test("目录和加载错误按当前语言生成")
    func localizedErrorMessagesUseAppStrings() {
        let error = StubLocalizedError(description: "disk read failed")

        #expect(
            TokenStatsViewModel.cannotAccessDataDirectoryMessage(
                providerName: "Claude Code",
                language: .zhHans
            )
                == "无法访问 Claude Code 数据文件夹，请再次选择。"
        )
        #expect(
            TokenStatsViewModel.cannotAccessDataDirectoryMessage(
                providerName: "Claude Code",
                language: .en
            )
                == "Cannot access the Claude Code data folder. Please choose it again."
        )
        #expect(
            TokenStatsViewModel.authorizationFailedMessage(
                providerName: "Claude Code",
                language: .zhHans
            )
                == "无法保存 Claude Code 数据文件夹的访问权限，请重新选择。"
        )
        #expect(
            TokenStatsViewModel.authorizationFailedMessage(
                providerName: "Claude Code",
                language: .en
            )
                == "Could not save access to the Claude Code data folder. Please choose again."
        )
        #expect(
            TokenStatsViewModel.loadFailedMessage(
                error: error,
                language: .zhHans
            ) == "数据加载失败: disk read failed"
        )
        #expect(
            TokenStatsViewModel.loadFailedMessage(
                error: error,
                language: .en
            ) == "Data load failed: disk read failed"
        )
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

    /// 成功完成本地刷新后记录刷新时间,供主界面展示“xx 分钟/小时前更新”。
    @Test func successfulLocalRefreshRecordsRefreshTime() async throws {
        let now = Date(timeIntervalSince1970: 2_000_000)
        let provider = StubUsageProvider(id: .claude)
        let bookmarkManager = StubBookmarkManager(rootURL: URL(fileURLWithPath: NSTemporaryDirectory()))
        let vm = TokenStatsViewModel(
            providers: [provider],
            bookmarkManager: bookmarkManager,
            nowProvider: { now }
        )

        await vm.loadStats(for: .claude)

        #expect(vm.states[.claude]?.lastRefreshedAt == now)
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

    /// Codex 的 service tier 会改变倍率；仅该字段变化时也必须重新聚合。
    @Test func silentRefreshReloadsWhenCodexServiceTierChanges() async throws {
        let provider = MutableUsageProvider(
            id: .codex,
            usage: makeUsage(
                cacheCreation5m: 0,
                cacheCreation1h: 0,
                serviceTier: "standard"
            )
        )
        let bookmarkManager = StubBookmarkManager(
            rootURL: URL(fileURLWithPath: NSTemporaryDirectory())
        )
        let aggregator = CountingUsageAggregator()
        let vm = TokenStatsViewModel(
            providers: [provider],
            bookmarkManager: bookmarkManager,
            aggregator: aggregator
        )

        await vm.loadStats(for: .codex, mode: .silentIfUnchanged)
        let standardCost = vm.states[.codex]?.stats?.overall.cost

        provider.updateUsage(makeUsage(
            cacheCreation5m: 0,
            cacheCreation1h: 0,
            serviceTier: "priority"
        ))
        await vm.loadStats(for: .codex, mode: .silentIfUnchanged)
        let priorityCost = vm.states[.codex]?.stats?.overall.cost

        #expect(aggregator.aggregateCallCount == 2)
        #expect((priorityCost ?? 0) > (standardCost ?? 0))
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

    @Test func usageFingerprintIncludesSidechain() {
        let usage = makeUsage(cacheCreation5m: 0, cacheCreation1h: 0)
        let parent = makeEntry(id: .claude, usage: usage, isSidechain: false)
        let sidechain = makeEntry(id: .claude, usage: usage, isSidechain: true)

        #expect(UsageEntriesFingerprint.make(from: [parent]) !=
            UsageEntriesFingerprint.make(from: [sidechain]))
    }

    @Test func usageFingerprintIncludesSourceMessagePresence() {
        let usage = makeUsage(cacheCreation5m: 0, cacheCreation1h: 0)
        let sourced = makeEntry(id: .claude, usage: usage, hasSourceMessageID: true)
        let synthetic = makeEntry(id: .claude, usage: usage, hasSourceMessageID: false)

        #expect(UsageEntriesFingerprint.make(from: [sourced]) !=
            UsageEntriesFingerprint.make(from: [synthetic]))
    }

    @Test func usageFingerprintIncludesServiceTier() {
        let standard = makeEntry(
            id: .codex,
            usage: makeUsage(
                cacheCreation5m: 0,
                cacheCreation1h: 0,
                serviceTier: "standard"
            )
        )
        let priority = makeEntry(
            id: .codex,
            usage: makeUsage(
                cacheCreation5m: 0,
                cacheCreation1h: 0,
                serviceTier: "priority"
            )
        )

        #expect(UsageEntriesFingerprint.make(from: [standard]) !=
            UsageEntriesFingerprint.make(from: [priority]))
    }
}

private struct StubLocalizedError: LocalizedError {
    let description: String
    var errorDescription: String? { description }
}

private func makeUsage(
    cacheCreation5m: Int,
    cacheCreation1h: Int,
    serviceTier: String = "standard"
) -> TokenUsage {
    TokenUsage(
        inputTokens: 100,
        cacheCreationInputTokens: cacheCreation5m + cacheCreation1h,
        cacheReadInputTokens: 0,
        outputTokens: 50,
        serverToolUse: ServerToolUse(webSearchRequests: 0, webFetchRequests: 0),
        serviceTier: serviceTier,
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
    var openPanelMessageKey: AppStringKey {
        switch id {
        case .claude: .claudeDataDirectoryOpenPanelMessage
        case .codex: .codexDataDirectoryOpenPanelMessage
        case .opencode: .openCodeDataDirectoryOpenPanelMessage
        }
    }
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
    var openPanelMessageKey: AppStringKey {
        switch id {
        case .claude: .claudeDataDirectoryOpenPanelMessage
        case .codex: .codexDataDirectoryOpenPanelMessage
        case .opencode: .openCodeDataDirectoryOpenPanelMessage
        }
    }
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
    var openPanelMessageKey: AppStringKey {
        switch id {
        case .claude: .claudeDataDirectoryOpenPanelMessage
        case .codex: .codexDataDirectoryOpenPanelMessage
        case .opencode: .openCodeDataDirectoryOpenPanelMessage
        }
    }
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

private func makeEntry(
    id: ProviderID,
    usage: TokenUsage,
    isSidechain: Bool = false,
    hasSourceMessageID: Bool = true
) -> ParsedUsageEntry {
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
        isSidechain: isSidechain,
        hasSourceMessageID: hasSourceMessageID,
        provider: id,
        upstreamProviderID: nil,
        upstreamCost: nil
    )
}

@MainActor
private func directoryTestEnglishLanguageSettings() -> AppLanguageSettings {
    let suite = "DirectoryViewModelLanguage-\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suite)!
    return AppLanguageSettings(
        defaults: defaults,
        preferredLanguagesProvider: { ["en"] }
    )
}

private final class DirectoryTestUsageProvider:
    UsageProvider,
    @unchecked Sendable
{
    let id: ProviderID
    let displayName: String
    let bookmarkKey: String
    let hasCacheWriteDimension = true
    let hasReasoningDimension = false

    var openPanelMessageKey: AppStringKey {
        switch id {
        case .claude:
            .claudeDataDirectoryOpenPanelMessage
        case .codex:
            .codexDataDirectoryOpenPanelMessage
        case .opencode:
            .openCodeDataDirectoryOpenPanelMessage
        }
    }

    private let entries: [ParsedUsageEntry]
    private let throwsOnLoad: Bool
    private let suspendsLoads: Bool
    private let lock = NSLock()
    private var recordedLoadCount = 0
    private let loadRelease = DispatchSemaphore(value: 0)
    private let loadStartedStream: AsyncStream<Void>
    private let loadStartedContinuation:
        AsyncStream<Void>.Continuation

    init(
        id: ProviderID,
        bookmarkKey: String,
        entries: [ParsedUsageEntry]? = nil,
        throwsOnLoad: Bool = false,
        suspendsLoads: Bool = false
    ) {
        self.id = id
        self.bookmarkKey = bookmarkKey
        self.entries = entries ?? [
            makeEntry(
                id: id,
                usage: makeUsage(
                    cacheCreation5m: 0,
                    cacheCreation1h: 0
                )
            ),
        ]
        self.throwsOnLoad = throwsOnLoad
        self.suspendsLoads = suspendsLoads
        self.displayName = switch id {
        case .claude: "Claude Code"
        case .codex: "Codex"
        case .opencode: "opencode"
        }

        let signal = AsyncStream<Void>.makeStream()
        loadStartedStream = signal.stream
        loadStartedContinuation = signal.continuation
    }

    var loadCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return recordedLoadCount
    }

    func loadEntries(
        from dataRootURL: URL
    ) throws -> [ParsedUsageEntry] {
        lock.lock()
        recordedLoadCount += 1
        lock.unlock()

        loadStartedContinuation.yield(())
        if suspendsLoads {
            loadRelease.wait()
        }
        if throwsOnLoad {
            throw StubLoadError()
        }
        return entries
    }

    func waitUntilLoadStarts() async {
        var iterator = loadStartedStream.makeAsyncIterator()
        _ = await iterator.next()
    }

    func resumeLoad() {
        loadRelease.signal()
    }
}

@MainActor
private final class DirectoryTestBookmarkManager:
    BookmarkAccessManaging
{
    private let promptResult: DirectoryAuthorizationResult
    private let suspendsPrompt: Bool
    private var authorizedRoots: [String: URL]
    private var restoreFailureKeys: Set<String> = []
    private var promptContinuation:
        CheckedContinuation<DirectoryAuthorizationResult, Never>?
    private let promptStartedStream: AsyncStream<Void>
    private let promptStartedContinuation:
        AsyncStream<Void>.Continuation

    private(set) var promptedProviderIDs: [ProviderID] = []
    private(set) var restoredKeys: [String] = []
    private(set) var stoppedKeys: [String] = []

    init(
        promptResult: DirectoryAuthorizationResult = .cancelled,
        authorizedRoots: [String: URL] = [:],
        suspendsPrompt: Bool = false
    ) {
        self.promptResult = promptResult
        self.authorizedRoots = authorizedRoots
        self.suspendsPrompt = suspendsPrompt

        let signal = AsyncStream<Void>.makeStream()
        promptStartedStream = signal.stream
        promptStartedContinuation = signal.continuation
    }

    func hasBookmark(forKey key: String) -> Bool {
        authorizedRoots[key] != nil
    }

    func promptUserToSelectDirectory(
        forProvider provider: any UsageProvider
    ) async -> DirectoryAuthorizationResult {
        promptedProviderIDs.append(provider.id)

        let result: DirectoryAuthorizationResult
        if suspendsPrompt {
            result = await withCheckedContinuation { continuation in
                promptContinuation = continuation
                promptStartedContinuation.yield(())
            }
        } else {
            promptStartedContinuation.yield(())
            result = promptResult
        }

        if case .authorized(let url) = result {
            authorizedRoots[provider.bookmarkKey] = url
        }
        return result
    }

    func restoreBookmarkAndAccess(forKey key: String) -> URL? {
        restoredKeys.append(key)
        guard let url = authorizedRoots[key] else {
            return nil
        }
        if restoreFailureKeys.contains(key) {
            // 模拟 Task 3 的生产语义：恢复失败会删除当前 key。
            authorizedRoots.removeValue(forKey: key)
            return nil
        }
        return url
    }

    func stopAccessing(forKey key: String) {
        stoppedKeys.append(key)
    }

    func failRestoration(forKey key: String) {
        restoreFailureKeys.insert(key)
    }

    func waitUntilPromptStarts() async {
        var iterator = promptStartedStream.makeAsyncIterator()
        _ = await iterator.next()
    }

    func resumePrompt(
        with result: DirectoryAuthorizationResult
    ) {
        guard let continuation = promptContinuation else {
            preconditionFailure(
                "resumePrompt 必须在目录 prompt 已开始后调用"
            )
        }
        promptContinuation = nil
        continuation.resume(returning: result)
    }
}

@MainActor
private final class StubBookmarkManager: BookmarkAccessManaging {
    private let rootURL: URL
    private let promptResult: DirectoryAuthorizationResult

    init(
        rootURL: URL,
        promptResult: DirectoryAuthorizationResult? = nil
    ) {
        self.rootURL = rootURL
        self.promptResult = promptResult ?? .authorized(rootURL)
    }

    func hasBookmark(forKey key: String) -> Bool {
        true
    }

    func promptUserToSelectDirectory(
        forProvider provider: any UsageProvider
    ) async -> DirectoryAuthorizationResult {
        promptResult
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
