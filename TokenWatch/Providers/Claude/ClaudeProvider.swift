import Foundation

/// Claude Code 数据源
/// 装配现有 ClaudeJSONLScanner + ClaudeJSONLParser，适配 UsageProvider 协议
struct ClaudeProvider: UsageProvider {
    /// Claude v2 可能已缓存缺行状态，因此 v3 不兼容任何旧版本。
    static let currentDiskCacheVersion = 3
    static let compatibleDiskCacheVersions: Set<Int> = []

    let id: ProviderID = .claude
    let displayName = "Claude Code"
    let bookmarkKey = "ClaudeDataDirectoryBookmark"
    let openPanelMessageKey: AppStringKey = .claudeDataDirectoryOpenPanelMessage
    let hasCacheWriteDimension = true
    let hasReasoningDimension = false

    private let scanner = ClaudeJSONLScanner()
    private let parser = ClaudeJSONLParser(
        diskStore: SystemJSONLDiskCacheStore(
            namespace: "claude",
            cacheVersion: ClaudeProvider.currentDiskCacheVersion,
            compatibleCacheVersions: ClaudeProvider.compatibleDiskCacheVersions
        )
    )

    /// 扫描 Claude 数据根下所有 JSONL 文件并解析为统一条目
    /// - Parameter dataRootURL: 已授权的 Claude 数据根
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
        let files = try scanner.scanAllJSONLFiles(in: dataRootURL)
        let result = try parser.parseAllFilesWithCacheStatus(
            files,
            claudeDataRoot: dataRootURL,
            materializeEntriesWhenUnchanged: materializeEntriesWhenUnchanged
        )
        return UsageProviderLoadResult(
            entries: result.candidates,
            didChange: result.didChange,
            sourceRevision: result.sourceRevision
        )
    }

    /// 仅接受包含 `projects/` 的 Claude Code 数据根，避免将 Home 等上级目录误当作数据目录。
    func validateDataRoot(
        _ dataRootURL: URL
    ) -> ProviderDataRootValidationResult {
        let projectsURL = dataRootURL.appendingPathComponent(
            "projects",
            isDirectory: true
        )
        var isDirectory: ObjCBool = false
        let exists = FileManager.default.fileExists(
            atPath: projectsURL.path,
            isDirectory: &isDirectory
        )
        return exists && isDirectory.boolValue
            ? .valid
            : .missingExpectedStructure
    }
}
