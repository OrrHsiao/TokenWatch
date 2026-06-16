import Foundation
import AppKit

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
final class SecurityScopedBookmarkManager: Sendable {

    static let shared = SecurityScopedBookmarkManager()

    /// 每个 key 对应的会话状态(已恢复的 URL + 当前逻辑访问次数)
    private var sessions = SecurityScopedAccessSessions()

    // MARK: - 查询

    /// 是否已存储该 key 对应的 Bookmark
    func hasBookmark(forKey key: String) -> Bool {
        UserDefaults.standard.data(forKey: key) != nil
    }

    // MARK: - 授权流程

    /// 通过 NSOpenPanel 让用户选择 provider 默认目录
    /// 选择后创建 Security-Scoped Bookmark 并持久化到 UserDefaults
    func promptUserToSelectDirectory(forProvider provider: any UsageProvider) async -> URL? {
        return await withCheckedContinuation { continuation in
            let panel = NSOpenPanel()
            panel.canChooseDirectories = true
            panel.canChooseFiles = false
            panel.allowsMultipleSelection = false
            panel.message = provider.openPanelMessage
            panel.prompt = "授权访问"
            panel.showsHiddenFiles = true
            panel.treatsFilePackagesAsDirectories = true

            // 默认定位到 provider 期望的目录;不存在则回退到 home
            let target = URL(fileURLWithPath: provider.defaultDirectoryPath, isDirectory: true)
            if FileManager.default.fileExists(atPath: target.path) {
                panel.directoryURL = target
            } else {
                panel.directoryURL = FileManager.default.homeDirectoryForCurrentUser
            }

            let key = provider.bookmarkKey
            panel.begin { [weak self] response in
                guard response == .OK, let url = panel.url else {
                    continuation.resume(returning: nil)
                    return
                }
                self?.createAndSaveBookmark(for: url, key: key)
                continuation.resume(returning: url)
            }
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

        guard let bookmarkData = UserDefaults.standard.data(forKey: key) else {
            return nil
        }

        var isStale = false
        guard let url = try? URL(
            resolvingBookmarkData: bookmarkData,
            options: .withSecurityScope,
            relativeTo: nil,
            bookmarkDataIsStale: &isStale
        ) else {
            UserDefaults.standard.removeObject(forKey: key)
            return nil
        }

        guard url.startAccessingSecurityScopedResource() else {
            UserDefaults.standard.removeObject(forKey: key)
            return nil
        }

        if isStale {
            if let fresh = try? url.bookmarkData(
                options: .withSecurityScope,
                includingResourceValuesForKeys: nil,
                relativeTo: nil
            ) {
                UserDefaults.standard.set(fresh, forKey: key)
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

    // MARK: - Private

    private func createAndSaveBookmark(for url: URL, key: String) {
        guard let bookmarkData = try? url.bookmarkData(
            options: .withSecurityScope,
            includingResourceValuesForKeys: nil,
            relativeTo: nil
        ) else {
            return
        }
        UserDefaults.standard.set(bookmarkData, forKey: key)
    }
}
