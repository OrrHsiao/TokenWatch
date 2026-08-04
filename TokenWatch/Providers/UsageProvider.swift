import Foundation

/// 用户选择的数据根是否包含当前 provider 所需的最小目录结构。
///
/// 该校验只用于发现明显选错的目录；结构正确但暂时没有可解析记录时仍应视为有效选择。
enum ProviderDataRootValidationResult: Sendable, Equatable {
    case valid
    case missingExpectedStructure
}

/// Provider 一轮扫描的结果；JSONL provider 可在源未变化时省略大量 entry 物化。
struct UsageProviderLoadResult: Sendable {
    let entries: [ParsedUsageEntry]?
    let didChange: Bool
    let sourceRevision: String?
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

    /// 扫描数据源并返回可跨进程校验的变化状态。
    /// - Parameters:
    ///   - dataRootURL: 已通过当前 provider bookmark 恢复访问的数据根。
    ///   - materializeEntriesWhenUnchanged: `false` 时，支持该能力的 provider
    ///     可在源版本未变化时返回 `nil` entries，让上层直接复用统计快照。
    func loadEntriesWithCacheStatus(
        from dataRootURL: URL,
        materializeEntriesWhenUnchanged: Bool
    ) throws -> UsageProviderLoadResult

    /// 校验用户选择的数据根是否包含当前 provider 的必要文件或目录。
    /// - Parameter dataRootURL: 已通过当前 provider bookmark 恢复访问的数据根。
    /// - Returns: 目录结构存在时返回 `.valid`；否则返回 `.missingExpectedStructure`。
    func validateDataRoot(
        _ dataRootURL: URL
    ) -> ProviderDataRootValidationResult
}

extension UsageProvider {
    /// 不支持增量源版本的 provider 保持原有语义：读取完整 entries 并视为已变化。
    func loadEntriesWithCacheStatus(
        from dataRootURL: URL,
        materializeEntriesWhenUnchanged: Bool
    ) throws -> UsageProviderLoadResult {
        _ = materializeEntriesWhenUnchanged
        return UsageProviderLoadResult(
            entries: try loadEntries(from: dataRootURL),
            didChange: true,
            sourceRevision: nil
        )
    }

    /// 默认不额外约束目录结构，供测试替身及未来兼容 provider 使用。
    func validateDataRoot(
        _ dataRootURL: URL
    ) -> ProviderDataRootValidationResult {
        .valid
    }
}
