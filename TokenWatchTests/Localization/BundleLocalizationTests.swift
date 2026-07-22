import Foundation
import Testing
@testable import TokenWatch

@MainActor
@Suite("BundleLocalization")
struct BundleLocalizationTests {
    private static let expectedLocalizationCodes = Set(AppLanguage.allCases.map(\.rawValue))

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
            let resourcePath = try #require(
                bundle.path(
                    forResource: "InfoPlist",
                    ofType: "strings",
                    inDirectory: nil,
                    forLocalization: language
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
