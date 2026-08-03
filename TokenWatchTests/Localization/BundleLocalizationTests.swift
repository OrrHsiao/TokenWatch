import Foundation
import Testing
@testable import TokenWatch

@MainActor
@Suite("BundleLocalization")
struct BundleLocalizationTests {
    private static let expectedLocalizationCodes = Set(AppLanguage.allCases.map(\.rawValue))
    // Xcode 会将 Tagalog 的 InfoPlist 字符串目录规范化为 `fil`，产品偏好仍使用 Codex 的 `tl` 代码。
    private static let infoPlistResourceAliases = ["tl": "fil"]

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
}
