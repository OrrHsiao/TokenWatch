import Foundation
import Testing
@testable import TokenWatch

private let migratedLocaleIdentifiers = [
    "en-US", "zh-CN", "zh-TW", "ja-JP", "ko-KR", "es-ES",
    "de-DE", "fr-FR", "pt-BR", "it-IT", "nl-NL", "pl-PL",
]

private let westernAndRegionalLocaleIdentifiers = [
    "ca-ES", "da-DK", "es-419", "fi-FI", "fr-CA",
    "is-IS", "nb-NO", "pt-PT", "ro-RO", "sv-SE",
]

private let centralEuropeanLatinLocaleIdentifiers = [
    "bs-BA", "cs-CZ", "et-EE", "hr-HR", "hu-HU", "lt",
    "lv-LV", "sk-SK", "sl-SI", "sq-AL", "tr-TR",
]

private let easternEuropeanAndCentralAsianLocaleIdentifiers = [
    "bg-BG", "el-GR", "hy-AM", "ka-GE", "kk",
    "mk-MK", "mn", "ru-RU", "sr-RS", "uk-UA",
]

private let middleEasternAndSouthAsianLocaleIdentifiers = [
    "ar", "bn-BD", "fa", "gu-IN", "hi-IN", "kn-IN",
    "ml", "mr-IN", "pa", "ta-IN", "te-IN", "ur",
]

private let africanSoutheastAsianAndHongKongLocaleIdentifiers = [
    "am", "id-ID", "ms-MY", "my-MM", "so-SO",
    "sw-TZ", "th-TH", "tl", "vi-VN", "zh-HK",
]

private let validatedLocaleIdentifiers = migratedLocaleIdentifiers
    + westernAndRegionalLocaleIdentifiers
    + centralEuropeanLatinLocaleIdentifiers
    + easternEuropeanAndCentralAsianLocaleIdentifiers
    + middleEasternAndSouthAsianLocaleIdentifiers
    + africanSoutheastAsianAndHongKongLocaleIdentifiers

private func resourceKeys(for localeIdentifier: String) -> [AppStringKey] {
    AppStringKey.allCases
}

// 独立抄录产品设计冻结清单，避免测试从 AppLanguage 或分批数组继承同一处遗漏。
private let frozenCodexLocaleIdentifiers = [
    "en-US",
    "am",
    "ar",
    "bg-BG",
    "bn-BD",
    "bs-BA",
    "ca-ES",
    "cs-CZ",
    "da-DK",
    "de-DE",
    "el-GR",
    "es-419",
    "es-ES",
    "et-EE",
    "fa",
    "fi-FI",
    "fr-CA",
    "fr-FR",
    "gu-IN",
    "hi-IN",
    "hr-HR",
    "hu-HU",
    "hy-AM",
    "id-ID",
    "is-IS",
    "it-IT",
    "ja-JP",
    "ka-GE",
    "kk",
    "kn-IN",
    "ko-KR",
    "lt",
    "lv-LV",
    "mk-MK",
    "ml",
    "mn",
    "mr-IN",
    "ms-MY",
    "my-MM",
    "nb-NO",
    "nl-NL",
    "pa",
    "pl-PL",
    "pt-BR",
    "pt-PT",
    "ro-RO",
    "ru-RU",
    "sk-SK",
    "sl-SI",
    "so-SO",
    "sq-AL",
    "sr-RS",
    "sv-SE",
    "sw-TZ",
    "ta-IN",
    "te-IN",
    "th-TH",
    "tl",
    "tr-TR",
    "uk-UA",
    "ur",
    "vi-VN",
    "zh-CN",
    "zh-HK",
    "zh-TW",
]

@Suite("AppLocalizationResources")
struct AppLocalizationResourcesTests {
    @Test("迁移的十二份资源均直接定义全部 189 个 key")
    func migratedResourcesDefineAllKeys() throws {
        #expect(AppStringKey.allCases.count == 189)
        try assertCompleteResources(migratedLocaleIdentifiers)
    }

    @Test("西欧、北欧与地区变体的十份资源均直接定义全部 189 个 key")
    func westernAndRegionalResourcesAreComplete() throws {
        #expect(AppStringKey.allCases.count == 189)
        try assertCompleteResources([
            "ca-ES", "da-DK", "es-419", "fi-FI", "fr-CA",
            "is-IS", "nb-NO", "pt-PT", "ro-RO", "sv-SE",
        ])
    }

    @Test("中东欧拉丁文字的十一份资源均直接定义全部 189 个 key")
    func centralEuropeanLatinResourcesAreComplete() throws {
        #expect(AppStringKey.allCases.count == 189)
        try assertCompleteResources(centralEuropeanLatinLocaleIdentifiers)
    }

    @Test("东欧、高加索与中亚文字的十份资源均直接定义全部 189 个 key")
    func easternEuropeanAndCentralAsianResourcesAreComplete() throws {
        #expect(AppStringKey.allCases.count == 189)
        try assertCompleteResources(easternEuropeanAndCentralAsianLocaleIdentifiers)
    }

