import Foundation
import Testing
@testable import TokenWatch

@MainActor
@Suite("AppLanguageSettings")
struct AppLanguageSettingsTests {
    @Test("缺失值回落到跟随系统")
    func missingPreferenceFallsBackToSystem() throws {
        try withTemporaryDefaults { defaults in
            let settings = AppLanguageSettings(defaults: defaults, preferredLanguagesProvider: { ["zh-Hans-US"] })

            #expect(settings.selectedPreference == .system)
            #expect(settings.resolvedLanguage == .zhHans)
        }
    }

    @Test("非法值回落到跟随系统")
    func invalidPreferenceFallsBackToSystem() throws {
        try withTemporaryDefaults { defaults in
            defaults.set("fr", forKey: AppLanguageSettings.storageKey)
            let settings = AppLanguageSettings(defaults: defaults, preferredLanguagesProvider: { ["en-US"] })

            #expect(settings.selectedPreference == .system)
            #expect(settings.resolvedLanguage == .en)
        }
    }

    @Test("中文系统语言解析为中文")
    func systemChineseResolvesToChinese() throws {
        try withTemporaryDefaults { defaults in
            let settings = AppLanguageSettings(defaults: defaults, preferredLanguagesProvider: { ["zh-Hant-TW"] })

            #expect(settings.resolvedLanguage == .zhHans)
        }
    }

    @Test("英文系统语言解析为英文")
    func systemEnglishResolvesToEnglish() throws {
        try withTemporaryDefaults { defaults in
            let settings = AppLanguageSettings(defaults: defaults, preferredLanguagesProvider: { ["en-US"] })

            #expect(settings.resolvedLanguage == .en)
        }
    }

    @Test("其他系统语言回落到英文")
    func unsupportedSystemLanguageFallsBackToEnglish() throws {
        try withTemporaryDefaults { defaults in
            let settings = AppLanguageSettings(defaults: defaults, preferredLanguagesProvider: { ["ja-JP"] })

            #expect(settings.resolvedLanguage == .en)
        }
    }

    @Test("选择英文会持久化并通知观察者")
    func selectingEnglishPersistsAndNotifies() throws {
        try withTemporaryDefaults { defaults in
            let settings = AppLanguageSettings(defaults: defaults, preferredLanguagesProvider: { ["zh-Hans-US"] })
            var notificationCount = 0
            let token = settings.observe { notificationCount += 1 }

            settings.selectedPreference = .en

            #expect(defaults.string(forKey: AppLanguageSettings.storageKey) == "en")
            #expect(settings.resolvedLanguage == .en)
            #expect(notificationCount == 1)

            settings.removeObserver(token)
            settings.selectedPreference = .zhHans
            #expect(notificationCount == 1)
        }
    }

    @Test("基础文案按语言返回")
    func stringsReturnLocalizedText() {
        #expect(AppStrings.text(.settingsTitle, language: .zhHans) == "设置")
        #expect(AppStrings.text(.settingsTitle, language: .en) == "Settings")
        #expect(AppLanguagePreference.system.title(language: .zhHans) == "跟随系统")
        #expect(AppLanguagePreference.system.title(language: .en) == "System")
    }

    @Test("英文文案表覆盖所有 key")
    func englishStringTableCoversAllKeys() {
        for key in AppStringKey.allCases {
            #expect(
                AppStrings.text(key, language: .en) != String(describing: key),
                "Missing English string for \(key)"
            )
        }
    }

    @Test("所有文案 key 均解析为非空字符串")
    func allStringKeysResolveToNonEmptyText() {
        for key in AppStringKey.allCases {
            for language in [AppLanguage.zhHans, .en] {
                #expect(
                    !AppStrings.text(key, language: language).trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                    "Empty string for \(key) in \(language)"
                )
            }
        }
    }

    @Test("缺失中英文文案时回落到 key 名称")
    func missingStringsFallBackToKeyName() {
        #expect(
            AppStrings.text(.settingsTitle, language: .zhHans, zhHans: [:], en: [:]) == "settingsTitle"
        )
    }
}

private func withTemporaryDefaults(_ body: (UserDefaults) throws -> Void) rethrows {
    let suiteName = "AppLanguageSettingsTests.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suiteName)!
    defer { defaults.removePersistentDomain(forName: suiteName) }
    try body(defaults)
}
