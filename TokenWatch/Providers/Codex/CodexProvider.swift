import Foundation

/// Codex CLI / Codex Desktop 数据源
/// 装配 CodexRolloutScanner + CodexRolloutParser，适配 UsageProvider 协议
struct CodexProvider: UsageProvider {
    let id: ProviderID = .codex
    let displayName = "Codex"
    let bookmarkKey = "CodexDataDirectoryBookmark"
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
        parser: CodexRolloutParser = CodexRolloutParser(),
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
        let files = try scanner.scanAll(in: dataRootURL)
        let speed = serviceTierResolver.pricingSpeed(at: dataRootURL)
        return try parser.parseAllFiles(files, pricingSpeed: speed)
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
