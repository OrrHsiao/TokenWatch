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
            panel.directoryURL = FileManager.default.homeDirectoryForCurrentUser

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
    /// 如果 Bookmark 过期（isStale），尝试用现有 URL 重建
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
            return nil
        }

        if isStale {
            // Bookmark 过期，用现有 URL 重建
            _ = url.startAccessingSecurityScopedResource()
            url.stopAccessingSecurityScopedResource()
            createAndSaveBookmark(for: url)
        }

        guard url.startAccessingSecurityScopedResource() else {
            return nil
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
