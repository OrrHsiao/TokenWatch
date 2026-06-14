import Foundation

/// Codex CLI / Codex Desktop 数据源
/// 装配 CodexRolloutScanner + CodexRolloutParser，适配 UsageProvider 协议
struct CodexProvider: UsageProvider {
    let id: ProviderID = .codex
    let displayName = "Codex"
    let bookmarkKey = "CodexDirectoryBookmark"
    let defaultDirectoryPath = NSString("~/.codex").expandingTildeInPath
    let openPanelMessage = "请选择 ~/.codex 目录以授权 TokenWatch 读取 Codex 用量数据"
    /// Codex 不暴露 cache write 概念，UI 该 Tab 不展示该行
    let hasCacheWriteDimension = false

    private let scanner = CodexRolloutScanner()
    private let parser = CodexRolloutParser()

    /// 扫描 Codex 目录下所有 rollout JSONL 文件并解析为统一条目
    /// - Parameter rootURL: 已授权的 ~/.codex 目录
    /// - Returns: 去重后的 ParsedUsageEntry 列表
    func loadEntries(from rootURL: URL) throws -> [ParsedUsageEntry] {
        let files = try scanner.scanAll(in: rootURL)
        return try parser.parseAllFiles(files)
    }
}
