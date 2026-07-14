import Foundation
import AppKit
import os.log

/// ViewModel 需要的 Bookmark 访问能力。
/// 生产实现仍由 `SecurityScopedBookmarkManager` 提供,测试可注入轻量 fake。
@MainActor
protocol BookmarkAccessManaging: Sendable {
    /// 是否已保存指定 key 的 bookmark。
    func hasBookmark(forKey key: String) -> Bool

    /// 请求用户选择 provider 目录并保存 bookmark。
    /// - Returns: 授权后的目录;取消时返回 nil。
    func promptUserToSelectDirectory(forProvider provider: any UsageProvider) async -> URL?

    /// 恢复 bookmark 并开始 security-scoped 访问。
    /// - Returns: 可访问目录;失败时返回 nil。
    func restoreBookmarkAndAccess(forKey key: String) -> URL?

    /// 停止一次对应 key 的 security-scoped 访问。
    func stopAccessing(forKey key: String)
}

/// 记录当前进程内 security-scoped URL 的逻辑访问次数。
/// 同一个 bookmark key 可能被多个 provider 并发复用,只有成对释放到 0 时才真正 stopAccessing。
struct SecurityScopedAccessSessions: Sendable {
    private struct Session: Sendable {
        let url: URL
        var referenceCount: Int
    }

    private var sessions: [String: Session] = [:]

    mutating func retainExisting(forKey key: String) -> URL? {
        guard var session = sessions[key] else { return nil }
        session.referenceCount += 1
        sessions[key] = session
        return session.url
    }

    mutating func insert(_ url: URL, forKey key: String) {
        sessions[key] = Session(url: url, referenceCount: 1)
    }

    mutating func release(forKey key: String) -> URL? {
        guard var session = sessions[key] else { return nil }
        guard session.referenceCount <= 1 else {
            session.referenceCount -= 1
            sessions[key] = session
            return nil
        }
        sessions[key] = nil
        return session.url
    }

    mutating func removeAll() -> [URL] {
        let urls = sessions.values.map(\.url)
        sessions.removeAll()
        return urls
    }
}

/// 管理多个 Security-Scoped Bookmark 的创建、存储和恢复
/// provider 可以共享同一个 bookmarkKey,因此同一 URL 的访问会做引用计数
@MainActor
final class SecurityScopedBookmarkManager: BookmarkAccessManaging {

    static let shared = SecurityScopedBookmarkManager()

    struct OpenPanelCopy: Equatable {
        let message: String
        let prompt: String
    }

    private let bookmarkDataCreator: any BookmarkDataCreating
    private let bookmarkStore: any BookmarkDataStoring
    private let logger = Logger(
        subsystem: "com.xiaoao.TokenWatch",
        category: "SecurityScopedBookmarkManager"
    )

    /// 每个 key 对应的会话状态(已恢复的 URL + 当前逻辑访问次数)
    private var sessions = SecurityScopedAccessSessions()

    init(
        bookmarkDataCreator: any BookmarkDataCreating = SecurityScopedBookmarkDataCreator(),
        bookmarkStore: any BookmarkDataStoring = UserDefaultsBookmarkStore()
    ) {
        self.bookmarkDataCreator = bookmarkDataCreator
        self.bookmarkStore = bookmarkStore
    }

    nonisolated static func openPanelCopy(language: AppLanguage) -> OpenPanelCopy {
        OpenPanelCopy(
            message: AppStrings.text(.homeAccessMessage, language: language),
            prompt: AppStrings.text(.authorizeAccessPrompt, language: language)
        )
    }

    /// 创建未预设初始目录的标准授权面板。
    /// - Parameter language: 面板提示文案使用的语言。
    /// - Returns: 仅允许用户单选目录的 `NSOpenPanel`。
    static func makeOpenPanel(language: AppLanguage) -> NSOpenPanel {
        let panel = NSOpenPanel()
        configureOpenPanel(panel, language: language)
        return panel
    }

