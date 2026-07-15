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

private let validatedLocaleIdentifiers = migratedLocaleIdentifiers
    + westernAndRegionalLocaleIdentifiers

@Suite("AppLocalizationResources")
struct AppLocalizationResourcesTests {
    @Test("迁移的十二份资源均直接定义全部 140 个 key")
    func migratedResourcesDefineAllKeys() throws {
        #expect(AppStringKey.allCases.count == 140)
        try assertCompleteResources(migratedLocaleIdentifiers)
    }

    @Test("西欧、北欧与地区变体的十份资源均直接定义全部 140 个 key")
    func westernAndRegionalResourcesAreComplete() throws {
        #expect(AppStringKey.allCases.count == 140)
        try assertCompleteResources([
            "ca-ES", "da-DK", "es-419", "fi-FI", "fr-CA",
            "is-IS", "nb-NO", "pt-PT", "ro-RO", "sv-SE",
        ])
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
            for key in AppStringKey.allCases {
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
            for key in AppStringKey.allCases {
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
            for key in AppStringKey.allCases {
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
        #expect(
            validationIssues.isEmpty,
            "English reuse allowlist is invalid: \(validationIssues)"
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
            for key in AppStringKey.allCases {
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

private enum LocalizationResourceTestError: Error, CustomStringConvertible {
    case repositoryRootNotFound
    case resourceMissing(String)
    case invalidUTF8(String)
    case invalidPropertyList(String)
    case valueMissing(String, String)
    case malformedFormat(String)

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
    .errorOpenCodeDatabaseNotFoundFormat: [.init(position: 1, type: "@")],
    .errorOpenCodeDatabaseOpenFailedFormat: [
        .init(position: 1, type: "d"), .init(position: 2, type: "@"),
    ],
    .errorOpenCodeDatabaseQueryFailedFormat: [
        .init(position: 1, type: "d"), .init(position: 2, type: "@"),
    ],
]

private let fixedTerms = [
    "AI Token Watch", "Claude Code", "opencode.db", "Codex", "SQLite", "opencode", "Tokens", "Token",
]

private func assertCompleteResources(_ localeIdentifiers: [String]) throws {
    let expectedKeyOrder = AppStringKey.allCases.map(\.rawValue)
    let expectedKeys = Set(expectedKeyOrder)
    let resources = try loadResources(localeIdentifiers)

    for localeIdentifier in localeIdentifiers {
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
        for key in AppStringKey.allCases {
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

private func localizationResourcesURL() throws -> URL {
    var candidate = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
    while candidate.path != "/" {
        let projectURL = candidate.appendingPathComponent("TokenWatch.xcodeproj")
        if FileManager.default.fileExists(atPath: projectURL.path) {
            return candidate.appendingPathComponent("TokenWatch/Localization/Resources", isDirectory: true)
        }
        candidate.deleteLastPathComponent()
    }
    throw LocalizationResourceTestError.repositoryRootNotFound
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
    for term in fixedTerms.sorted(by: { $0.count > $1.count }) {
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
