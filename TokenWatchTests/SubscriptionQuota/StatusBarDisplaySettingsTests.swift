import Foundation
import Testing
@testable import TokenWatch

@MainActor
@Suite("StatusBarDisplaySettings")
struct StatusBarDisplaySettingsTests {

    @Test("默认同时显示订阅额度与今日 Tokens，额度为两个周期，并持久化用户选择")
    func defaultsAndPersistence() throws {
        let suiteName = "StatusBarDisplaySettingsTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let settings = StatusBarDisplaySettings(defaults: defaults)
        #expect(settings.mode == .quotaAndTodayTokens)
        #expect(settings.mode.showsQuota && settings.mode.showsTodayTokens)
        #expect(!StatusBarDisplayMode.subscriptionQuota.showsTodayTokens)
        #expect(!StatusBarDisplayMode.todayTokens.showsQuota)
        #expect(settings.quotaWindows == .both)
        #expect(settings.quotaWindows.windowKinds == [.fiveHour, .sevenDay])

        settings.mode = .todayTokens
        settings.quotaWindows = .sevenDay

        let reloaded = StatusBarDisplaySettings(defaults: defaults)
        #expect(reloaded.mode == .todayTokens)
        #expect(reloaded.quotaWindows == .sevenDay)
        #expect(reloaded.quotaWindows.windowKinds == [.sevenDay])
    }

    @Test("只有值变化时才通知状态栏重绘；无效存储值回退默认")
    func notifiesOnlyOnChange() throws {
        let suiteName = "StatusBarDisplaySettingsTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        defaults.set("unknown", forKey: StatusBarDisplaySettings.modeStorageKey)

        let settings = StatusBarDisplaySettings(defaults: defaults)
        #expect(settings.mode == .quotaAndTodayTokens)
        var notifications = 0
        settings.observe { notifications += 1 }

        settings.quotaWindows = .both
        settings.quotaWindows = .fiveHour
        settings.quotaWindows = .fiveHour

        #expect(notifications == 1)
    }
}