    /// 配置标准授权面板，不覆盖系统管理的初始目录。
    /// - Parameters:
    ///   - panel: 待配置的目录选择面板。
    ///   - language: 面板提示文案使用的语言。
    static func configureOpenPanel(_ panel: NSOpenPanel, language: AppLanguage) {
        let copy = openPanelCopy(language: language)
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.message = copy.message
        panel.prompt = copy.prompt
        panel.showsHiddenFiles = true
        panel.treatsFilePackagesAsDirectories = true
    }

    // MARK: - 查询

    /// 是否已存储该 key 对应的 Bookmark
    func hasBookmark(forKey key: String) -> Bool {
        bookmarkStore.data(forKey: key) != nil
    }

    // MARK: - 授权流程

    /// 通过 NSOpenPanel 让用户主动选择授权目录
    /// 选择后创建 Security-Scoped Bookmark 并持久化到 UserDefaults
    func promptUserToSelectDirectory(forProvider provider: any UsageProvider) async -> URL? {
        return await withCheckedContinuation { continuation in
            let panel = Self.makeOpenPanel(language: AppLanguageSettings.shared.resolvedLanguage)

            let key = provider.bookmarkKey
            panel.begin { [weak self] response in
                guard response == .OK, let url = panel.url else {
                    continuation.resume(returning: nil)
                    return
                }
                continuation.resume(
                    returning: self?.persistSelectedDirectory(url, forKey: key)
                )
            }
        }
    }

    /// 创建并验证保存所选目录的 bookmark；失败时不返回假授权 URL。
    /// - Parameters:
    ///   - url: 用户选中的目录。
    ///   - key: 保存 bookmark data 的键。
    /// - Returns: 创建与保存均成功时返回原目录，否则返回 nil。
    func persistSelectedDirectory(_ url: URL, forKey key: String) -> URL? {
        do {
            let data = try bookmarkDataCreator.createBookmarkData(for: url)
            guard bookmarkStore.save(data, forKey: key) else {
                logger.error("Bookmark 保存验证失败: \(key)")
                return nil
            }
            return url
        } catch {
            logger.error("Bookmark 创建失败: \(error.localizedDescription)")
            return nil
        }
    }

    // MARK: - Bookmark 恢复

    /// 从 UserDefaults 恢复指定 key 的 Bookmark 并 startAccessing
    /// stale 处理:解析得到的 URL 仍可临时使用,startAccessing 后立即用其重建 bookmark
    func restoreBookmarkAndAccess(forKey key: String) -> URL? {
        // 已经在访问中 → 增加逻辑引用,避免共享 key 的并发读取被提前 stop
        if let url = sessions.retainExisting(forKey: key) {
            return url
        }

        guard let bookmarkData = bookmarkStore.data(forKey: key) else {
            return nil
        }

        var isStale = false
        guard let url = try? URL(
            resolvingBookmarkData: bookmarkData,
            options: .withSecurityScope,
            relativeTo: nil,
            bookmarkDataIsStale: &isStale
        ) else {
            bookmarkStore.removeData(forKey: key)
            return nil
        }

        guard url.startAccessingSecurityScopedResource() else {
            bookmarkStore.removeData(forKey: key)
            return nil
        }

        if isStale {
            do {
                let fresh = try bookmarkDataCreator.createBookmarkData(for: url)
                if !bookmarkStore.save(fresh, forKey: key) {
                    logger.error("过期 Bookmark 重存验证失败: \(key)")
                }
            } catch {
                logger.error("过期 Bookmark 重建失败: \(error.localizedDescription)")
            }
        }

        sessions.insert(url, forKey: key)
        return url
    }

    /// 停止指定 key 的安全访问
    func stopAccessing(forKey key: String) {
        guard let url = sessions.release(forKey: key) else { return }
        url.stopAccessingSecurityScopedResource()
    }

    /// 停止所有 key 的安全访问(applicationWillTerminate 用)
    func stopAccessingAll() {
        for url in sessions.removeAll() {
            url.stopAccessingSecurityScopedResource()
        }
    }

}
