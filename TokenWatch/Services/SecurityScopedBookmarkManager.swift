import Foundation
import AppKit

/// 管理 Security-Scoped Bookmark 的创建、存储和恢复
/// 这是 Sandbox 适配的核心：通过 NSOpenPanel 让用户授权访问 ~/.claude 目录
/// 然后将访问权限持久化为 Bookmark，后续启动无需重复授权
///
/// 参考 TokenTracker 的授权流程设计
@MainActor
final class SecurityScopedBookmarkManager: Sendable {

    static let shared = SecurityScopedBookmarkManager()

    private let bookmarkKey = "ClaudeDirectoryBookmark"
    private var cachedURL: URL?
    private var isAccessing = false

    /// 检查是否已有存储的 Bookmark
    var hasBookmark: Bool {
        UserDefaults.standard.data(forKey: bookmarkKey) != nil
    }

    // MARK: - 授权流程

    /// 通过 NSOpenPanel 让用户选择 ~/.claude 目录
    /// 选择后创建 Security-Scoped Bookmark 并持久化到 UserDefaults
    /// - Returns: 用户选择的目录 URL，取消返回 nil
    func promptUserToSelectClaudeDirectory() async -> URL? {
        return await withCheckedContinuation { continuation in
            let panel = NSOpenPanel()
            panel.canChooseDirectories = true
            panel.canChooseFiles = false
            panel.allowsMultipleSelection = false
            panel.message = "请选择 ~/.claude 目录以授权 TokenWatch 读取用量数据"
            panel.prompt = "授权访问"
            panel.showsHiddenFiles = true                       // 默认显示隐藏目录
            panel.treatsFilePackagesAsDirectories = true
            // 默认定位到 ~/.claude（若不存在则回退至 home），减少用户操作步骤
            let claudeDir = FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent(".claude", isDirectory: true)
            if FileManager.default.fileExists(atPath: claudeDir.path) {
                panel.directoryURL = claudeDir
            } else {
                panel.directoryURL = FileManager.default.homeDirectoryForCurrentUser
            }

            panel.begin { [weak self] response in
                guard response == .OK, let url = panel.url else {
                    continuation.resume(returning: nil)
                    return
                }
                self?.createAndSaveBookmark(for: url)
                continuation.resume(returning: url)
            }
        }
    }

    // MARK: - Bookmark 恢复

    /// 从 UserDefaults 恢复 Bookmark 并开始安全访问
    ///
    /// stale 处理：Apple 文档说明，stale bookmark 解析得到的 URL 仍可临时使用，
    /// 但应尽快用该 URL 重建 bookmark；若重建失败（例如目录已被删除/移动），
    /// 则清空持久化数据并要求重新授权，而不是无声继续以失效凭据访问。
    /// - Returns: 成功恢复访问的目录 URL，失败返回 nil
    func restoreBookmarkAndAccess() -> URL? {
        guard !isAccessing else { return cachedURL }

        guard let bookmarkData = UserDefaults.standard.data(forKey: bookmarkKey) else {
            return nil
        }

        var isStale = false
        guard let url = try? URL(
            resolvingBookmarkData: bookmarkData,
            options: .withSecurityScope,
            relativeTo: nil,
            bookmarkDataIsStale: &isStale
        ) else {
            // bookmark 完全无法解析（数据损坏或目录失效），清理并要求重新授权
            UserDefaults.standard.removeObject(forKey: bookmarkKey)
            return nil
        }

        guard url.startAccessingSecurityScopedResource() else {
            // 即便 URL 解出来,沙盒也可能拒绝访问 → 清理 bookmark 走重新授权
            UserDefaults.standard.removeObject(forKey: bookmarkKey)
            return nil
        }

        if isStale {
            // 在已 startAccessing 的状态下用当前 URL 重建 bookmark；失败不影响本次访问
            if let fresh = try? url.bookmarkData(
                options: .withSecurityScope,
                includingResourceValuesForKeys: nil,
                relativeTo: nil
            ) {
                UserDefaults.standard.set(fresh, forKey: bookmarkKey)
            }
        }

        isAccessing = true
        cachedURL = url
        return url
    }

    /// 停止安全访问，释放资源
    func stopAccessing() {
        if let url = cachedURL, isAccessing {
            url.stopAccessingSecurityScopedResource()
        }
        isAccessing = false
        cachedURL = nil
    }

    // MARK: - Private

    /// 创建 Security-Scoped Bookmark 并保存到 UserDefaults
    private func createAndSaveBookmark(for url: URL) {
        guard let bookmarkData = try? url.bookmarkData(
            options: .withSecurityScope,
            includingResourceValuesForKeys: nil,
            relativeTo: nil
        ) else {
            return
        }
        UserDefaults.standard.set(bookmarkData, forKey: bookmarkKey)
    }
}
