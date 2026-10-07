import Foundation
import os.log

/// DeepSeek Harness（DSH）数据源。
///
/// 数据来自 DSH 的会话日志 `~/.dsh/sessions/--<cwd>--/<session-id>/session[.vN].jsonl[.zstd]`：
/// 每条 `assistant/message` / `assistant/attempt` 事件都带有 provider 上报的真实用量，
/// 并附带模型、上游 route、turn/step 与毫秒时间戳，足以支撑按模型 / 小时 / 项目 / 会话
/// / 子代理的全部聚合维度。
///
/// 与其它 provider 的差异：
/// - 日志默认是多帧 zstd，需要内置解码器（见 `TokenWatch/Vendor/Zstd/README.md`）；
/// - 逐条用量存在「同 (turn, step) 替换」与「重试累加」语义，按 DSH 官方投影折叠；
/// - 费用不记录在日志里，由 DSH 自带的 pi-ai 定价目录本地计算。
struct DeepSeekHarnessProvider: UsageProvider {
    /// 磁盘缓存版本；折叠语义或状态结构变化时提升。
    static let currentDiskCacheVersion = 1
    static let compatibleDiskCacheVersions: Set<Int> = []

    let id: ProviderID = .deepSeekHarness
    let displayName = "DeepSeek Harness"
    let bookmarkKey = "DeepSeekHarnessDataDirectoryBookmark"
    let openPanelMessageKey: AppStringKey = .deepSeekHarnessDataDirectoryOpenPanelMessage
    /// DSH 的 wire 字段是 Anthropic 风格（`cache_creation_input_tokens`），能力上支持 cache write；
    /// DeepSeek route 下恒为 0，接 Anthropic / Bedrock route 时非 0。
    let hasCacheWriteDimension = true
    /// 历史日志（v0/v3）确实产出 `reasoningTokens`；当前构建不再产出，UI 侧按 `> 0` 门控。
    let hasReasoningDimension = true

    private static let logger = Logger(
        subsystem: "com.xiaoao.TokenWatch",
        category: "DeepSeekHarnessProvider"
    )

    private let scanner: DeepSeekHarnessScanner
    private let parser: DeepSeekHarnessSessionLogParser
    private let cacheCoordinator: JSONLLastGoodCacheCoordinator<
        DeepSeekHarnessSessionLogState,
        JSONLUnscopedCacheScope
    >
    private let diskStore: (any JSONLDiskCacheStoring<DeepSeekHarnessSessionLogState>)?
    private let priceCatalog: DeepSeekHarnessPriceCatalogStore

    init(
        scanner: DeepSeekHarnessScanner = DeepSeekHarnessScanner(),
        parser: DeepSeekHarnessSessionLogParser = DeepSeekHarnessSessionLogParser(),
        fileReader: any JSONLFileReading = SystemJSONLFileReader(),
        diskStore: (any JSONLDiskCacheStoring<DeepSeekHarnessSessionLogState>)? = SystemJSONLDiskCacheStore(
            namespace: "deepseek-harness",
            cacheVersion: DeepSeekHarnessProvider.currentDiskCacheVersion,
            compatibleCacheVersions: DeepSeekHarnessProvider.compatibleDiskCacheVersions
        ),
        priceCatalog: DeepSeekHarnessPriceCatalogStore = .shared
    ) {
        self.scanner = scanner
        self.parser = parser
        self.diskStore = diskStore
        self.priceCatalog = priceCatalog
        self.cacheCoordinator = JSONLLastGoodCacheCoordinator(fileReader: fileReader)
    }

    /// 扫描 DSH 数据根下所有会话日志并解析为统一条目。
    /// - Parameter dataRootURL: 已授权的 DSH 数据根（推荐 `~/.dsh`，亦支持 `~/.dsh/sessions`）。
    /// - Returns: 去重后的 ParsedUsageEntry 列表。
    func loadEntries(from dataRootURL: URL) throws -> [ParsedUsageEntry] {
        try loadEntriesWithCacheStatus(
            from: dataRootURL,
            materializeEntriesWhenUnchanged: true
        ).entries ?? []
    }

    /// 扫描会话日志并返回可与统计快照绑定的源版本。
    func loadEntriesWithCacheStatus(
        from dataRootURL: URL,
        materializeEntriesWhenUnchanged: Bool
    ) throws -> UsageProviderLoadResult {
        let roots = scanner.resolveDataRoots(dataRootURL)
        // 定价目录与日志同源：扫描时顺带刷新，保证聚合阶段能查到 route×model 价格。
        priceCatalog.refresh(dshHomeURL: roots.dshHome)

        let files = try scanner.locateSessionLogFiles(in: dataRootURL)
        let result: JSONLLastGoodCacheLoadResult<ParsedUsageEntry> =
            cacheCoordinator.loadListedFilesWithChangeStatus(
                files,
                scope: .shared,
                diskStore: diskStore,
                materializeCandidatesWhenUnchanged: materializeEntriesWhenUnchanged,
                cacheKey: { $0.url.path },
                urlForFile: { $0.url },
                build: { [parser] file, snapshot, previous in
                    try parser.buildState(file: file, snapshot: snapshot, previous: previous)
                },
                project: { [parser] state in
                    parser.project(state)
                },
                sourceRevisionComponent: { Self.sourceRevisionComponent(for: $0) },
                onFailure: { file, error, reusedLastGood in
                    if reusedLastGood {
                        Self.logger.warning(
                            "会话日志暂时不可读，复用上次成功结果: \(file.url.lastPathComponent, privacy: .public) — \(error.localizedDescription, privacy: .public)"
                        )
                    } else {
                        Self.logger.warning(
                            "会话日志首次读取失败，跳过: \(file.url.lastPathComponent, privacy: .public) — \(error.localizedDescription, privacy: .public)"
                        )
                    }
                }
            )
        return UsageProviderLoadResult(
            entries: result.candidates,
            didChange: result.didChange,
            sourceRevision: result.sourceRevision
        )
    }

    /// 校验数据根是否包含 `sessions/` 目录。
    func validateDataRoot(
        _ dataRootURL: URL
    ) -> ProviderDataRootValidationResult {
        scanner.validateDataRoot(dataRootURL)
    }

    /// 源版本分量：已消费字节偏移 + 记录条数，两者共同决定统计快照是否可复用。
    private static func sourceRevisionComponent(
        for state: DeepSeekHarnessSessionLogState
    ) -> Data {
        var component = Data()
        var offset = state.committedByteCount.bigEndian
        withUnsafeBytes(of: &offset) {
            component.append(contentsOf: $0)
        }
        var recordCount = UInt64(state.folder.recordCount).bigEndian
        withUnsafeBytes(of: &recordCount) {
            component.append(contentsOf: $0)
        }
        return component
    }
}