    @Test("中东与南亚文字的十二份资源均直接定义全部 189 个 key")
    func middleEasternAndSouthAsianResourcesAreComplete() throws {
        #expect(AppStringKey.allCases.count == 189)
        try assertCompleteResources(middleEasternAndSouthAsianLocaleIdentifiers)
    }

    @Test("非洲、东南亚与香港中文的十份资源均直接定义全部 189 个 key")
    func africanSoutheastAsianAndHongKongResourcesAreComplete() throws {
        #expect(AppStringKey.allCases.count == 189)
        try assertCompleteResources(africanSoutheastAsianAndHongKongLocaleIdentifiers)
    }

    @Test("源码资源目录与冻结的 65 个 Codex locale 完全一致")
    func sourceResourceDirectoriesMatchFrozenCodexLocales() throws {
        #expect(frozenCodexLocaleIdentifiers.count == 65)
        #expect(Set(frozenCodexLocaleIdentifiers).count == frozenCodexLocaleIdentifiers.count)

        let resourcesURL = try localizationResourcesURL()
        let directoryURLs = try FileManager.default.contentsOfDirectory(
            at: resourcesURL,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        )
        let resourceLocaleIdentifiers = try directoryURLs.compactMap { directoryURL -> String? in
            guard directoryURL.pathExtension == "lproj",
                  try directoryURL.resourceValues(forKeys: [.isDirectoryKey]).isDirectory == true else {
                return nil
            }
            return directoryURL.deletingPathExtension().lastPathComponent
        }

        #expect(Set(resourceLocaleIdentifiers) == Set(frozenCodexLocaleIdentifiers))
        try assertCompleteResources(frozenCodexLocaleIdentifiers)
    }

