import Foundation

/// Codex CLI / Codex Desktop 数据源
/// 装配 CodexRolloutScanner + CodexRolloutParser，适配 UsageProvider 协议
struct CodexProvider: UsageProvider {
    /// v5 新增快照去重状态；旧缓存已包含重复用量，必须从源日志重新解析。
    static let currentDiskCacheVersion = 5
    static let compatibleDiskCacheVersions: Set<Int> = []

    /// 数据目录 bookmark 键；订阅额度读取复用同一授权。
    static let dataDirectoryBookmarkKey = "CodexDataDirectoryBookmark"

    let id: ProviderID = .codex
    let displayName = "Codex"
    let bookmarkKey = CodexProvider.dataDirectoryBookmarkKey
    let openPanelMessageKey: AppStringKey = .codexDataDirectoryOpenPanelMessage
    /// Codex 不暴露 cache write 概念，UI 该 Tab 不展示该行
    let hasCacheWriteDimension = false
    /// Codex 的 reasoning 已并入 output_tokens,不单列维度
    let hasReasoningDimension = false

    private let scanner: CodexRolloutScanner
    private let parser: CodexRolloutParser
    private let serviceTierResolver: CodexServiceTierResolver

    init(
        scanner: CodexRolloutScanner = CodexRolloutScanner(),
        parser: CodexRolloutParser = CodexRolloutParser(
            diskStore: SystemJSONLDiskCacheStore(
                namespace: "codex",
                cacheVersion: CodexProvider.currentDiskCacheVersion,
                compatibleCacheVersions: CodexProvider.compatibleDiskCacheVersions
            )
        ),
        serviceTierResolver: CodexServiceTierResolver = CodexServiceTierResolver()
    ) {
        self.scanner = scanner
        self.parser = parser
        self.serviceTierResolver = serviceTierResolver
    }

    /// 扫描 Codex 数据根下所有 rollout JSONL 文件并解析为统一条目
    /// - Parameter dataRootURL: 已授权的 Codex 数据根
    /// - Returns: 去重后的 ParsedUsageEntry 列表
    func loadEntries(from dataRootURL: URL) throws -> [ParsedUsageEntry] {
        try loadEntriesWithCacheStatus(
            from: dataRootURL,
            materializeEntriesWhenUnchanged: true
        ).entries ?? []
    }

    /// 扫描文件元数据并返回可与统计快照绑定的源版本。
    func loadEntriesWithCacheStatus(
        from dataRootURL: URL,
        materializeEntriesWhenUnchanged: Bool
    ) throws -> UsageProviderLoadResult {
        let files = try scanner.scanAll(in: dataRootURL)
        let speed = serviceTierResolver.pricingSpeed(at: dataRootURL)
        let result = try parser.parseAllFilesWithCacheStatus(
            files,
            pricingSpeed: speed,
            materializeEntriesWhenUnchanged: materializeEntriesWhenUnchanged
        )
        return UsageProviderLoadResult(
            entries: result.candidates,
            didChange: result.didChange,
            sourceRevision: result.sourceRevision
        )
    }

    /// 接受包含 `sessions/` 或 `archived_sessions/` 的 Codex 数据根。
    func validateDataRoot(
        _ dataRootURL: URL
    ) -> ProviderDataRootValidationResult {
        for directoryName in ["sessions", "archived_sessions"] {
            let directoryURL = dataRootURL.appendingPathComponent(
                directoryName,
                isDirectory: true
            )
            var isDirectory: ObjCBool = false
            let exists = FileManager.default.fileExists(
                atPath: directoryURL.path,
                isDirectory: &isDirectory
            )
            if exists && isDirectory.boolValue {
                return .valid
            }
        }
        return .missingExpectedStructure
    }
}
