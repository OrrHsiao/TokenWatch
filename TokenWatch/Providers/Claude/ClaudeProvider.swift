import Foundation

/// Claude Code 数据源
/// 装配现有 ClaudeJSONLScanner + ClaudeJSONLParser，适配 UsageProvider 协议
struct ClaudeProvider: UsageProvider {
    let id: ProviderID = .claude
    let displayName = "Claude Code"
    let bookmarkKey = ProviderAuthorization.homeBookmarkKey
    let openPanelMessage = ProviderAuthorization.homeAccessMessage
    let hasCacheWriteDimension = true
    let hasReasoningDimension = false

    private let scanner = ClaudeJSONLScanner()
    private let parser = ClaudeJSONLParser()

    /// 扫描 Claude 目录下所有 JSONL 文件并解析为统一条目
    /// - Parameter rootURL: 已授权的用户目录
    /// - Returns: 去重后的 ParsedUsageEntry 列表
    func loadEntries(from rootURL: URL) throws -> [ParsedUsageEntry] {
        let claudeRoot = rootURL.appendingPathComponent(".claude", isDirectory: true)
        let files = try scanner.scanAllJSONLFiles(in: claudeRoot)
        return try parser.parseAllFiles(files, claudeDataRoot: claudeRoot)
    }
}