    @Test("三条授权面板文案在全部语言中均为选择与通常路径、命令定位两行")
    func providerOpenPanelMessagesAreExactlyTwoLines() throws {
        let expectedDetails: [(key: AppStringKey, usualPath: String, command: String)] = [
            (
                .claudeDataDirectoryOpenPanelMessage,
                "~/.claude",
                "echo \"${CLAUDE_CONFIG_DIR:-$HOME/.claude}\""
            ),
            (
                .codexDataDirectoryOpenPanelMessage,
                "~/.codex",
                "echo \"${CODEX_HOME:-$HOME/.codex}\""
            ),
            (
                .openCodeDataDirectoryOpenPanelMessage,
                "~/.local/share/opencode",
                "echo \"${XDG_DATA_HOME:-$HOME/.local/share}/opencode\""
            ),
        ]
        let removedStructureTerms = ["projects", "sessions", "archived_sessions", "opencode.db"]
        let resources = try loadResources(frozenCodexLocaleIdentifiers)

        for localeIdentifier in frozenCodexLocaleIdentifiers {
            let resource = try requiredResource(localeIdentifier, in: resources)
            for (key, usualPath, expectedCommand) in expectedDetails {
                let message = try requiredValue(key, in: resource)
                let lines = message.components(separatedBy: "\n")
                #expect(
                    lines.count == 2,
                    "Expected exactly two lines in \(localeIdentifier)/\(key.rawValue)"
                )
                guard lines.count == 2 else { continue }

                for line in lines {
                    #expect(!line.isEmpty, "Empty line in \(localeIdentifier)/\(key.rawValue)")
                    #expect(
                        line == line.trimmingCharacters(in: .whitespaces),
                        "Leading or trailing whitespace in \(localeIdentifier)/\(key.rawValue)"
                    )
                }
                #expect(occurrenceCount(of: usualPath, in: lines[0]) == 1)
                #expect(!lines[0].contains(expectedCommand))
                #expect(!lines[1].contains(usualPath))
                #expect(occurrenceCount(of: expectedCommand, in: lines[1]) == 1)
                #expect(lines[1] != expectedCommand)
                #expect(!message.contains(" · "))
                #expect(
                    removedStructureTerms.allSatisfy { !message.contains($0) },
                    "Obsolete structure guidance in \(localeIdentifier)/\(key.rawValue)"
                )
            }
        }
    }

    @Test("Xcode localization 元数据与冻结目录完全一致")
    func projectLocalizationMetadataMatchesFrozenCodexLocales() throws {
        let metadata = try projectLocalizationMetadata()
        let expectedKnownRegions = frozenCodexLocaleIdentifiers + ["Base"]

        #expect(metadata.developmentRegion == "en-US")
        #expect(metadata.knownRegions == expectedKnownRegions)
        #expect(Set(metadata.knownRegions) == Set(expectedKnownRegions))
    }

    @Test("InfoPlist 品牌名已完成全部目标语言审核且没有空版权项")
    func infoPlistCatalogIsCompleteAndReviewed() throws {
        let catalogURL = try repositoryRootURL()
            .appendingPathComponent("TokenWatch/InfoPlist.xcstrings")
        let data = try Data(contentsOf: catalogURL)
        let root = try #require(
            try JSONSerialization.jsonObject(with: data) as? [String: Any]
        )
        let strings = try #require(root["strings"] as? [String: Any])
        let expectedLocales = Set(frozenCodexLocaleIdentifiers + ["en"])
        let infoPlistData = try Data(
            contentsOf: try repositoryRootURL().appendingPathComponent("TokenWatch/Info.plist")
        )
        let infoPlist = try #require(
            try PropertyListSerialization.propertyList(from: infoPlistData, format: nil)
                as? [String: Any]
        )

        #expect(Set(strings.keys) == Set(["CFBundleDisplayName", "CFBundleName"]))
        #expect(infoPlist["NSHumanReadableCopyright"] == nil)
        for value in strings.values {
            let entry = try #require(value as? [String: Any])
            let localizations = try #require(entry["localizations"] as? [String: Any])
            #expect(Set(localizations.keys) == expectedLocales)

            for (locale, localization) in localizations {
                let localizedEntry = try #require(localization as? [String: Any])
                let stringUnit = try #require(localizedEntry["stringUnit"] as? [String: Any])
                let expectedState = locale == "en" ? "new" : "translated"
                #expect(stringUnit["state"] as? String == expectedState)
                #expect(stringUnit["value"] as? String == "AI Token Watch")
            }
        }
    }

    @Test("Widget Extension 文案覆盖所有支持语言")
    func widgetExtensionStringsCoverAllSupportedLanguages() throws {
        let catalog = try widgetExtensionLocalizationCatalog()
        let expectedLocales = Set(AppLanguage.allCases.map(widgetExtensionLocaleIdentifier))
        let expectedKeys = [
            "widget.dated.format",
            "widget.heatmap.description",
            "widget.heatmap.name",
            "widget.heatmap.title",
            "widget.hourly.description",
            "widget.hourly.name",
            "widget.locked",
            "widget.monthlyBudget.name",
            "widget.modelFocus.name",
            "widget.notReady",
            "widget.projectFocus.name",
            "widget.today.title",
            "widget.updated.format",
            "widget.weekly.axis.day",
            "widget.weekly.axis.tokens",
            "widget.weekly.name",
        ]
        let formattedKeys = Set([
            "widget.dated.format",
            "widget.updated.format",
        ])
        let expectedFormatSignature = [FormatArgument(position: 1, type: "@")]

        #expect(Set(catalog.keys) == Set(expectedKeys))

        for key in expectedKeys {
            let localizations = try #require(catalog[key])
            #expect(
                Set(localizations.keys) == expectedLocales,
                "Unexpected locale coverage for \(key)"
            )
            for (locale, value) in localizations {
                #expect(
                    !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                    "Empty value in Widget Extension for \(locale)/\(key)"
                )
                if formattedKeys.contains(key) {
                    let signature = try formatSignature(
                        value,
                        context: "Widget Extension \(locale)/\(key)"
                    )
                    #expect(signature == expectedFormatSignature)
                }
            }
        }

        let lockedGuidance = try #require(catalog["widget.locked"])
        let englishLockedGuidance = try #require(lockedGuidance["en"])
        for (locale, value) in lockedGuidance where locale != "en" {
            #expect(
                value.trimmingCharacters(in: .whitespacesAndNewlines)
                    != englishLockedGuidance,
                "English lock guidance reused for \(locale)"
            )
        }
        #expect(lockedGuidance["zh-Hans"] != lockedGuidance["zh-Hant"])
        #expect(lockedGuidance["zh-HK"] == lockedGuidance["zh-Hant"])
    }

    @Test("月度预算标题与 Widget 无快照回退文案保持一致")
    func monthlyBudgetTitleMatchesWidgetFallback() throws {
        let catalog = try widgetExtensionLocalizationCatalog()
        let titles = try #require(catalog["widget.monthlyBudget.name"])

        for language in AppLanguage.allCases {
            let widgetLocale = widgetExtensionLocaleIdentifier(for: language)
            let fallbackTitle = try #require(titles[widgetLocale])
            #expect(
                AppStrings.text(.widgetMonthlyBudgetTitle, language: language) == fallbackTitle,
                "Monthly budget title differs between host and Widget fallback for \(language.rawValue)"
            )
        }
    }

    @Test("所有格式参数签名与英文基准一致")
    func localizedFormatSignaturesMatchEnglish() throws {
        let resources = try loadResources(validatedLocaleIdentifiers)
        let english = try requiredResource("en-US", in: resources)
        let englishSignatures = try signatures(in: english.values)

        #expect(Set(englishSignatures.keys) == Set(expectedFormatSignatures.keys))
        for (key, expectedSignature) in expectedFormatSignatures {
            #expect(englishSignatures[key] == expectedSignature, "Unexpected English signature for \(key.rawValue)")
        }

        for localeIdentifier in validatedLocaleIdentifiers where localeIdentifier != "en-US" {
            let resource = try requiredResource(localeIdentifier, in: resources)
            let localizedSignatures = try signatures(in: resource.values)
            for key in resourceKeys(for: localeIdentifier) {
                #expect(
                    localizedSignatures[key] == englishSignatures[key],
                    "Placeholder mismatch for \(localeIdentifier)/\(key.rawValue)"
                )
            }
        }
    }

    @Test("格式扫描器支持位置参数与转义百分号并拒绝非法格式")
    func formatScannerValidatesSupportedSyntax() throws {
        #expect(
            try formatSignature("%2$d %% %1$@", context: "test") == [
                .init(position: 1, type: "@"),
                .init(position: 2, type: "d"),
            ]
        )
        #expect(throws: LocalizationResourceTestError.self) {
            try formatSignature("%@ %2$d", context: "mixed")
        }
        #expect(throws: LocalizationResourceTestError.self) {
            try formatSignature("%2$@", context: "out-of-range")
        }
        #expect(throws: LocalizationResourceTestError.self) {
            try formatSignature("%f", context: "unknown")
        }
    }

    @Test("声明扫描器不会漏掉等号换行的重复 key")
    func declarationScannerCountsSplitLineDuplicates() throws {
        let source = """
        "settingsTitle" = "Settings";
        "settingsTitle"
        = "Override";
        """

        #expect(try declaredLocalizationKeys(in: source) == ["settingsTitle", "settingsTitle"])
    }

    @Test("声明扫描器不会漏掉同一行的重复 key")
    func declarationScannerCountsSameLineDuplicates() throws {
        let source = #""settingsTitle" = "Settings"; "settingsTitle" = "Override";"#

        #expect(try declaredLocalizationKeys(in: source) == ["settingsTitle", "settingsTitle"])
    }

    @Test("每个 locale 子 Bundle 可直接读取每个 key")
    func localeBundlesReadEveryKeyDirectly() throws {
        let resources = try loadResources(validatedLocaleIdentifiers)
        let missingSentinel = "__TOKENWATCH_MISSING_LOCALIZATION__"

        for localeIdentifier in validatedLocaleIdentifiers {
            let resource = try requiredResource(localeIdentifier, in: resources)
            let localeBundle = try #require(Bundle(url: resource.directoryURL))
            for key in resourceKeys(for: localeIdentifier) {
                let value = localeBundle.localizedString(
                    forKey: key.rawValue,
                    value: missingSentinel,
                    table: "Localizable"
                )
                #expect(value != missingSentinel, "Bundle lookup missed \(localeIdentifier)/\(key.rawValue)")
            }
        }
    }

    @Test("英文复用仅限固定术语或逐 key 人工许可")
    func englishReuseHasExactReviewedAllowlist() throws {
        let resources = try loadResources(validatedLocaleIdentifiers)
        let english = try requiredResource("en-US", in: resources)
        var requiredAllowlistPairs = Set<LocalizationKey>()

        for localeIdentifier in validatedLocaleIdentifiers where localeIdentifier != "en-US" {
            let localized = try requiredResource(localeIdentifier, in: resources)
            for key in resourceKeys(for: localeIdentifier) {
                let englishValue = try requiredValue(key, in: english)
                let localizedValue = try requiredValue(key, in: localized)
                let exactlyReusesEnglish = localizedValue == englishValue
                    && !isPureFixedTerminology(localizedValue)
                let reusesEnglishPhrase = sharesEnglishWordNGram(
                    englishValue: englishValue,
                    localizedValue: localizedValue
                )
                if exactlyReusesEnglish || reusesEnglishPhrase {
                    requiredAllowlistPairs.insert(.init(localeIdentifier: localeIdentifier, key: key))
                }
            }
        }

        let validationIssues = englishReuseAllowlistValidationIssues(
            localizationEnglishReuseAllowlist,
            validatedLocaleIdentifiers: validatedLocaleIdentifiers,
            requiredPairs: requiredAllowlistPairs
        )
        let configuredAllowlistPairs = Set(localizationEnglishReuseAllowlist.map {
            LocalizationKey(localeIdentifier: $0.localeIdentifier, key: $0.key)
        })
        let missingAllowlistEntries = requiredAllowlistPairs
            .subtracting(configuredAllowlistPairs)
            .map { "\($0.localeIdentifier)/\($0.key.rawValue)" }
            .sorted()
        let staleAllowlistEntries = configuredAllowlistPairs
            .subtracting(requiredAllowlistPairs)
            .map { "\($0.localeIdentifier)/\($0.key.rawValue)" }
            .sorted()
        #expect(
            validationIssues.isEmpty,
            "English reuse allowlist is invalid: \(validationIssues); missing=\(missingAllowlistEntries); stale=\(staleAllowlistEntries)"
        )
    }

    @Test("完整 allowlist 校验不会忽略未知 locale 的无效记录")
    func englishReuseAllowlistValidatesCompleteInput() {
        let invalidAllowances: [LocalizationEnglishReuseAllowance] = [
            .init(localeIdentifier: "zz-ZZ", key: .languageEnglish, reason: ""),
            .init(localeIdentifier: "zz-ZZ", key: .languageEnglish, reason: "重复记录"),
        ]

        let issues = englishReuseAllowlistValidationIssues(
            invalidAllowances,
            validatedLocaleIdentifiers: validatedLocaleIdentifiers,
            requiredPairs: []
        )

        #expect(Set(issues) == [
            .unknownLocale("zz-ZZ"),
            .duplicateLocaleKey,
            .emptyReason,
            .usageMismatch,
        ])
    }

    @Test("产品与数据源固定名称保留大小写和出现次数")
    func fixedTerminologyIsPreservedExactly() throws {
        let resources = try loadResources(validatedLocaleIdentifiers)
        let english = try requiredResource("en-US", in: resources)

        for localeIdentifier in validatedLocaleIdentifiers where localeIdentifier != "en-US" {
            let localized = try requiredResource(localeIdentifier, in: resources)
            for key in resourceKeys(for: localeIdentifier) {
                let englishValue = try requiredValue(key, in: english)
                let localizedValue = try requiredValue(key, in: localized)
                for term in fixedTerms {
                    let englishCount = occurrenceCount(of: term, in: englishValue)
                    guard englishCount > 0 else { continue }
                    #expect(
                        occurrenceCount(of: term, in: localizedValue) == englishCount,
                        "Fixed term \(term) differs in \(localeIdentifier)/\(key.rawValue)"
                    )
                }
            }
        }
    }
}

