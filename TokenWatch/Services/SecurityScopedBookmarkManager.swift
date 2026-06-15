import Foundation
import AppKit

/// 管理多个 Security-Scoped Bookmark 的创建、存储和恢复
/// 每个 provider 使用自己的 bookmarkKey,数据互相独立
///
/// 历史 key `ClaudeDirectoryBookmark` 由 ClaudeProvider 复用,迁移用户无需重新授权
@MainActor
final class SecurityScopedBookmarkManager: Sendable {

    static let shared = SecurityScopedBookmarkManager()

    /// 每个 key 对应的会话状态(已恢复的 URL + 是否处于 startAccessing)
    private struct Session {
        var url: URL
        var isAccessing: Bool
    }
    private var sessions: [String: Session] = [:]

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
        // 已经在访问中 → 直接返回缓存 URL
        if let session = sessions[key], session.isAccessing {
            return session.url
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

        sessions[key] = Session(url: url, isAccessing: true)
        return url
    }

    /// 停止指定 key 的安全访问
    func stopAccessing(forKey key: String) {
        guard let session = sessions[key], session.isAccessing else { return }
        session.url.stopAccessingSecurityScopedResource()
        sessions[key] = nil
    }

    /// 停止所有 key 的安全访问(applicationWillTerminate 用)
    func stopAccessingAll() {
        for key in Array(sessions.keys) {
            stopAccessing(forKey: key)
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
