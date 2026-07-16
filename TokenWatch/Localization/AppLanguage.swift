import Foundation

enum AppLanguage: String, CaseIterable, Sendable, Equatable {
    case en = "en-US"
    case am
    case ar
    case bgBG = "bg-BG"
    case bnBD = "bn-BD"
    case bsBA = "bs-BA"
    case caES = "ca-ES"
    case csCZ = "cs-CZ"
    case daDK = "da-DK"
    case de = "de-DE"
    case elGR = "el-GR"
    case es419 = "es-419"
    case es = "es-ES"
    case etEE = "et-EE"
    case fa
    case fiFI = "fi-FI"
    case frCA = "fr-CA"
    case fr = "fr-FR"
    case guIN = "gu-IN"
    case hiIN = "hi-IN"
    case hrHR = "hr-HR"
    case huHU = "hu-HU"
    case hyAM = "hy-AM"
    case idID = "id-ID"
    case isIS = "is-IS"
    case it = "it-IT"
    case ja = "ja-JP"
    case kaGE = "ka-GE"
    case kk
    case knIN = "kn-IN"
    case ko = "ko-KR"
    case lt
    case lvLV = "lv-LV"
    case mkMK = "mk-MK"
    case ml
    case mn
    case mrIN = "mr-IN"
    case msMY = "ms-MY"
    case myMM = "my-MM"
    case nbNO = "nb-NO"
    case nl = "nl-NL"
    case pa
    case pl = "pl-PL"
    case ptBR = "pt-BR"
    case ptPT = "pt-PT"
    case roRO = "ro-RO"
    case ruRU = "ru-RU"
    case skSK = "sk-SK"
    case slSI = "sl-SI"
    case soSO = "so-SO"
    case sqAL = "sq-AL"
    case srRS = "sr-RS"
    case svSE = "sv-SE"
    case swTZ = "sw-TZ"
    case taIN = "ta-IN"
    case teIN = "te-IN"
    case thTH = "th-TH"
    case tl
    case trTR = "tr-TR"
    case ukUA = "uk-UA"
    case ur
    case viVN = "vi-VN"
    case zhHans = "zh-CN"
    case zhHK = "zh-HK"
    case zhHant = "zh-TW"
}

extension AppLanguage {
    var localeIdentifier: String {
        rawValue
    }

    var resourceIdentifier: String {
        rawValue
    }

    var baseLanguageCode: String {
        rawValue.split(separator: "-", maxSplits: 1).first.map(String.init)?.lowercased() ?? rawValue
    }

    var nativeDisplayName: String {
        Locale(identifier: rawValue).localizedString(forIdentifier: rawValue) ?? rawValue
    }

    var usesCompactCJKFormatting: Bool {
        ["zh", "ja", "ko"].contains(baseLanguageCode)
    }

    var usesFullWidthParentheses: Bool {
        baseLanguageCode == "zh"
    }

    var yearAxisSuffix: String? {
        switch baseLanguageCode {
        case "zh", "ja":
            return "年"
        case "ko":
            return "년"
        default:
            return nil
        }
    }

    var hourSuffix: String? {
        switch baseLanguageCode {
        case "zh":
            return "时"
        case "ja":
            return "時"
        case "ko":
            return "시"
        default:
            return nil
        }
    }

}

enum AppLanguagePreference: CaseIterable, Sendable, Equatable {
    case system
    case language(AppLanguage)

    static var allCases: [Self] {
        [.system] + AppLanguage.allCases.map(Self.language)
    }

    var storageValue: String {
        switch self {
        case .system:
            return "system"
        case .language(let language):
            return language.rawValue
        }
    }

    /// Returns the localized display title for this language preference.
    func title(language displayLanguage: AppLanguage) -> String {
        switch self {
        case .system:
            return AppStrings.text(.languageSystem, language: displayLanguage)
        case .language(let language):
            return language.nativeDisplayName
        }
    }
}

@MainActor
final class AppLanguageSettings {
    struct ObservationToken: Hashable, Sendable {
        let id: UUID
    }

    static let shared = AppLanguageSettings(defaults: .standard)
    static let storageKey = "TokenWatch.languagePreference"