private struct LocalizationResource {
    let localeIdentifier: String
    let directoryURL: URL
    let values: [String: String]
    let declaredKeys: [String]
}

private struct LocalizationKey: Hashable {
    let localeIdentifier: String
    let key: AppStringKey
}

private enum EnglishReuseAllowlistValidationIssue: Hashable {
    case unknownLocale(String)
    case duplicateLocaleKey
    case emptyReason
    case usageMismatch
}

private struct FormatArgument: Equatable, Hashable {
    let position: Int
    let type: String
}

private struct ProjectLocalizationMetadata {
    let developmentRegion: String
    let knownRegions: [String]
}

private enum LocalizationResourceTestError: Error, CustomStringConvertible {
    case repositoryRootNotFound
    case resourceMissing(String)
    case invalidUTF8(String)
    case invalidPropertyList(String)
    case valueMissing(String, String)
    case malformedFormat(String)
    case invalidProjectLocalizationMetadata
    case invalidWidgetLocalizationCatalog

    var description: String {
        switch self {
        case .repositoryRootNotFound:
            return "Could not locate repository root from #filePath"
        case .resourceMissing(let localeIdentifier):
            return "Missing Localizable.strings for \(localeIdentifier)"
        case .invalidUTF8(let localeIdentifier):
            return "Localizable.strings is not UTF-8 for \(localeIdentifier)"
        case .invalidPropertyList(let localeIdentifier):
            return "Localizable.strings is not a string property list for \(localeIdentifier)"
        case .valueMissing(let localeIdentifier, let key):
            return "Missing value for \(localeIdentifier)/\(key)"
        case .malformedFormat(let message):
            return message
        case .invalidProjectLocalizationMetadata:
            return "Could not parse localization metadata from project.pbxproj"
        case .invalidWidgetLocalizationCatalog:
            return "Could not parse Widget Extension localization catalog"
        }
    }
}

