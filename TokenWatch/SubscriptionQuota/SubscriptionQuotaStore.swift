import AppKit
import Foundation
import UniformTypeIdentifiers
import os.log

/// 额度 store 需要的 bookmark 能力；与 provider 目录共用同一套 security-scoped 管理。
@MainActor
protocol SubscriptionQuotaBookmarkAccessing: Sendable {
    func hasBookmark(forKey key: String) -> Bool
    func restoreBookmarkAndAccess(forKey key: String) -> URL?
    func stopAccessing(forKey key: String)
    /// 为用户选中的 URL 创建并保存 bookmark；bookmark 创建与目录无关，文件同样适用。
    func persistSelectedDirectory(_ url: URL, forKey key: String) -> Bool
}

extension SecurityScopedBookmarkManager: SubscriptionQuotaBookmarkAccessing {}

/// 让用户选择 Claude Code 配置文件的面板。
@MainActor
protocol ClaudeQuotaFilePanelPresenting: Sendable {
    /// - Returns: 用户确认的文件；取消时返回 nil。
    func chooseClaudeConfigFile(language: AppLanguage) async -> URL?
}

/// App Sandbox 下现有 `.claude/` 目录授权不包含同级 `.claude.json`，
/// 因此单独请求该文件的只读授权，不扩大为 Home 授权。
@MainActor
struct OpenPanelClaudeQuotaFilePresenter: ClaudeQuotaFilePanelPresenting {
    func chooseClaudeConfigFile(language: AppLanguage) async -> URL? {
        await withCheckedContinuation { continuation in
            let panel = Self.makeOpenPanel(language: language)
            NSApp.activate(ignoringOtherApps: true)
            panel.begin { response in
                continuation.resume(returning: response == .OK ? panel.url : nil)
            }
        }
    }

    /// 创建只允许单选 JSON 文件的面板；与目录面板一致，不预设初始目录。
    static func makeOpenPanel(language: AppLanguage) -> NSOpenPanel {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.showsHiddenFiles = true
        panel.allowedContentTypes = [.json]
        panel.message = AppStrings.text(.claudeQuotaFileOpenPanelMessage, language: language)
        panel.prompt = AppStrings.text(.chooseDirectoryPrompt, language: language)
        return panel
    }
}

/// Claude / Codex 本地订阅额度状态。
///
/// 只读取本地快照：Claude 为用户授权的 `.claude.json`，Codex 复用已授权的数据目录。
/// 不联网，不读取凭据。两个工具的状态独立更新，读取失败时保留最后有效快照。
@MainActor
final class SubscriptionQuotaStore {
    struct ObservationToken: Hashable {
        let id: UUID
    }

    static let claudeQuotaFileBookmarkKey = "ClaudeQuotaFileBookmark"

    private(set) var states: [SubscriptionQuotaProvider: SubscriptionQuotaProviderState] = [
        .claude: .initial,
        .codex: .initial,
    ]
    private(set) var isAuthorizingClaudeFile = false

    private let bookmarkManager: any SubscriptionQuotaBookmarkAccessing
    private let claudeReader: ClaudeQuotaFileReader
    private let codexReader: CodexQuotaReader
    private let filePanelPresenter: any ClaudeQuotaFilePanelPresenting
    private let languageProvider: @MainActor () -> AppLanguage
    private let isDemoModeEnabled: @MainActor () -> Bool
    private let nowProvider: @MainActor () -> Date
    private let logger = Logger(subsystem: "com.xiaoao.TokenWatch", category: "SubscriptionQuotaStore")
    private var observers: [ObservationToken: @MainActor () -> Void] = [:]
    private var isRefreshing = false
    private var needsAnotherRefresh = false

