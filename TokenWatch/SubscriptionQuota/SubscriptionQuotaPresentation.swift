import Foundation

/// 剩余额度的强调级别；旧记录不强调颜色。
enum SubscriptionQuotaSeverity: Equatable, Sendable {
    case normal
    /// 剩余 ≤20%。
    case warning
    /// 剩余 ≤10%。
    case danger
}

/// 单个额度窗口的展示模型；状态栏与弹窗共用同一套判定。
struct SubscriptionQuotaWindowPresentation: Equatable, Sendable {
    let kind: SubscriptionQuotaWindowKind
    /// 弹窗窗口名，例如“5 小时”。
    let title: String
    /// 状态栏圆环内的周期，固定为 5H / 7D。
    let shortLabel: String
    /// 剩余百分比；nil 表示该窗口显示“—”。
    let remainingPercent: Double?
    let valueText: String
    /// 弹窗横条下方的说明：重置倒计时、重置时间未知、已重置（推断）等。
    let detailText: String
    let severity: SubscriptionQuotaSeverity
    /// 记录较旧或按重置点推断时为 true，横条弱化显示。
    let isStale: Bool
    /// 剩余额度不是来源报告值，而是跨过重置点后推断的 100%。
    let isResetInferred: Bool
    let accessibilityText: String
}

/// 单个工具分组的展示模型。
struct SubscriptionQuotaProviderPresentation: Equatable, Sendable {
    enum Action: Equatable, Sendable {
        case chooseClaudeFile
        case authorizeCodexDirectory
    }

    let provider: SubscriptionQuotaProvider
    /// 分组标题右侧的独立记录时间与读取状态。
    let statusText: String
    /// 记录较旧或读取失败时，用强调色提醒该工具的数据可能不是最新。
    let isStatusHighlighted: Bool
    let isStale: Bool
    /// 固定按 5 小时、一周排列。
    let windows: [SubscriptionQuotaWindowPresentation]
    /// 非 nil 时以一行提示替代两个窗口（未授权、首次读取失败）。
    let message: String?
    let action: Action?
    let actionTitle: String?
}

/// 将额度状态转换为界面文案和强调级别。
///
/// 规则集中在纯函数中，便于覆盖 0%、100%、不足 1%、旧记录、跨重置点和未授权等边界。
enum SubscriptionQuotaPresenter {
    /// 旧快照阈值是产品策略，不代表 Claude 或 Codex 服务端的有效期。
    static let staleInterval: TimeInterval = 60 * 60
    static let warningThreshold: Double = 20
    static let dangerThreshold: Double = 10
    /// 跨过重置点且没有新快照时推断的剩余百分比。
    static let resetInferredRemainingPercent: Double = 100

    /// 生成单个工具的展示模型。
    /// - Parameters:
    ///   - provider: 工具。
    ///   - state: store 中该工具的状态。
    ///   - now: 当前时间，用于计龄、倒计时与重置点判断。
    ///   - language: 界面语言。
    static func make(
        provider: SubscriptionQuotaProvider,
        state: SubscriptionQuotaProviderState,
        now: Date,
        language: AppLanguage
    ) -> SubscriptionQuotaProviderPresentation {
        let readFailedText = AppStrings.text(.quotaReadFailed, language: language)

        switch state.result {
        case .none:
            return SubscriptionQuotaProviderPresentation(
                provider: provider,
                statusText: "",
                isStatusHighlighted: false,
                isStale: false,
                windows: unavailableWindows(provider: provider, detail: "", language: language),
                message: state.lastReadFailed ? readFailedText : nil,
                action: nil,
                actionTitle: nil
            )

        case .notAuthorized:
            let action: SubscriptionQuotaProviderPresentation.Action
            let actionKey: AppStringKey
            switch provider {
            case .claude:
                action = .chooseClaudeFile
                actionKey = .quotaChooseFile
            case .codex:
                action = .authorizeCodexDirectory
                actionKey = .settingsChooseDirectory
            }
            return SubscriptionQuotaProviderPresentation(
                provider: provider,
                statusText: "",
                isStatusHighlighted: false,
                isStale: false,
                windows: unavailableWindows(provider: provider, detail: "", language: language),
                message: AppStrings.text(.quotaNotRead, language: language),
                action: action,
                actionTitle: AppStrings.text(actionKey, language: language)
            )

        case .noRecord:
            return SubscriptionQuotaProviderPresentation(
                provider: provider,
                statusText: state.lastReadFailed ? readFailedText : "",
                isStatusHighlighted: state.lastReadFailed,
                isStale: false,
                windows: unavailableWindows(
                    provider: provider,
                    detail: AppStrings.text(.quotaNoRecord, language: language),
                    language: language
                ),
                message: nil,
                action: nil,
                actionTitle: nil
            )

        case .snapshot(let snapshot):
            let isStale = now.timeIntervalSince(snapshot.recordedAt) > staleInterval
            var statusParts = [recordedText(recordedAt: snapshot.recordedAt, now: now, language: language)]
            if isStale {
                statusParts.append(AppStrings.text(.quotaStaleRecord, language: language))
            }
            if state.lastReadFailed {
                statusParts.append(readFailedText)
            }
            let windows = SubscriptionQuotaWindowKind.allCases.map { kind in
                window(
                    kind: kind,
                    value: snapshot.windows[kind],
                    provider: provider,
                    isStale: isStale,
                    now: now,
                    language: language
                )
            }
            return SubscriptionQuotaProviderPresentation(
                provider: provider,
                statusText: statusParts.joined(separator: " · "),
                isStatusHighlighted: isStale || state.lastReadFailed,
                isStale: isStale,
                windows: windows,
                message: nil,
                action: nil,
                actionTitle: nil
            )
        }
    }

