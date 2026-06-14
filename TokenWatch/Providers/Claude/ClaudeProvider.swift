import Foundation

/// Claude Code 数据源
/// 装配现有 ClaudeJSONLScanner + ClaudeJSONLParser，适配 UsageProvider 协议
struct ClaudeProvider: UsageProvider {
    let id: ProviderID = .claude
    let displayName = "Claude Code"
    // bookmarkKey 与历史版本兼容，勿改 — 已有用户 UserDefaults 中存的就是这个 key
    let bookmarkKey = "ClaudeDirectoryBookmark"
    let defaultDirectoryPath = NSString("~/.claude").expandingTildeInPath
    let openPanelMessage = "请选择 ~/.claude 目录以授权 TokenWatch 读取 Claude Code 用量数据"
    let hasCacheWriteDimension = true

    private let scanner = ClaudeJSONLScanner()
    private let parser = ClaudeJSONLParser()

    /// 扫描 Claude 目录下所有 JSONL 文件并解析为统一条目
    /// - Parameter rootURL: 已授权的 ~/.claude 目录
    /// - Returns: 去重后的 ParsedUsageEntry 列表
    func loadEntries(from rootURL: URL) throws -> [ParsedUsageEntry] {
        let files = try scanner.scanAllJSONLFiles(in: rootURL)
        return try parser.parseAllFiles(files, claudeDataRoot: rootURL)
    }
}