    init(
        bookmarkManager: any SubscriptionQuotaBookmarkAccessing = SecurityScopedBookmarkManager.shared,
        claudeReader: ClaudeQuotaFileReader = ClaudeQuotaFileReader(),
        codexReader: CodexQuotaReader = CodexQuotaReader(),
        filePanelPresenter: any ClaudeQuotaFilePanelPresenting = OpenPanelClaudeQuotaFilePresenter(),
        languageProvider: @escaping @MainActor () -> AppLanguage = {
            AppLanguageSettings.shared.resolvedLanguage
        },
        isDemoModeEnabled: @escaping @MainActor () -> Bool = { DemoStatsFixture.isDemoModeEnabled },
        nowProvider: @escaping @MainActor () -> Date = Date.init
    ) {
        self.bookmarkManager = bookmarkManager
        self.claudeReader = claudeReader
        self.codexReader = codexReader
        self.filePanelPresenter = filePanelPresenter
        self.languageProvider = languageProvider
        self.isDemoModeEnabled = isDemoModeEnabled
        self.nowProvider = nowProvider
    }

    func state(for provider: SubscriptionQuotaProvider) -> SubscriptionQuotaProviderState {
        states[provider] ?? .initial
    }

    /// 是否已保存 Claude 额度文件 bookmark；只查询存在性、不恢复访问，供设置页展示授权状态。
    var hasClaudeFileBookmark: Bool {
        bookmarkManager.hasBookmark(forKey: Self.claudeQuotaFileBookmarkKey)
    }

    @discardableResult
    func observe(_ handler: @escaping @MainActor () -> Void) -> ObservationToken {
        let token = ObservationToken(id: UUID())
        observers[token] = handler
        return token
    }

    func removeObserver(_ token: ObservationToken) {
        observers.removeValue(forKey: token)
    }

    /// 重新读取两个工具的本地额度记录。
    ///
    /// 只检查本地记录：记录时间始终来自来源快照，刷新不会把读取时刻当作快照时刻。
    /// 刷新进行中再次请求时合并为一次追加刷新，状态无变化时不通知 observer。
    func refresh() async {
        guard !isRefreshing else {
            needsAnotherRefresh = true
            return
        }
        isRefreshing = true
        defer { isRefreshing = false }

        repeat {
            needsAnotherRefresh = false
            await performRefresh()
        } while needsAnotherRefresh
    }

    /// 让用户选择 `.claude.json` 并保存只读 bookmark，成功后立即刷新。
    /// - Returns: bookmark 保存成功时返回 true；取消或保存失败返回 false。
    @discardableResult
    func requestClaudeFileAuthorization() async -> Bool {
        guard !isAuthorizingClaudeFile else { return false }
        isAuthorizingClaudeFile = true
        defer { isAuthorizingClaudeFile = false }

        guard let url = await filePanelPresenter.chooseClaudeConfigFile(language: languageProvider()) else {
            logger.info("用户取消选择 Claude 额度文件")
            return false
        }
        // 每轮刷新都成对恢复 / 释放访问；进行中的刷新结束后，追加刷新会改用新 bookmark。
        guard bookmarkManager.persistSelectedDirectory(url, forKey: Self.claudeQuotaFileBookmarkKey) else {
            logger.error("Claude 额度文件 bookmark 保存失败")
            return false
        }
        logger.info("Claude 额度文件授权成功")
        await refresh()
        return true
    }

    // MARK: - Private

    private func performRefresh() async {
        if isDemoModeEnabled() {
            apply(Self.demoResults(now: nowProvider()))
            return
        }

        let claudeURL = restoreAccess(forKey: Self.claudeQuotaFileBookmarkKey, name: "Claude 额度文件")
        let codexURL = restoreAccess(forKey: CodexProvider.dataDirectoryBookmarkKey, name: "Codex 数据目录")
        defer {
            if claudeURL != nil {
                bookmarkManager.stopAccessing(forKey: Self.claudeQuotaFileBookmarkKey)
            }
            if codexURL != nil {
                bookmarkManager.stopAccessing(forKey: CodexProvider.dataDirectoryBookmarkKey)
            }
        }

        let claudeReader = self.claudeReader
        let codexReader = self.codexReader
        async let claudeResult = Task.detached(priority: .utility) { () -> Result<SubscriptionQuotaReadResult, Error> in
            guard let claudeURL else { return .success(.notAuthorized) }
            return Result { try claudeReader.read(fileURL: claudeURL) }
        }.value
        async let codexResult = Task.detached(priority: .utility) { () -> Result<SubscriptionQuotaReadResult, Error> in
            guard let codexURL else { return .success(.notAuthorized) }
            return Result { try codexReader.read(codexRoot: codexURL) }
        }.value

        apply([.claude: await claudeResult, .codex: await codexResult])
    }

