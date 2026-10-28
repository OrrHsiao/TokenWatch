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

/// 额度模式下状态栏展示的窗口；次序固定为 5H、7D，不自动轮播或切换到更紧张的窗口。
enum StatusBarQuotaWindowsOption: String, CaseIterable, Sendable {
    case both
    case fiveHour
    case sevenDay

    static let defaultOption: StatusBarQuotaWindowsOption = .both

    var windowKinds: [SubscriptionQuotaWindowKind] {
        switch self {
        case .both:
            return [.fiveHour, .sevenDay]
        case .fiveHour:
            return [.fiveHour]
        case .sevenDay:
            return [.sevenDay]
        }
    }

    func title(language: AppLanguage) -> String {
        switch self {
        case .both:
            return AppStrings.text(.quotaWindowsBoth, language: language)
        case .fiveHour:
            return AppStrings.text(.quotaWindowFiveHour, language: language)
        case .sevenDay:
            return AppStrings.text(.quotaWindowWeek, language: language)
        }
    }
}

/// 持久化状态栏展示设置，并通知状态栏重绘。
@MainActor
final class StatusBarDisplaySettings {
    struct ObservationToken: Hashable {
        let id: UUID
    }

    static let shared = StatusBarDisplaySettings(defaults: .standard)
    static let modeStorageKey = "TokenWatch.statusBarDisplayMode"
    static let quotaWindowsStorageKey = "TokenWatch.statusBarQuotaWindows"

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

    var quotaWindows: StatusBarQuotaWindowsOption {
        get {
            defaults.string(forKey: Self.quotaWindowsStorageKey)
                .flatMap(StatusBarQuotaWindowsOption.init(rawValue:))
                ?? .defaultOption
        }
        set {
            guard quotaWindows != newValue else { return }
            defaults.set(newValue.rawValue, forKey: Self.quotaWindowsStorageKey)
            notifyChange()
        }
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