private let expectedFormatSignatures: [AppStringKey: [FormatArgument]] = [
    .dashboardTotalSourcesProjectsFormat: [
        .init(position: 1, type: "d"), .init(position: 2, type: "d"),
    ],
    .dashboardScanUpdatedFormat: [.init(position: 1, type: "@")],
    .dashboardMinutesAgoFormat: [.init(position: 1, type: "d")],
    .dashboardHoursAgoFormat: [.init(position: 1, type: "d")],
    .dashboardShowingSessionsFormat: [
        .init(position: 1, type: "@"),
        .init(position: 2, type: "@"),
        .init(position: 3, type: "@"),
    ],
    .periodNoTokenDataFormat: [.init(position: 1, type: "@")],
    .chartTokenAccessibilityFormat: [.init(position: 1, type: "@")],
    .chartCostAccessibilityFormat: [.init(position: 1, type: "@")],
    .widgetDatedUsageTitleFormat: [.init(position: 1, type: "@")],
    .widgetUpdatedThroughTitleFormat: [.init(position: 1, type: "@")],
    .widgetPurchaseActionFormat: [.init(position: 1, type: "@")],
    .errorCannotAccessProviderDirectoryFormat: [.init(position: 1, type: "@")],
    .errorProviderDirectoryAuthorizationFailedFormat: [.init(position: 1, type: "@")],
    .errorDirectoryNotDirectoryFormat: [.init(position: 1, type: "@")],
    .errorCannotEnumerateDirectoryFormat: [.init(position: 1, type: "@")],
    .errorOpenCodeDatabaseNotFoundFormat: [.init(position: 1, type: "@")],
    .errorOpenCodeDatabaseOpenFailedFormat: [
        .init(position: 1, type: "d"), .init(position: 2, type: "@"),
    ],
    .errorOpenCodeDatabaseQueryFailedFormat: [
        .init(position: 1, type: "d"), .init(position: 2, type: "@"),
    ],
]