    private func restoreAccess(forKey key: String, name: String) -> URL? {
        guard bookmarkManager.hasBookmark(forKey: key) else { return nil }
        guard let url = bookmarkManager.restoreBookmarkAndAccess(forKey: key) else {
            logger.error("\(name, privacy: .public) bookmark 恢复失败，需要重新授权")
            return nil
        }
        return url
    }

    /// 合并读取结果：成功即替换（账号切换后不沿用旧账号的值），失败只标记并保留最后有效值。
    private func apply(_ results: [SubscriptionQuotaProvider: Result<SubscriptionQuotaReadResult, Error>]) {
        var didChange = false
        for (provider, result) in results {
            let previous = state(for: provider)
            let next: SubscriptionQuotaProviderState
            switch result {
            case .success(let readResult):
                next = SubscriptionQuotaProviderState(result: readResult, lastReadFailed: false)
            case .failure(let error):
                logger.warning(
                    "\(provider.displayName, privacy: .public) 额度读取失败，保留最后有效记录: \(error.localizedDescription)"
                )
                next = SubscriptionQuotaProviderState(result: previous.result, lastReadFailed: true)
            }
            guard next != previous else { continue }
            states[provider] = next
            didChange = true
        }
        guard didChange else { return }
        for handler in Array(observers.values) {
            handler()
        }
    }

    /// 截图与 UI 测试使用的确定性额度。
    static func demoResults(now: Date) -> [SubscriptionQuotaProvider: Result<SubscriptionQuotaReadResult, Error>] {
        func snapshot(
            _ provider: SubscriptionQuotaProvider,
            recordedSecondsAgo: TimeInterval,
            fiveHour: (used: Double, resetsIn: TimeInterval),
            sevenDay: (used: Double, resetsIn: TimeInterval)
        ) -> Result<SubscriptionQuotaReadResult, Error> {
            var windows: [SubscriptionQuotaWindowKind: SubscriptionQuotaWindow] = [:]
            windows[.fiveHour] = SubscriptionQuotaWindow(
                usedPercent: fiveHour.used,
                resetsAt: now.addingTimeInterval(fiveHour.resetsIn)
            )
            windows[.sevenDay] = SubscriptionQuotaWindow(
                usedPercent: sevenDay.used,
                resetsAt: now.addingTimeInterval(sevenDay.resetsIn)
            )
            return .success(.snapshot(SubscriptionQuotaSnapshot(
                provider: provider,
                accountID: nil,
                bucketID: provider == .codex ? CodexQuotaReader.defaultBucketID : nil,
                recordedAt: now.addingTimeInterval(-recordedSecondsAgo),
                windows: windows
            )))
        }

        return [
            .claude: snapshot(
                .claude,
                recordedSecondsAgo: 2 * 60,
                fiveHour: (32, 2 * 3_600 + 14 * 60 + 30),
                sevenDay: (14, 3 * 86_400 + 5 * 3_600 + 30)
            ),
            .codex: snapshot(
                .codex,
                recordedSecondsAgo: 10,
                fiveHour: (12, 4 * 3_600 + 49 * 60 + 30),
                sevenDay: (2, 6 * 86_400 + 23 * 3_600 + 30)
            ),
        ]
    }
}
