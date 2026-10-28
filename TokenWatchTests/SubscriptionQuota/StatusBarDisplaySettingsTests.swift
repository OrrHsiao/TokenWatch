import Foundation
import Testing
@testable import TokenWatch

@MainActor
@Suite("StatusBarDisplaySettings")
struct StatusBarDisplaySettingsTests {

    @Test("默认同时显示订阅额度与今日 Tokens，各周期默认显示且为详细模式，并持久化用户选择")
    func defaultsAndPersistence() throws {
        let suiteName = "StatusBarDisplaySettingsTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let settings = StatusBarDisplaySettings(defaults: defaults)
        #expect(settings.mode == .quotaAndTodayTokens)
        #expect(settings.mode.showsQuota && settings.mode.showsTodayTokens)
        #expect(!StatusBarDisplayMode.subscriptionQuota.showsTodayTokens)
        #expect(!StatusBarDisplayMode.todayTokens.showsQuota)
        for provider in SubscriptionQuotaProvider.allCases {
            for kind in SubscriptionQuotaWindowKind.allCases {
                #expect(settings.quotaWindowConfiguration(provider: provider, kind: kind) == .init(
                    isVisible: true,
                    style: .detailed
                ))
            }
        }
        #expect(settings.hasVisibleQuotaWindow)

        settings.mode = .todayTokens
        settings.setQuotaWindowConfiguration(
            .init(isVisible: false, style: .detailed),
            provider: .claude,
            kind: .fiveHour
        )
        settings.setQuotaWindowConfiguration(
            .init(isVisible: true, style: .compact),
            provider: .codex,
            kind: .sevenDay
        )

        let reloaded = StatusBarDisplaySettings(defaults: defaults)
        #expect(reloaded.mode == .todayTokens)
        // Claude 与 Codex 的周期配置互不影响。
        #expect(reloaded.quotaWindowConfiguration(provider: .claude, kind: .fiveHour) == .init(
            isVisible: false,
            style: .detailed
        ))
        #expect(reloaded.quotaWindowConfiguration(provider: .codex, kind: .fiveHour) == .init(
            isVisible: true,
            style: .detailed
        ))
        #expect(reloaded.quotaWindowConfiguration(provider: .codex, kind: .sevenDay) == .init(
            isVisible: true,
            style: .compact
        ))
        #expect(!StatusBarQuotaWindowStyle.compact.showsValue)
        #expect(StatusBarQuotaWindowStyle.detailed.showsValue)
    }

    @Test("只有值变化时才通知状态栏重绘；无效存储值回退默认")
    func notifiesOnlyOnChange() throws {
        let suiteName = "StatusBarDisplaySettingsTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        defaults.set("unknown", forKey: StatusBarDisplaySettings.modeStorageKey)
        defaults.set(
            "unknown",
            forKey: StatusBarDisplaySettings.quotaWindowStyleStorageKey(provider: .claude, kind: .sevenDay)
        )

        let settings = StatusBarDisplaySettings(defaults: defaults)
        #expect(settings.mode == .quotaAndTodayTokens)
        #expect(settings.quotaWindowConfiguration(provider: .claude, kind: .sevenDay).style == .detailed)
        var notifications = 0
        settings.observe { notifications += 1 }

        settings.setQuotaWindowConfiguration(.defaultConfiguration, provider: .claude, kind: .fiveHour)
        settings.setQuotaWindowConfiguration(
            .init(isVisible: true, style: .compact),
            provider: .claude,
            kind: .fiveHour
        )
        settings.setQuotaWindowConfiguration(
            .init(isVisible: true, style: .compact),
            provider: .claude,
            kind: .fiveHour
        )

        #expect(notifications == 1)
    }

    @Test("两个 Agent 的所有周期都关闭时没有可展示的额度")
    func allWindowsHiddenHasNoVisibleQuota() throws {
        let suiteName = "StatusBarDisplaySettingsTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let settings = StatusBarDisplaySettings(defaults: defaults)

        for provider in SubscriptionQuotaProvider.allCases {
            for kind in SubscriptionQuotaWindowKind.allCases {
                settings.setQuotaWindowConfiguration(
                    .init(isVisible: false, style: .detailed),
                    provider: provider,
                    kind: kind
                )
            }
        }
        #expect(!settings.hasVisibleQuotaWindow)

        settings.setQuotaWindowConfiguration(
            .init(isVisible: true, style: .compact),
            provider: .codex,
            kind: .sevenDay
        )
        #expect(settings.hasVisibleQuotaWindow)
    }
}