private let fixedTerms = [
    "AI Token Watch", "App Store", "Claude Code", "opencode.db", "Codex", "SQLite", "opencode", "Tokens", "Token",
    "echo \"${CLAUDE_CONFIG_DIR:-$HOME/.claude}\"", "CLAUDE_CONFIG_DIR",
    "echo \"${CODEX_HOME:-$HOME/.codex}\"", "CODEX_HOME",
    "echo \"${XDG_DATA_HOME:-$HOME/.local/share}/opencode\"", "XDG_DATA_HOME",
    "~/.claude", "~/.codex", "~/.local/share/opencode", ".claude", ".codex",
]

// 目录中的固定子路径可能因语言而显示为原名或译名；仅在英文短语复用扫描时忽略它们。
private let englishReuseIgnoredTerms = fixedTerms + ["projects", "sessions", "archived_sessions"]

private func assertCompleteResources(_ localeIdentifiers: [String]) throws {
    let resources = try loadResources(localeIdentifiers)

    for localeIdentifier in localeIdentifiers {
        let expectedKeyOrder = resourceKeys(for: localeIdentifier).map(\.rawValue)
        let expectedKeys = Set(expectedKeyOrder)
        let resource = try requiredResource(localeIdentifier, in: resources)
        let uniqueDeclaredKeys = Set(resource.declaredKeys)
        #expect(
            resource.declaredKeys.count == uniqueDeclaredKeys.count,
            "Duplicate key declaration in \(localeIdentifier)"
        )
        #expect(
            uniqueDeclaredKeys == Set(resource.values.keys),
            "Raw declarations and parsed keys differ in \(localeIdentifier)"
        )
        #expect(resource.declaredKeys == expectedKeyOrder, "Unexpected key order in \(localeIdentifier)")
        #expect(Set(resource.values.keys) == expectedKeys, "Incomplete key set in \(localeIdentifier)")
        for key in resourceKeys(for: localeIdentifier) {
            let value = try requiredValue(key, in: resource)
            #expect(
                !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                "Empty value in \(localeIdentifier)/\(key.rawValue)"
            )
            #expect(value != key.rawValue, "Raw key used as value in \(localeIdentifier)/\(key.rawValue)")
        }
    }
}

private func loadResources(_ localeIdentifiers: [String]) throws -> [String: LocalizationResource] {
    let resourcesURL = try localizationResourcesURL()
    return try Dictionary(uniqueKeysWithValues: localeIdentifiers.map { localeIdentifier in
        let directoryURL = resourcesURL.appendingPathComponent("\(localeIdentifier).lproj", isDirectory: true)
        let stringsURL = directoryURL.appendingPathComponent("Localizable.strings")
        guard FileManager.default.fileExists(atPath: stringsURL.path) else {
            throw LocalizationResourceTestError.resourceMissing(localeIdentifier)
        }

        let data = try Data(contentsOf: stringsURL)
        guard let source = String(data: data, encoding: .utf8) else {
            throw LocalizationResourceTestError.invalidUTF8(localeIdentifier)
        }
        let propertyList = try PropertyListSerialization.propertyList(from: data, format: nil)
        guard let values = propertyList as? [String: String] else {
            throw LocalizationResourceTestError.invalidPropertyList(localeIdentifier)
        }
        let declaredKeys = try declaredLocalizationKeys(in: source)
        return (localeIdentifier, LocalizationResource(
            localeIdentifier: localeIdentifier,
            directoryURL: directoryURL,
            values: values,
            declaredKeys: declaredKeys
        ))
    })
}

private func repositoryRootURL() throws -> URL {
    var candidate = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
    while candidate.path != "/" {
        let projectURL = candidate.appendingPathComponent("TokenWatch.xcodeproj")
        if FileManager.default.fileExists(atPath: projectURL.path) {
            return candidate
        }
        candidate.deleteLastPathComponent()
    }
    throw LocalizationResourceTestError.repositoryRootNotFound
}

private func localizationResourcesURL() throws -> URL {
    try repositoryRootURL().appendingPathComponent("TokenWatch/Localization/Resources", isDirectory: true)
}

private func widgetExtensionLocalizationCatalog() throws -> [String: [String: String]] {
    let catalogURL = try repositoryRootURL().appendingPathComponent(
        "TokenWatchWidgets/Localizable.xcstrings"
    )
    let data = try Data(contentsOf: catalogURL)
    guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
          let strings = root["strings"] as? [String: Any] else {
        throw LocalizationResourceTestError.invalidWidgetLocalizationCatalog
    }

    return try strings.reduce(into: [String: [String: String]]()) { result, entry in
        guard let value = entry.value as? [String: Any] else {
            throw LocalizationResourceTestError.invalidWidgetLocalizationCatalog
        }
        guard let rawLocalizations = value["localizations"] else {
            return
        }
        guard let localizations = rawLocalizations as? [String: Any] else {
            throw LocalizationResourceTestError.invalidWidgetLocalizationCatalog
        }
        let values = try localizations.reduce(into: [String: String]()) { localizedValues, localization in
            guard let localizationValue = localization.value as? [String: Any],
                  let stringUnit = localizationValue["stringUnit"] as? [String: Any],
                  let value = stringUnit["value"] as? String else {
                throw LocalizationResourceTestError.invalidWidgetLocalizationCatalog
            }
            localizedValues[localization.key] = value
        }
        result[entry.key] = values
    }
}

