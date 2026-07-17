import AppKit
import Foundation
import Testing
@testable import TokenWatch

struct SecurityScopedBookmarkManagerTests {

    @Test("同一 bookmark key 的并发访问需要成对释放")
    func sharedSessionRequiresBalancedStops() {
        var sessions = SecurityScopedAccessSessions()
        let key = "HomeDirectoryBookmark"
        let url = URL(fileURLWithPath: "/Users/example", isDirectory: true)

        sessions.insert(url, forKey: key)
        #expect(sessions.retainExisting(forKey: key) == url)

        #expect(sessions.release(forKey: key) == nil)
        #expect(sessions.retainExisting(forKey: key) == url)

        #expect(sessions.release(forKey: key) == nil)
        #expect(sessions.release(forKey: key) == url)
        #expect(sessions.retainExisting(forKey: key) == nil)
    }

    @Test("授权面板使用 provider 专属文案")
    func openPanelCopyUsesProviderMessage() {
        #expect(SecurityScopedBookmarkManager.openPanelCopy(
            for: ClaudeProvider(),
            language: .en
        ).message == "Choose the Claude Code data folder. It is usually named \".claude\".")
        #expect(SecurityScopedBookmarkManager.openPanelCopy(
            for: CodexProvider(),
            language: .en
        ).message == "Choose the Codex data folder. It is usually named \".codex\".")
        #expect(SecurityScopedBookmarkManager.openPanelCopy(
            for: OpenCodeProvider(),
            language: .en
        ).message == "Choose the opencode data folder. It is usually named \"opencode\" and contains \"opencode.db\".")
        #expect(SecurityScopedBookmarkManager.openPanelCopy(
            for: ClaudeProvider(),
            language: .en
        ).prompt == "Choose")
    }

    @MainActor
    @Test("选择目录成功会写入目标 provider key 并返回 URL")
    func successfulSelectionPersistsProviderBookmarkAndReturnsURL() async {
        let key = "CodexDataDirectoryBookmark"
        let selectedURL = URL(fileURLWithPath: "/chosen-codex", isDirectory: true)
        let bookmarkData = Data([7, 8, 9])
        let store = ManagerBookmarkStore()
        let presenter = RecordingDirectoryPresenter(selection: selectedURL)
        let manager = SecurityScopedBookmarkManager(
            bookmarkDataCreator: FixedManagerBookmarkDataCreator(data: bookmarkData),
            bookmarkStore: store,
            directoryPresenter: presenter,
            languageProvider: { .en }
        )

        let result = await manager.promptUserToSelectDirectory(
            forProvider: CodexProvider()
        )

        #expect(result == .authorized(selectedURL))
        #expect(store.data(forKey: key) == bookmarkData)
        #expect(presenter.requestedProviderIDs == [.codex])
    }

    @MainActor
    @Test("选择目录后保存失败会返回 failed 并保留旧 bookmark")
    func selectedDirectoryPersistenceFailureReturnsFailedAndKeepsOldBookmark() async {
        let key = "ClaudeDataDirectoryBookmark"
        let oldData = Data([1, 2, 3])
        let selectedURL = URL(fileURLWithPath: "/replacement", isDirectory: true)
        let store = RejectingManagerBookmarkStore(values: [key: oldData])
        let manager = SecurityScopedBookmarkManager(
            bookmarkDataCreator: FixedManagerBookmarkDataCreator(data: Data([4, 5, 6])),
            bookmarkStore: store,
            directoryPresenter: RecordingDirectoryPresenter(selection: selectedURL),
            languageProvider: { .en }
        )

        let result = await manager.promptUserToSelectDirectory(
            forProvider: ClaudeProvider()
        )

        #expect(result == .failed)
        #expect(store.data(forKey: key) == oldData)
    }

    @MainActor
    @Test("取消目录面板不会写入或替换 bookmark")
    func cancellationDoesNotWriteOrReplaceBookmark() async {
        let key = "ClaudeDataDirectoryBookmark"
        let oldData = Data([1])
        let store = ManagerBookmarkStore(values: [key: oldData])
        let manager = SecurityScopedBookmarkManager(
            bookmarkStore: store,
            directoryPresenter: RecordingDirectoryPresenter(selection: nil),
            languageProvider: { .en }
        )

        let result = await manager.promptUserToSelectDirectory(
            forProvider: ClaudeProvider()
        )

        #expect(result == .cancelled)
        #expect(store.data(forKey: key) == oldData)
    }

    @MainActor
    @Test("面板使用 provider 文案且不改系统初始目录")
    func panelConfigurationUsesProviderCopyAndPreservesSystemDirectory() {
        let panel = NSOpenPanel()
        panel.directoryURL = FileManager.default.temporaryDirectory

        SecurityScopedBookmarkManager.configureOpenPanel(
            panel,
            for: CodexProvider(),
            language: .en
        )

        #expect(panel.directoryURL == FileManager.default.temporaryDirectory)
        #expect(panel.message == "Choose the Codex data folder. It is usually named \".codex\".")
        #expect(panel.prompt == "Choose")
        #expect(panel.canChooseDirectories)
        #expect(!panel.canChooseFiles)
        #expect(!panel.allowsMultipleSelection)
        #expect(panel.showsHiddenFiles)
        #expect(panel.treatsFilePackagesAsDirectories)
    }

    @MainActor
    @Test("无效 bookmark 恢复失败时清除注入 store")
    func invalidBookmarkRemovalUsesInjectedStore() {
        let key = "InvalidBookmark"
        let store = ManagerBookmarkStore(values: [key: Data([0])])
        let manager = SecurityScopedBookmarkManager(bookmarkStore: store)

        #expect(manager.hasBookmark(forKey: key))
        #expect(manager.restoreBookmarkAndAccess(forKey: key) == nil)
        #expect(!manager.hasBookmark(forKey: key))
        #expect(store.removedKeys == [key])
    }

    @MainActor
    @Test("stale bookmark 刷新失败会停止访问且只清除当前 provider")
    func staleRefreshFailureStopsAccessAndClearsOnlyCurrentProvider() {
        let claudeKey = "ClaudeDataDirectoryBookmark"
        let codexKey = "CodexDataDirectoryBookmark"
        let store = ManagerBookmarkStore(values: [
            claudeKey: Data([1]),
            codexKey: Data([2]),
        ])
        let url = URL(fileURLWithPath: "/claude", isDirectory: true)
        let accessor = RecordingResourceAccessor(startResult: true)
        let manager = SecurityScopedBookmarkManager(
            bookmarkDataCreator: ThrowingManagerBookmarkDataCreator(),
            bookmarkDataResolver: FixedBookmarkDataResolver(
                result: .init(url: url, isStale: true)
            ),
            bookmarkStore: store,
            resourceAccessor: accessor
        )

        #expect(manager.restoreBookmarkAndAccess(forKey: claudeKey) == nil)
        #expect(!manager.hasBookmark(forKey: claudeKey))
        #expect(manager.hasBookmark(forKey: codexKey))
        #expect(accessor.stoppedURLs == [url])
    }

    @MainActor
    @Test("startAccess 失败只清除请求的 provider bookmark")
    func startAccessFailureClearsOnlyRequestedProviderBookmark() {
        let claudeKey = "ClaudeDataDirectoryBookmark"
        let codexKey = "CodexDataDirectoryBookmark"
        let store = ManagerBookmarkStore(values: [
            claudeKey: Data([1]),
            codexKey: Data([2]),
        ])
        let accessor = RecordingResourceAccessor(startResult: false)
        let manager = SecurityScopedBookmarkManager(
            bookmarkDataResolver: FixedBookmarkDataResolver(
                result: .init(
                    url: URL(fileURLWithPath: "/claude", isDirectory: true),
                    isStale: false
                )
            ),
            bookmarkStore: store,
            resourceAccessor: accessor
        )

        #expect(manager.restoreBookmarkAndAccess(forKey: claudeKey) == nil)
        #expect(!manager.hasBookmark(forKey: claudeKey))
        #expect(manager.hasBookmark(forKey: codexKey))
        #expect(accessor.stoppedURLs.isEmpty)
    }

    @MainActor
    @Test("bookmark 解析失败只清除当前 provider")
    func resolverFailureClearsOnlyCurrentProvider() {
        let claudeKey = "ClaudeDataDirectoryBookmark"
        let codexKey = "CodexDataDirectoryBookmark"
        let store = ManagerBookmarkStore(values: [
            claudeKey: Data([1]),
            codexKey: Data([2]),
        ])
        let accessor = RecordingResourceAccessor(startResult: true)
        let manager = SecurityScopedBookmarkManager(
            bookmarkDataResolver: MappingBookmarkDataResolver(values: [:]),
            bookmarkStore: store,
            resourceAccessor: accessor
        )

        #expect(manager.restoreBookmarkAndAccess(forKey: claudeKey) == nil)
        #expect(!manager.hasBookmark(forKey: claudeKey))
        #expect(manager.hasBookmark(forKey: codexKey))
        #expect(accessor.startedURLs.isEmpty)
        #expect(accessor.stoppedURLs.isEmpty)
    }

    @MainActor
    @Test("provider bookmark 会话分别恢复并分别释放")
    func providerSessionsRestoreAndStopIndependently() {
        let claudeKey = "ClaudeDataDirectoryBookmark"
        let codexKey = "CodexDataDirectoryBookmark"
        let sharedURL = URL(fileURLWithPath: "/shared", isDirectory: true)
        let resolver = MappingBookmarkDataResolver(values: [
            Data([1]): .init(url: sharedURL, isStale: false),
            Data([2]): .init(url: sharedURL, isStale: false),
        ])
        let accessor = RecordingResourceAccessor(startResult: true)
        let manager = SecurityScopedBookmarkManager(
            bookmarkDataResolver: resolver,
            bookmarkStore: ManagerBookmarkStore(values: [
                claudeKey: Data([1]),
                codexKey: Data([2]),
            ]),
            resourceAccessor: accessor
        )

        #expect(manager.restoreBookmarkAndAccess(forKey: claudeKey) == sharedURL)
        #expect(manager.restoreBookmarkAndAccess(forKey: codexKey) == sharedURL)
        #expect(accessor.startedURLs == [sharedURL, sharedURL])
        manager.stopAccessing(forKey: claudeKey)
        #expect(accessor.stoppedURLs == [sharedURL])
        #expect(manager.restoreBookmarkAndAccess(forKey: codexKey) == sharedURL)
        manager.stopAccessing(forKey: codexKey)
        manager.stopAccessing(forKey: codexKey)
        #expect(accessor.stoppedURLs == [sharedURL, sharedURL])
    }

    @MainActor
    @Test("stale bookmark 刷新成功会保存新数据并通过注入 accessor 释放")
    func staleRefreshSuccessPersistsFreshDataAndStopsThroughAccessor() {
        let key = "ClaudeDataDirectoryBookmark"
        let staleData = Data([1])
        let freshData = Data([9])
        let url = URL(fileURLWithPath: "/claude", isDirectory: true)
        let store = ManagerBookmarkStore(values: [key: staleData])
        let accessor = RecordingResourceAccessor(startResult: true)
        let manager = SecurityScopedBookmarkManager(
            bookmarkDataCreator: FixedManagerBookmarkDataCreator(data: freshData),
            bookmarkDataResolver: FixedBookmarkDataResolver(
                result: .init(url: url, isStale: true)
            ),
            bookmarkStore: store,
            resourceAccessor: accessor
        )

        #expect(manager.restoreBookmarkAndAccess(forKey: key) == url)
        #expect(store.data(forKey: key) == freshData)
        manager.stopAccessing(forKey: key)
        #expect(accessor.stoppedURLs == [url])
    }

    @MainActor
    @Test("stale bookmark 保存失败会停止访问且只清除当前 provider")
    func staleRefreshSaveFailureStopsAccessAndClearsOnlyCurrentProvider() {
        let claudeKey = "ClaudeDataDirectoryBookmark"
        let codexKey = "CodexDataDirectoryBookmark"
        let url = URL(fileURLWithPath: "/claude", isDirectory: true)
        let store = RejectingManagerBookmarkStore(values: [
            claudeKey: Data([1]),
            codexKey: Data([2]),
        ])
        let accessor = RecordingResourceAccessor(startResult: true)
        let manager = SecurityScopedBookmarkManager(
            bookmarkDataCreator: FixedManagerBookmarkDataCreator(data: Data([9])),
            bookmarkDataResolver: FixedBookmarkDataResolver(
                result: .init(url: url, isStale: true)
            ),
            bookmarkStore: store,
            resourceAccessor: accessor
        )

        #expect(manager.restoreBookmarkAndAccess(forKey: claudeKey) == nil)
        #expect(!manager.hasBookmark(forKey: claudeKey))
        #expect(manager.hasBookmark(forKey: codexKey))
        #expect(accessor.stoppedURLs == [url])
    }

    @MainActor
    @Test("stopAccessingAll 使用注入 accessor 且不会重复释放")
    func stopAccessingAllUsesInjectedAccessorWithoutDuplicateStops() {
        let claudeKey = "ClaudeDataDirectoryBookmark"
        let codexKey = "CodexDataDirectoryBookmark"
        let claudeURL = URL(fileURLWithPath: "/claude", isDirectory: true)
        let codexURL = URL(fileURLWithPath: "/codex", isDirectory: true)
        let accessor = RecordingResourceAccessor(startResult: true)
        let manager = SecurityScopedBookmarkManager(
            bookmarkDataResolver: MappingBookmarkDataResolver(values: [
                Data([1]): .init(url: claudeURL, isStale: false),
                Data([2]): .init(url: codexURL, isStale: false),
            ]),
            bookmarkStore: ManagerBookmarkStore(values: [
                claudeKey: Data([1]),
                codexKey: Data([2]),
            ]),
            resourceAccessor: accessor
        )

        #expect(manager.restoreBookmarkAndAccess(forKey: claudeKey) == claudeURL)
        #expect(manager.restoreBookmarkAndAccess(forKey: codexKey) == codexURL)
        manager.stopAccessingAll()
        #expect(Set(accessor.stoppedURLs) == Set([claudeURL, codexURL]))
        manager.stopAccessingAll()
        #expect(accessor.stoppedURLs.count == 2)
    }

    @MainActor
    @Test("stopAccessingAll 会按 bookmark key 释放同一 URL")
    func stopAccessingAllStopsSharedURLOncePerBookmarkKey() {
        let sharedURL = URL(fileURLWithPath: "/shared", isDirectory: true)
        let accessor = RecordingResourceAccessor(startResult: true)
        let manager = SecurityScopedBookmarkManager(
            bookmarkDataResolver: MappingBookmarkDataResolver(values: [
                Data([1]): .init(url: sharedURL, isStale: false),
                Data([2]): .init(url: sharedURL, isStale: false),
            ]),
            bookmarkStore: ManagerBookmarkStore(values: [
                "ClaudeDataDirectoryBookmark": Data([1]),
                "CodexDataDirectoryBookmark": Data([2]),
            ]),
            resourceAccessor: accessor
        )

        #expect(manager.restoreBookmarkAndAccess(
            forKey: "ClaudeDataDirectoryBookmark"
        ) == sharedURL)
        #expect(manager.restoreBookmarkAndAccess(
            forKey: "CodexDataDirectoryBookmark"
        ) == sharedURL)

        manager.stopAccessingAll()

        #expect(accessor.stoppedURLs == [sharedURL, sharedURL])
    }
}

