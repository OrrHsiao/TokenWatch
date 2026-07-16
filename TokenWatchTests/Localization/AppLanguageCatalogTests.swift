import Foundation
import Testing
@testable import TokenWatch

// 独立抄录产品冻结清单，避免目录测试从生产 enum 继承顺序或遗漏。
private let frozenLocaleIdentifiers = [
    "en-US", "am", "ar", "bg-BG", "bn-BD", "bs-BA", "ca-ES", "cs-CZ",
    "da-DK", "de-DE", "el-GR", "es-419", "es-ES", "et-EE", "fa", "fi-FI",
    "fr-CA", "fr-FR", "gu-IN", "hi-IN", "hr-HR", "hu-HU", "hy-AM", "id-ID",
    "is-IS", "it-IT", "ja-JP", "ka-GE", "kk", "kn-IN", "ko-KR", "lt",
    "lv-LV", "mk-MK", "ml", "mn", "mr-IN", "ms-MY", "my-MM", "nb-NO",
    "nl-NL", "pa", "pl-PL", "pt-BR", "pt-PT", "ro-RO", "ru-RU", "sk-SK",
    "sl-SI", "so-SO", "sq-AL", "sr-RS", "sv-SE", "sw-TZ", "ta-IN", "te-IN",
    "th-TH", "tl", "tr-TR", "uk-UA", "ur", "vi-VN", "zh-CN", "zh-HK", "zh-TW",
]

@Suite("AppLanguageCatalog")
struct AppLanguageCatalogTests {
    @Test("语言目录与冻结的 65 locale 顺序完全一致")
    func catalogMatchesFrozenLocaleOrder() {
        let localeIdentifiers = AppLanguage.allCases.map(\.rawValue)

        #expect(frozenLocaleIdentifiers.count == 65)
        #expect(localeIdentifiers == frozenLocaleIdentifiers)
        #expect(Set(localeIdentifiers).count == localeIdentifiers.count)
    }

    @Test("每种语言的资源标识与展示名均有效")
    func catalogEntriesExposeResourcesAndNativeNames() {
        for language in AppLanguage.allCases {
            #expect(language.resourceIdentifier == language.rawValue)
            #expect(!language.nativeDisplayName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
    }

    @Test("偏好目录由系统项和冻结顺序的 65 种语言组成")
    func preferencesAreSystemFollowedByFrozenLanguages() {
        let preferences = AppLanguagePreference.allCases

        #expect(preferences.count == 66)
        #expect(preferences.first == .system)
        #expect(
            Array(preferences.dropFirst())
                == AppLanguage.allCases.map(AppLanguagePreference.language)
        )
    }
}
