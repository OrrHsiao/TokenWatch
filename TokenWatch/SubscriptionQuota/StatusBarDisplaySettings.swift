import Foundation

/// 状态栏常驻内容。
enum StatusBarDisplayMode: String, CaseIterable, Sendable {
    /// 原有仪表盘图标与今日 token 文本在前，额度圆环在后（默认）。
    case quotaAndTodayTokens
    /// 只显示 Claude / Codex 订阅剩余额度圆环。
    case subscriptionQuota
    /// 只显示原有今日 token 文本。
    case todayTokens

    static let defaultMode: StatusBarDisplayMode = .quotaAndTodayTokens

    var showsQuota: Bool {
        self != .todayTokens
    }

    var showsTodayTokens: Bool {
        self != .subscriptionQuota
    }

    func title(language: AppLanguage) -> String {
        switch self {
        case .quotaAndTodayTokens:
            return AppStrings.text(.statusBarDisplayQuotaAndTodayTokens, language: language)
        case .subscriptionQuota:
            return AppStrings.text(.statusBarDisplayQuota, language: language)
        case .todayTokens:
            return AppStrings.text(.statusBarDisplayTodayTokens, language: language)
        }
    }
}

/// 单个额度周期在状态栏中的展示样式。
enum StatusBarQuotaWindowStyle: String, CaseIterable, Sendable {
    /// 简洁：只显示圆环，不显示剩余百分比。
    case compact
    /// 详细：圆环右侧显示剩余百分比。
    case detailed

    static let defaultStyle: StatusBarQuotaWindowStyle = .detailed

    var showsValue: Bool {
        self == .detailed
    }

    func title(language: AppLanguage) -> String {
        switch self {
        case .compact:
            return AppStrings.text(.settingsQuotaStyleCompact, language: language)
        case .detailed:
            return AppStrings.text(.settingsQuotaStyleDetailed, language: language)
        }
    }
}

/// 某个 Agent 的某个额度周期在状态栏中的展示配置。
struct StatusBarQuotaWindowConfiguration: Equatable, Sendable {
    var isVisible: Bool
    var style: StatusBarQuotaWindowStyle

    static let defaultConfiguration = StatusBarQuotaWindowConfiguration(
        isVisible: true,
        style: .defaultStyle
    )
}

/// 持久化状态栏展示设置，并通知状态栏重绘。
@MainActor
final class StatusBarDisplaySettings {
    struct ObservationToken: Hashable {
        let id: UUID
    }

    static let shared = StatusBarDisplaySettings(defaults: .standard)
    static let modeStorageKey = "TokenWatch.statusBarDisplayMode"

    private let defaults: UserDefaults
    private var observers: [ObservationToken: @MainActor () -> Void] = [:]

    init(defaults: UserDefaults) {
        self.defaults = defaults
    }

    var mode: StatusBarDisplayMode {
        get {
            defaults.string(forKey: Self.modeStorageKey)
                .flatMap(StatusBarDisplayMode.init(rawValue:))
                ?? .defaultMode
        }
        set {
            guard mode != newValue else { return }
            defaults.set(newValue.rawValue, forKey: Self.modeStorageKey)
            notifyChange()
        }
    }

    /// 读取某个 Agent 某个周期的状态栏展示配置；未配置或存储值无效时为默认（显示 + 详细）。
    /// - Parameters:
    ///   - provider: Claude 或 Codex。
    ///   - kind: 5 小时或一周。
    /// - Returns: 该周期是否展示及展示样式。
    func quotaWindowConfiguration(
        provider: SubscriptionQuotaProvider,
        kind: SubscriptionQuotaWindowKind
    ) -> StatusBarQuotaWindowConfiguration {
        let visibilityKey = Self.quotaWindowVisibilityStorageKey(provider: provider, kind: kind)
        let isVisible = defaults.object(forKey: visibilityKey) == nil
            ? StatusBarQuotaWindowConfiguration.defaultConfiguration.isVisible
            : defaults.bool(forKey: visibilityKey)
        let style = defaults.string(forKey: Self.quotaWindowStyleStorageKey(provider: provider, kind: kind))
            .flatMap(StatusBarQuotaWindowStyle.init(rawValue:))
            ?? .defaultStyle
        return StatusBarQuotaWindowConfiguration(isVisible: isVisible, style: style)
    }

    /// 更新某个 Agent 某个周期的展示配置；值未变化时不通知重绘。
    /// - Parameters:
    ///   - configuration: 新配置。
    ///   - provider: Claude 或 Codex。
    ///   - kind: 5 小时或一周。
    func setQuotaWindowConfiguration(
        _ configuration: StatusBarQuotaWindowConfiguration,
        provider: SubscriptionQuotaProvider,
        kind: SubscriptionQuotaWindowKind
    ) {
        guard quotaWindowConfiguration(provider: provider, kind: kind) != configuration else { return }
        defaults.set(
            configuration.isVisible,
            forKey: Self.quotaWindowVisibilityStorageKey(provider: provider, kind: kind)
        )
        defaults.set(
            configuration.style.rawValue,
            forKey: Self.quotaWindowStyleStorageKey(provider: provider, kind: kind)
        )
        notifyChange()
    }

    /// 是否至少有一个周期需要在状态栏展示；全部关闭时状态栏退回只显示今日 Tokens。
    var hasVisibleQuotaWindow: Bool {
        SubscriptionQuotaProvider.allCases.contains { provider in
            SubscriptionQuotaWindowKind.allCases.contains { kind in
                quotaWindowConfiguration(provider: provider, kind: kind).isVisible
            }
        }
    }

    static func quotaWindowVisibilityStorageKey(
        provider: SubscriptionQuotaProvider,
        kind: SubscriptionQuotaWindowKind
    ) -> String {
        "TokenWatch.statusBarQuota.\(provider.rawValue).\(kind.rawValue).visible"
    }

    static func quotaWindowStyleStorageKey(
        provider: SubscriptionQuotaProvider,
        kind: SubscriptionQuotaWindowKind
    ) -> String {
        "TokenWatch.statusBarQuota.\(provider.rawValue).\(kind.rawValue).style"
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

    private func notifyChange() {
        for handler in Array(observers.values) {
            handler()
        }
    }
}