private final class ManagerBookmarkStore: BookmarkDataStoring, @unchecked Sendable {
    private var values: [String: Data]
    private(set) var removedKeys: [String] = []

    init(values: [String: Data] = [:]) {
        self.values = values
    }

    func data(forKey key: String) -> Data? {
        values[key]
    }

    func save(_ data: Data, forKey key: String) -> Bool {
        values[key] = data
        return values[key] == data
    }

    func removeData(forKey key: String) {
        values[key] = nil
        removedKeys.append(key)
    }
}

private struct FixedManagerBookmarkDataCreator: BookmarkDataCreating {
    let data: Data
    func createBookmarkData(for url: URL) throws -> Data { data }
}

private enum ManagerBookmarkCreatorError: Error {
    case fixtureFailure
}

private struct ThrowingManagerBookmarkDataCreator: BookmarkDataCreating {
    func createBookmarkData(for url: URL) throws -> Data {
        throw ManagerBookmarkCreatorError.fixtureFailure
    }
}

private enum ManagerBookmarkResolverError: Error {
    case missingFixture
}

private struct FixedBookmarkDataResolver: BookmarkDataResolving {
    let result: ResolvedBookmark

    func resolveBookmarkData(_ data: Data) throws -> ResolvedBookmark {
        result
    }
}