private func widgetExtensionLocaleIdentifier(for language: AppLanguage) -> String {
    switch language {
    case .en:
        return "en"
    case .de:
        return "de"
    case .es:
        return "es"
    case .fr:
        return "fr"
    case .it:
        return "it"
    case .ja:
        return "ja"
    case .ko:
        return "ko"
    case .nl:
        return "nl"
    case .pl:
        return "pl"
    case .zhHans:
        return "zh-Hans"
    case .zhHant:
        return "zh-Hant"
    case .tl:
        return "fil"
    default:
        return language.rawValue
    }
}

private func projectLocalizationMetadata() throws -> ProjectLocalizationMetadata {
    let projectURL = try repositoryRootURL().appendingPathComponent("TokenWatch.xcodeproj/project.pbxproj")
    let source = try String(contentsOf: projectURL, encoding: .utf8)
    let fullRange = NSRange(source.startIndex..<source.endIndex, in: source)

    let developmentRegionExpression = try NSRegularExpression(
        pattern: #"developmentRegion\s*=\s*\"?([^\";]+)\"?;"#
    )
    let knownRegionsExpression = try NSRegularExpression(
        pattern: #"knownRegions\s*=\s*\((.*?)\);"#,
        options: [.dotMatchesLineSeparators]
    )
    guard let developmentMatch = developmentRegionExpression.firstMatch(in: source, range: fullRange),
          let developmentRange = Range(developmentMatch.range(at: 1), in: source),
          let knownRegionsMatch = knownRegionsExpression.firstMatch(in: source, range: fullRange),
          let knownRegionsRange = Range(knownRegionsMatch.range(at: 1), in: source) else {
        throw LocalizationResourceTestError.invalidProjectLocalizationMetadata
    }

    let developmentRegion = source[developmentRange]
        .trimmingCharacters(in: .whitespacesAndNewlines)
    let knownRegions = source[knownRegionsRange]
        .split(whereSeparator: { $0.isNewline })
        .compactMap { line -> String? in
            let value = line
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .trimmingCharacters(in: CharacterSet(charactersIn: ","))
                .trimmingCharacters(in: CharacterSet(charactersIn: "\""))
            return value.isEmpty ? nil : value
        }

    return ProjectLocalizationMetadata(
        developmentRegion: developmentRegion,
        knownRegions: knownRegions
    )
}

private func declaredLocalizationKeys(in source: String) throws -> [String] {
    let expression = try NSRegularExpression(
        pattern: #""([A-Za-z][A-Za-z0-9]*)"(?=\s*=)"#
    )
    let range = NSRange(source.startIndex..<source.endIndex, in: source)
    return expression.matches(in: source, range: range).compactMap { match in
        guard let keyRange = Range(match.range(at: 1), in: source) else { return nil }
        return String(source[keyRange])
    }
}

private func englishReuseAllowlistValidationIssues(
    _ allowances: [LocalizationEnglishReuseAllowance],
    validatedLocaleIdentifiers: [String],
    requiredPairs: Set<LocalizationKey>
) -> [EnglishReuseAllowlistValidationIssue] {
    let validatedIdentifiers = Set(validatedLocaleIdentifiers)
    let unknownIdentifiers = Set(allowances.map(\.localeIdentifier))
        .subtracting(validatedIdentifiers)
        .sorted()
    let allowancePairs = Set(allowances.map {
        LocalizationKey(localeIdentifier: $0.localeIdentifier, key: $0.key)
    })
    var issues = unknownIdentifiers.map(EnglishReuseAllowlistValidationIssue.unknownLocale)
    if allowancePairs.count != allowances.count {
        issues.append(.duplicateLocaleKey)
    }
    if allowances.contains(where: {
        $0.reason.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }) {
        issues.append(.emptyReason)
    }
    if allowancePairs != requiredPairs {
        issues.append(.usageMismatch)
    }
    return issues
}

private func requiredResource(
    _ localeIdentifier: String,
    in resources: [String: LocalizationResource]
) throws -> LocalizationResource {
    guard let resource = resources[localeIdentifier] else {
        throw LocalizationResourceTestError.resourceMissing(localeIdentifier)
    }
    return resource
}

private func requiredValue(
    _ key: AppStringKey,
    in resource: LocalizationResource
) throws -> String {
    guard let value = resource.values[key.rawValue] else {
        throw LocalizationResourceTestError.valueMissing(resource.localeIdentifier, key.rawValue)
    }
    return value
}

private func signatures(in values: [String: String]) throws -> [AppStringKey: [FormatArgument]] {
    var result: [AppStringKey: [FormatArgument]] = [:]
    for key in AppStringKey.allCases {
        guard let value = values[key.rawValue] else { continue }
        let signature = try formatSignature(value, context: key.rawValue)
        if !signature.isEmpty {
            result[key] = signature
        }
    }
    return result
}

