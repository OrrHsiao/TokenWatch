import Foundation

/// opencode (https://opencode.ai) 数据源
/// 装配 OpenCodeSQLiteScanner + OpenCodeMessageParser,适配 UsageProvider 协议
struct OpenCodeProvider: UsageProvider {
    let id: ProviderID = .opencode
    let displayName = "opencode"
    let bookmarkKey = ProviderAuthorization.homeBookmarkKey
    let openPanelMessage = ProviderAuthorization.homeAccessMessage
    /// opencode 的 cache.write 含义与 Anthropic cache_creation 不完全等价,数据层映射保留但 UI 暂不展示
    let hasCacheWriteDimension = false
    /// opencode 显式暴露 reasoning_tokens(GPT-5/o3 系列)
    let hasReasoningDimension = true

    private let scanner = OpenCodeSQLiteScanner()
    private let parser = OpenCodeMessageParser()

    /// 扫描 opencode.db 并解析为统一条目
    /// - Parameter rootURL: 已授权的用户目录
    /// - Returns: ParsedUsageEntry 列表(messageId 由 SQLite PK 保证全局唯一,无需去重)
    func loadEntries(from rootURL: URL) throws -> [ParsedUsageEntry] {
        let openCodeRoot = rootURL
            .appendingPathComponent(".local", isDirectory: true)
            .appendingPathComponent("share", isDirectory: true)
            .appendingPathComponent("opencode", isDirectory: true)
        let rows = try scanner.scanAll(in: openCodeRoot)
        return parser.parseAll(rows)
    }
}