private struct MappingBookmarkDataResolver: BookmarkDataResolving {
    let values: [Data: ResolvedBookmark]

    func resolveBookmarkData(_ data: Data) throws -> ResolvedBookmark {
        guard let result = values[data] else {
            throw ManagerBookmarkResolverError.missingFixture
        }
        return result
    }
}

private final class RecordingResourceAccessor: SecurityScopedResourceAccessing, @unchecked Sendable {
    private let lock = NSLock()
    private let startResult: Bool
    private var recordedStarts: [URL] = []
    private var recordedStops: [URL] = []

    init(startResult: Bool) {
        self.startResult = startResult
    }

    var startedURLs: [URL] {
        lock.lock()
        defer { lock.unlock() }
        return recordedStarts
    }

    var stoppedURLs: [URL] {
        lock.lock()
        defer { lock.unlock() }
        return recordedStops
    }

    func startAccessing(_ url: URL) -> Bool {
        lock.lock()
        recordedStarts.append(url)
        lock.unlock()
        return startResult
    }

    func stopAccessing(_ url: URL) {
        lock.lock()
        recordedStops.append(url)
        lock.unlock()
    }
}

@MainActor
private final class RecordingDirectoryPresenter: DirectoryPanelPresenting {
    let selection: URL?
    private(set) var requestedProviderIDs: [ProviderID] = []

    init(selection: URL?) {
        self.selection = selection
    }

    func chooseDirectory(
        for provider: any UsageProvider,
        language: AppLanguage
    ) async -> URL? {
        requestedProviderIDs.append(provider.id)
        return selection
    }
}

private final class RejectingManagerBookmarkStore: BookmarkDataStoring, @unchecked Sendable {
    private var values: [String: Data]

    init(values: [String: Data] = [:]) {
        self.values = values
    }

    func data(forKey key: String) -> Data? { values[key] }
    func save(_ data: Data, forKey key: String) -> Bool { false }

    func removeData(forKey key: String) {
        values[key] = nil
    }
}
