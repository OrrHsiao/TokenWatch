import Foundation

/// Antigravity (Google DeepMind Antigravity / AGY) 数据源
/// 装配 AntigravitySQLiteScanner + AntigravityMessageParser，适配 UsageProvider 协议
struct AntigravityProvider: UsageProvider {
    let id: ProviderID = .antigravity
    let displayName = "Antigravity"
    let bookmarkKey = "AntigravityDataDirectoryBookmark"
    let openPanelMessageKey: AppStringKey = .antigravityDataDirectoryOpenPanelMessage
    /// Google Gemini 上下文缓存计费为 cache read，不暴露显式 cache write 维度
    let hasCacheWriteDimension = false
    /// Gemini 思考模型（如 Flash/Pro High thinking）显式暴露 thoughts_token_count
    let hasReasoningDimension = true

    private let scanner: AntigravitySQLiteScanner
    private let parser: AntigravityMessageParser

    init(
        scanner: AntigravitySQLiteScanner = AntigravitySQLiteScanner(),
        parser: AntigravityMessageParser = AntigravityMessageParser()
    ) {
        self.scanner = scanner
        self.parser = parser
    }

    /// 扫描 Antigravity 数据根下所有会话数据库并解析为统一条目
    /// - Parameter dataRootURL: 已授权的 Antigravity 数据根（如 `~/.gemini/antigravity`）
    /// - Returns: 去重后的 ParsedUsageEntry 列表
    func loadEntries(from dataRootURL: URL) throws -> [ParsedUsageEntry] {
        let scanResults = try scanner.scanAll(in: dataRootURL)
        return parser.parseAll(scanResults)
    }

    /// 校验用户选择的数据根是否包含 Antigravity 必要文件或目录
    ///
    /// 接受以下几种有效形态：
    /// 1. 包含 `conversations/` 目录（桌面端或 CLI 根）
    /// 2. 包含 `antigravity/conversations` 或 `antigravity-cli/conversations`（`~/.gemini` 根）
    /// 3. 直接选择包含 `*.db` 数据库文件的目录
    func validateDataRoot(_ dataRootURL: URL) -> ProviderDataRootValidationResult {
        let dbFiles = scanner.locateDatabaseFiles(in: dataRootURL)
        if !dbFiles.isEmpty {
            return .valid
        }

        // 即使当下无 .db，只要具备 conversations/ 目录结构即可视为有效授权
        let directConversations = dataRootURL.appendingPathComponent("conversations", isDirectory: true)
        var isDir: ObjCBool = false
        if FileManager.default.fileExists(atPath: directConversations.path, isDirectory: &isDir), isDir.boolValue {
            return .valid
        }

        for sub in ["antigravity", "antigravity-cli"] {
            let nested = dataRootURL.appendingPathComponent(sub, isDirectory: true)
                .appendingPathComponent("conversations", isDirectory: true)
            var nestedIsDir: ObjCBool = false
            if FileManager.default.fileExists(atPath: nested.path, isDirectory: &nestedIsDir), nestedIsDir.boolValue {
                return .valid
            }
        }

        return .missingExpectedStructure
    }
}