    /// 剩余百分比文本：0% 只表示来源明确报告用尽；正剩余不足 1% 显示 `<1%`，
    /// 其余向下取整，避免 99.6% 被写成 100%。
    static func percentText(remainingPercent: Double) -> String {
        if remainingPercent <= 0 {
            return "0%"
        }
        if remainingPercent < 1 {
            return "<1%"
        }
        return "\(Int(remainingPercent.rounded(.down)))%"
    }

    static func severity(remainingPercent: Double) -> SubscriptionQuotaSeverity {
        if remainingPercent <= dangerThreshold {
            return .danger
        }
        if remainingPercent <= warningThreshold {
            return .warning
        }
        return .normal
    }

    static func windowTitle(_ kind: SubscriptionQuotaWindowKind, language: AppLanguage) -> String {
        switch kind {
        case .fiveHour:
            return AppStrings.text(.quotaWindowFiveHour, language: language)
        case .sevenDay:
            return AppStrings.text(.quotaWindowWeek, language: language)
        }
    }

    static func shortLabel(_ kind: SubscriptionQuotaWindowKind) -> String {
        switch kind {
        case .fiveHour:
            return "5H"
        case .sevenDay:
            return "7D"
        }
    }

    /// “记录于 X”：使用来源记录时间计龄。
    static func recordedText(recordedAt: Date, now: Date, language: AppLanguage) -> String {
        let elapsed = max(0, now.timeIntervalSince(recordedAt))
        let age: String
        if elapsed < 60 {
            age = AppStrings.text(.dashboardJustNow, language: language)
        } else if elapsed < 3_600 {
            age = String(
                format: AppStrings.text(.dashboardMinutesAgoFormat, language: language),
                Int(elapsed / 60)
            )
        } else if elapsed < 86_400 {
            age = String(
                format: AppStrings.text(.dashboardHoursAgoFormat, language: language),
                Int(elapsed / 3_600)
            )
        } else {
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: language.localeIdentifier)
            formatter.dateStyle = .short
            formatter.timeStyle = .short
            age = formatter.string(from: recordedAt)
        }
        return String(format: AppStrings.text(.quotaRecordedFormat, language: language), age)
    }

    /// 重置倒计时，最多两个单位，例如“2小时14分钟后重置”。
    static func resetCountdownText(resetsAt: Date, now: Date, language: AppLanguage) -> String {
        let formatter = DateComponentsFormatter()
        formatter.allowedUnits = [.day, .hour, .minute]
        formatter.unitsStyle = .abbreviated
        formatter.maximumUnitCount = 2
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = Locale(identifier: language.localeIdentifier)
        formatter.calendar = calendar
        // 不足一分钟时显示 1 分钟，避免出现“0 分钟后重置”。
        let interval = max(60, resetsAt.timeIntervalSince(now))
        let duration = formatter.string(from: interval) ?? ""
        return String(format: AppStrings.text(.quotaResetsInFormat, language: language), duration)
    }

    /// 状态栏悬停说明：按工具分组列出窗口、剩余额度、重置时间、记录时间及旧记录状态；
    /// 含推断窗口时在末尾说明推断的局限，只说明一次。
    static func toolTip(
        for presentations: [SubscriptionQuotaProviderPresentation],
        language: AppLanguage
    ) -> String {
        var sections = presentations.map { presentation in
            let name = presentation.provider.displayName
            if let message = presentation.message {
                return "\(name) · \(message)"
            }
            var lines = [presentation.statusText.isEmpty ? name : "\(name) · \(presentation.statusText)"]
            for window in presentation.windows {
                var parts = [window.title]
                if let remaining = window.remainingPercent {
                    parts.append(remainingText(remainingPercent: remaining, language: language))
                } else {
                    parts.append("—")
                }
                if !window.detailText.isEmpty {
                    parts.append(window.detailText)
                }
                lines.append(parts.joined(separator: " · "))
            }
            return lines.joined(separator: "\n")
        }
        if presentations.contains(where: { $0.windows.contains(where: \.isResetInferred) }) {
            sections.append(resetInferredNote(language: language))
        }
        return sections.joined(separator: "\n\n")
    }

    /// 推断规则与局限的说明，悬停说明与订阅区说明气泡共用。
    static func resetInferredNote(language: AppLanguage) -> String {
        String(
            format: AppStrings.text(.quotaResetInferredNoteFormat, language: language),
            percentText(remainingPercent: resetInferredRemainingPercent)
        )
    }

    static func remainingText(remainingPercent: Double, language: AppLanguage) -> String {
        String(
            format: AppStrings.text(.quotaRemainingFormat, language: language),
            percentText(remainingPercent: remainingPercent)
        )
    }

    // MARK: - Private

    private static func window(
        kind: SubscriptionQuotaWindowKind,
        value: SubscriptionQuotaWindow?,
        provider: SubscriptionQuotaProvider,
        isStale: Bool,
        now: Date,
        language: AppLanguage
    ) -> SubscriptionQuotaWindowPresentation {
        guard let value else {
            return unavailableWindow(
                kind: kind,
                provider: provider,
                detail: AppStrings.text(.quotaNoRecord, language: language),
                language: language
            )
        }
        let title = windowTitle(kind, language: language)

        // 来源只在本机使用工具时写新快照：跨过重置点后若本机用过，最新快照会换成新窗口的值，
        // 仍停留在旧快照即说明重置后本机未使用，因此推断剩余 100%。
        // 其他设备或网页的消耗本机看不到，文案标注“推断”并弱化横条，不使用警告色。
        if let resetsAt = value.resetsAt, now >= resetsAt {
            let detail = AppStrings.text(.quotaResetInferred, language: language)
            let remaining = resetInferredRemainingPercent
            return SubscriptionQuotaWindowPresentation(
                kind: kind,
                title: title,
                shortLabel: shortLabel(kind),
                remainingPercent: remaining,
                valueText: percentText(remainingPercent: remaining),
                detailText: detail,
                severity: .normal,
                isStale: true,
                isResetInferred: true,
                accessibilityText: [
                    "\(provider.displayName) \(title)",
                    remainingText(remainingPercent: remaining, language: language),
                    detail,
                ].joined(separator: " · ")
            )
        }

        let remaining = value.remainingPercent
        var detailParts: [String] = []
        if remaining <= 0 {
            detailParts.append(AppStrings.text(.quotaExhausted, language: language))
        }
        if let resetsAt = value.resetsAt {
            detailParts.append(resetCountdownText(resetsAt: resetsAt, now: now, language: language))
        } else {
            detailParts.append(AppStrings.text(.quotaResetUnknown, language: language))
        }

        var accessibilityParts = [
            "\(provider.displayName) \(title)",
            remainingText(remainingPercent: remaining, language: language),
        ]
        if isStale {
            accessibilityParts.append(AppStrings.text(.quotaStaleRecord, language: language))
        }
        return SubscriptionQuotaWindowPresentation(
            kind: kind,
            title: title,
            shortLabel: shortLabel(kind),
            remainingPercent: remaining,
            valueText: percentText(remainingPercent: remaining),
            detailText: detailParts.joined(separator: " · "),
            severity: isStale ? .normal : severity(remainingPercent: remaining),
            isStale: isStale,
            isResetInferred: false,
            accessibilityText: accessibilityParts.joined(separator: " · ")
        )
    }

    private static func unavailableWindows(
        provider: SubscriptionQuotaProvider,
        detail: String,
        language: AppLanguage
    ) -> [SubscriptionQuotaWindowPresentation] {
        SubscriptionQuotaWindowKind.allCases.map {
            unavailableWindow(kind: $0, provider: provider, detail: detail, language: language)
        }
    }

    private static func unavailableWindow(
        kind: SubscriptionQuotaWindowKind,
        provider: SubscriptionQuotaProvider,
        detail: String,
        language: AppLanguage
    ) -> SubscriptionQuotaWindowPresentation {
        let title = windowTitle(kind, language: language)
        let accessibility = detail.isEmpty
            ? "\(provider.displayName) \(title) —"
            : "\(provider.displayName) \(title) · \(detail)"
        return SubscriptionQuotaWindowPresentation(
            kind: kind,
            title: title,
            shortLabel: shortLabel(kind),
            remainingPercent: nil,
            valueText: "—",
            detailText: detail,
            severity: .normal,
            isStale: false,
            isResetInferred: false,
            accessibilityText: accessibility
        )
    }
}
