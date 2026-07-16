import Foundation

/// opencode (https://opencode.ai) 数据源
/// 装配 OpenCodeSQLiteScanner + OpenCodeMessageParser,适配 UsageProvider 协议
struct OpenCodeProvider: UsageProvider {
    let id: ProviderID = .opencode
    let displayName = "opencode"
    let bookmarkKey = "OpenCodeDataDirectoryBookmark"
    let openPanelMessageKey: AppStringKey = .openCodeDataDirectoryOpenPanelMessage
    /// opencode 的 cache.write 含义与 Anthropic cache_creation 不完全等价,数据层映射保留但 UI 暂不展示
    let hasCacheWriteDimension = false
    /// opencode 显式暴露 reasoning_tokens(GPT-5/o3 系列)
    let hasReasoningDimension = true

    private let scanner = OpenCodeSQLiteScanner()
    private let parser = OpenCodeMessageParser()

    /// 扫描 opencode.db 并解析为统一条目
    /// - Parameter dataRootURL: 已授权的 opencode 数据根
    /// - Returns: ParsedUsageEntry 列表(messageId 由 SQLite PK 保证全局唯一,无需去重)
    func loadEntries(from dataRootURL: URL) throws -> [ParsedUsageEntry] {
        let rows = try scanner.scanAll(in: dataRootURL)
        return parser.parseAll(rows)
    }
}
