import Foundation

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
    /// NSOpenPanel 顶部说明文案的本地化键
    var openPanelMessageKey: AppStringKey { get }
    /// 该 provider 是否产出 cache write tokens（决定 UI 是否展示该行）
    /// Claude=true，Codex=false
    var hasCacheWriteDimension: Bool { get }
    /// 该 provider 是否暴露 reasoning token 维度(决定 UI 是否展示该行)
    /// Claude=false(无该字段)、Codex=false(reasoning 已并入 output)、opencode=true
    var hasReasoningDimension: Bool { get }

    /// 从用户直接选择的 provider 数据根目录读取用量。
    /// - Parameter dataRootURL: 已通过当前 provider bookmark 恢复访问的数据根。
    /// - Returns: 解析并去重后的统一用量条目。
    func loadEntries(from dataRootURL: URL) throws -> [ParsedUsageEntry]
}