private func formatSignature(_ value: String, context: String) throws -> [FormatArgument] {
    let characters = Array(value)
    var arguments: [FormatArgument] = []
    var index = 0
    var sawExplicitPosition = false
    var sawImplicitPosition = false

    while index < characters.count {
        guard characters[index] == "%" else {
            index += 1
            continue
        }
        guard index + 1 < characters.count else {
            throw LocalizationResourceTestError.malformedFormat("Trailing % in \(context)")
        }
        if characters[index + 1] == "%" {
            index += 2
            continue
        }

        var cursor = index + 1
        var positionDigits = ""
        while cursor < characters.count, ("0"..."9").contains(characters[cursor]) {
            positionDigits.append(characters[cursor])
            cursor += 1
        }

        let position: Int
        if positionDigits.isEmpty {
            sawImplicitPosition = true
            position = arguments.count + 1
        } else {
            sawExplicitPosition = true
            guard cursor < characters.count, characters[cursor] == "$",
                  let explicitPosition = Int(positionDigits), explicitPosition > 0 else {
                throw LocalizationResourceTestError.malformedFormat("Invalid positional format in \(context)")
            }
            position = explicitPosition
            cursor += 1
        }

        guard !(sawExplicitPosition && sawImplicitPosition) else {
            throw LocalizationResourceTestError.malformedFormat("Mixed implicit and explicit positions in \(context)")
        }
        guard cursor < characters.count else {
            throw LocalizationResourceTestError.malformedFormat("Missing format type in \(context)")
        }
        let type = String(characters[cursor])
        guard type == "@" || type == "d" else {
            throw LocalizationResourceTestError.malformedFormat("Unknown format %\(type) in \(context)")
        }
        arguments.append(.init(position: position, type: type))
        index = cursor + 1
    }

    if sawExplicitPosition, arguments.contains(where: { $0.position > arguments.count }) {
        throw LocalizationResourceTestError.malformedFormat("Out-of-range format position in \(context)")
    }
    return arguments.sorted {
        $0.position == $1.position ? $0.type < $1.type : $0.position < $1.position
    }
}

private func isPureFixedTerminology(_ value: String) -> Bool {
    guard fixedTerms.contains(where: { occurrenceCount(of: $0, in: value) > 0 }) else {
        return false
    }
    var remainder = value
    for term in fixedTerms.sorted(by: { $0.count > $1.count }) {
        remainder = remainder.replacingOccurrences(of: term, with: "")
    }
    remainder = remainder.replacingOccurrences(
        of: #"%(?:[1-9][0-9]*\$)?[@d]|%%"#,
        with: "",
        options: .regularExpression
    )
    return remainder.unicodeScalars.allSatisfy {
        CharacterSet.whitespacesAndNewlines.contains($0)
            || CharacterSet.punctuationCharacters.contains($0)
            || CharacterSet.symbols.contains($0)
            || CharacterSet.decimalDigits.contains($0)
    }
}

private func sharesEnglishWordNGram(englishValue: String, localizedValue: String) -> Bool {
    let englishBigrams = wordBigrams(in: englishValue)
    guard !englishBigrams.isEmpty else { return false }
    return !englishBigrams.isDisjoint(with: wordBigrams(in: localizedValue))
}

private func wordBigrams(in value: String) -> Set<String> {
    var stripped = value
    for term in englishReuseIgnoredTerms.sorted(by: { $0.count > $1.count }) {
        stripped = stripped.replacingOccurrences(of: term, with: " ")
    }
    stripped = stripped.replacingOccurrences(
        of: #"%(?:[1-9][0-9]*\$)?[@d]|%%"#,
        with: " ",
        options: .regularExpression
    )
    let words = letterWords(in: stripped).map { $0.lowercased() }
    guard words.count >= 2 else { return [] }
    return Set((0..<(words.count - 1)).map { "\(words[$0])\u{0}\(words[$0 + 1])" })
}

private func letterWords(in value: String) -> [String] {
    guard let expression = try? NSRegularExpression(pattern: #"\p{L}+"#) else { return [] }
    let range = NSRange(value.startIndex..<value.endIndex, in: value)
    return expression.matches(in: value, range: range).compactMap { match in
        guard let wordRange = Range(match.range, in: value) else { return nil }
        return String(value[wordRange])
    }
}

private func occurrenceCount(of term: String, in value: String) -> Int {
    let pattern: String
    if term == "Token" {
        // Token 可直接与目标语言词缀或复合词相连；只排除 Tokens 的前缀重叠。
        pattern = #"Token(?!s)"#
    } else {
        pattern = NSRegularExpression.escapedPattern(for: term)
    }
    guard let expression = try? NSRegularExpression(pattern: pattern) else { return 0 }
    let range = NSRange(value.startIndex..<value.endIndex, in: value)
    return expression.numberOfMatches(in: value, range: range)
}