    private let defaults: UserDefaults
    private let preferredLanguagesProvider: () -> [String]
    private var observers: [ObservationToken: @MainActor () -> Void] = [:]

    init(
        defaults: UserDefaults,
        preferredLanguagesProvider: @escaping () -> [String] = { Locale.preferredLanguages }
    ) {
        self.defaults = defaults
        self.preferredLanguagesProvider = preferredLanguagesProvider
    }

    /// The persisted language preference. Missing or invalid stored values are treated as `.system`.
    var selectedPreference: AppLanguagePreference {
        get {
            guard let storedValue = defaults.string(forKey: Self.storageKey) else {
                return .system
            }
            if let language = AppLanguage(rawValue: storedValue) {
                return .language(language)
            }
            if let language = Self.legacyLanguagesByStorageValue[storedValue] {
                return .language(language)
            }
            return .system
        }
        set {
            guard selectedPreference != newValue else { return }
            defaults.set(newValue.storageValue, forKey: Self.storageKey)
            notifyChange()
        }
    }

    /// The concrete language currently used by the app.
    var resolvedLanguage: AppLanguage {
        switch selectedPreference {
        case .system:
            return Self.resolveSystemLanguage(preferredLanguagesProvider())
        case .language(let language):
            return language
        }
    }

    /// Resolves a system language identifier list to the supported app language.
    static func resolveSystemLanguage(_ preferredLanguages: [String]) -> AppLanguage {
        for identifier in preferredLanguages {
            if let language = supportedLanguage(for: identifier) {
                return language
            }
        }

        return .en
    }

    private static func supportedLanguage(for identifier: String) -> AppLanguage? {
        let normalized = identifier
            .replacingOccurrences(of: "_", with: "-")
            .lowercased()

        if let exactMatch = AppLanguage.allCases.first(where: {
            $0.rawValue.lowercased() == normalized
        }) {
            return exactMatch
        }

        let subtags = normalized.split(separator: "-").map(String.init)
        guard let baseLanguageCode = subtags.first else { return nil }
        let variantSubtags = Set(subtags.dropFirst())

        // 这些语言各有多个资源变体，不能用通用 base-code 规则任意选择第一项。
        switch baseLanguageCode {
        case "zh":
            if !variantSubtags.isDisjoint(with: ["hk", "mo"]) {
                return .zhHK
            }
            if !variantSubtags.isDisjoint(with: ["tw", "hant"]) {
                return .zhHant
            }
            return .zhHans
        case "es":
            return variantSubtags.isDisjoint(with: latinAmericanSpanishRegions) ? .es : .es419
        case "fr":
            return variantSubtags.contains("ca") ? .frCA : .fr
        case "pt":
            return variantSubtags.contains("pt") ? .ptPT : .ptBR
        default:
            let candidates = AppLanguage.allCases.filter {
                $0.baseLanguageCode == baseLanguageCode
            }
            return candidates.count == 1 ? candidates[0] : nil
        }
    }

    private static let latinAmericanSpanishRegions: Set<String> = [
        "419", "ar", "bo", "br", "cl", "co", "cr", "cu", "do", "ec", "gt",
        "hn", "mx", "ni", "pa", "pe", "pr", "py", "sv", "us", "uy", "ve",
    ]

    private static let legacyLanguagesByStorageValue: [String: AppLanguage] = [
        "en": .en,
        "zh-Hans": .zhHans,
        "zh-Hant": .zhHant,
        "ja": .ja,
        "ko": .ko,
        "es": .es,
        "de": .de,
        "fr": .fr,
        "pt-BR": .ptBR,
        "it": .it,
        "nl": .nl,
        "pl": .pl,
    ]

    /// Registers a main-actor observer that is called synchronously after preference changes.
    @discardableResult
    func observe(_ handler: @escaping @MainActor () -> Void) -> ObservationToken {
        let token = ObservationToken(id: UUID())
        observers[token] = handler
        return token
    }

    /// Removes a previously registered language-change observer.
    func removeObserver(_ token: ObservationToken) {
        observers.removeValue(forKey: token)
    }

    private func notifyChange() {
        for handler in Array(observers.values) {
            handler()
        }
    }
}
