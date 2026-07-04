import Foundation

/// Provider 统一授权配置。方案 2:所有数据源共享一次用户目录授权。
enum ProviderAuthorization {
    static let homeBookmarkKey = "HomeDirectoryBookmark"
    static let homeDirectoryPath = FileManager.default.homeDirectoryForCurrentUser.path
    static let homeAccessMessage = AppStrings.text(.homeAccessMessage, language: .zhHans)
}

/// 抽象的数据源 provider
/// 职责：扫描自己的目录、解析自己的 JSONL 格式、产出统一的 ParsedUsageEntry
/// 不关心 Bookmark / 聚合 / 定价 — 这些在共享层完成
///
/// 设计参考 ccusage `adapter/` 模式：per-provider 自治 paths/parser/loader
protocol UsageProvider: Sendable {
    /// 唯一标识，用于 UI Tab / Bookmark key / 状态字典 key
    var id: ProviderID { get }
    /// UI Tab 标题
    var displayName: String { get }
    /// UserDefaults Bookmark 持久化键
    var bookmarkKey: String { get }
    /// NSOpenPanel 默认定位目录（绝对路径）
    var defaultDirectoryPath: String { get }
    /// NSOpenPanel 顶部说明文案
    var openPanelMessage: String { get }
    /// 该 provider 是否产出 cache write tokens（决定 UI 是否展示该行）
    /// Claude=true，Codex=false
    var hasCacheWriteDimension: Bool { get }
    /// 该 provider 是否暴露 reasoning token 维度(决定 UI 是否展示该行)
    /// Claude=false(无该字段)、Codex=false(reasoning 已并入 output)、opencode=true
    var hasReasoningDimension: Bool { get }

    /// 扫描+解析，产出统一条目
    /// - Parameter rootURL: 已通过 Security-Scoped Bookmark 取得访问权限的用户目录
    func loadEntries(from rootURL: URL) throws -> [ParsedUsageEntry]
}
