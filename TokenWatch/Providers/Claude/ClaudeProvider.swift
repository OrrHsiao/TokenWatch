import Foundation

/// Claude Code 数据源
/// 装配现有 ClaudeJSONLScanner + ClaudeJSONLParser，适配 UsageProvider 协议
struct ClaudeProvider: UsageProvider {
    let id: ProviderID = .claude
    let displayName = "Claude Code"
    let bookmarkKey = "ClaudeDataDirectoryBookmark"
    let openPanelMessageKey: AppStringKey = .claudeDataDirectoryOpenPanelMessage
    let hasCacheWriteDimension = true
    let hasReasoningDimension = false

    private let scanner = ClaudeJSONLScanner()
    private let parser = ClaudeJSONLParser()

    /// 扫描 Claude 数据根下所有 JSONL 文件并解析为统一条目
    /// - Parameter dataRootURL: 已授权的 Claude 数据根
    /// - Returns: 去重后的 ParsedUsageEntry 列表
    func loadEntries(from dataRootURL: URL) throws -> [ParsedUsageEntry] {
        let files = try scanner.scanAllJSONLFiles(in: dataRootURL)
        return try parser.parseAllFiles(files, claudeDataRoot: dataRootURL)
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
