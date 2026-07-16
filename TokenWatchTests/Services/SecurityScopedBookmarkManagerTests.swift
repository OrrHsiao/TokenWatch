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
        ).message == "Choose the Claude Code data folder")
        #expect(SecurityScopedBookmarkManager.openPanelCopy(
            for: CodexProvider(),
            language: .en
        ).message == "Choose the Codex data folder")
        #expect(SecurityScopedBookmarkManager.openPanelCopy(
            for: OpenCodeProvider(),
            language: .en
        ).message == "Choose the opencode data folder")
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
        #expect(panel.message == "Choose the Codex data folder")
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
