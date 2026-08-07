import Foundation
import Testing
@testable import TokenWatch

@MainActor
@Suite("BundleLocalization")
struct BundleLocalizationTests {
    private static let expectedLocalizationCodes = Set(AppLanguage.allCases.map(\.rawValue))
    // Xcode 会将 Tagalog 的 InfoPlist 字符串目录规范化为 `fil`，产品偏好仍使用 Codex 的 `tl` 代码。
    private static let infoPlistResourceAliases = ["tl": "fil"]
    private static let widgetResourceAliases = [
        "en-US": "en",
        "de-DE": "de",
        "es-ES": "es",
        "fr-FR": "fr",
        "it-IT": "it",
        "ja-JP": "ja",
        "ko-KR": "ko",
        "nl-NL": "nl",
        "pl-PL": "pl",
        "tl": "fil",
        "zh-CN": "zh-Hans",
        "zh-TW": "zh-Hant",
    ]

    @Test("应用 Bundle 声明全部支持语言")
    func bundleDeclaresAllSupportedLanguages() throws {
        let bundle = Bundle(for: AppDelegate.self)
        let expected = Self.expectedLocalizationCodes
        let declaredCodes = try #require(
            bundle.object(forInfoDictionaryKey: "CFBundleLocalizations") as? [String]
        )

        #expect(Set(declaredCodes) == expected)
        #expect(Set(bundle.localizations).isSuperset(of: expected))

        for language in expected.sorted() {
            let infoPlistLocalization = Self.infoPlistResourceAliases[language] ?? language
            let resourcePath = try #require(
                bundle.path(
                    forResource: "InfoPlist",
                    ofType: "strings",
                    inDirectory: nil,
                    forLocalization: infoPlistLocalization
                )
            )
            let values = try #require(
                NSDictionary(contentsOfFile: resourcePath) as? [String: String]
            )

            #expect(values["CFBundleDisplayName"] == "AI Token Watch")
            #expect(values["CFBundleName"] == "AI Token Watch")
        }
    }

    @Test("Widget 成品 Bundle 可直接读取全部语言的锁定提示")
    func widgetBundleContainsLocalizedLockedGuidance() throws {
        let appBundle = Bundle(for: AppDelegate.self)
        let plugInsURL = try #require(appBundle.builtInPlugInsURL)
        let widgetBundle = try #require(Bundle(
            url: plugInsURL.appendingPathComponent("TokenWatchWidgets.appex", isDirectory: true)
        ))
        var lockedGuidanceByLanguage: [String: String] = [:]

        for language in AppLanguage.allCases {
            let resourceLocalization = Self.widgetResourceAliases[language.rawValue]
                ?? language.rawValue
            let resourcePath = try #require(widgetBundle.path(
                forResource: "Localizable",
                ofType: "strings",
                inDirectory: nil,
                forLocalization: resourceLocalization
            ))
            let values = try #require(
                NSDictionary(contentsOfFile: resourcePath) as? [String: String]
            )
            let localizedBundle = try #require(Bundle(
                url: URL(fileURLWithPath: resourcePath).deletingLastPathComponent()
            ))
            let lockedGuidance = localizedBundle.localizedString(
                forKey: "widget.locked",
                value: "__TOKENWATCH_MISSING_WIDGET_LOCALIZATION__",
                table: "Localizable"
            )

            #expect(values.count == 16)
            #expect(lockedGuidance == values["widget.locked"])
            #expect(!lockedGuidance.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            #expect(lockedGuidance != "__TOKENWATCH_MISSING_WIDGET_LOCALIZATION__")
            lockedGuidanceByLanguage[language.rawValue] = lockedGuidance
        }

        #expect(lockedGuidanceByLanguage["zh-CN"] != lockedGuidanceByLanguage["zh-TW"])
        #expect(lockedGuidanceByLanguage["zh-HK"] == lockedGuidanceByLanguage["zh-TW"])
    }
}
