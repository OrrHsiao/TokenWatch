import Foundation

enum AppLanguage: String, CaseIterable, Sendable, Equatable {
    case zhHans = "zh-CN"
    case zhHant = "zh-TW"
    case en = "en-US"
    case ja = "ja-JP"
    case ko = "ko-KR"
    case es = "es-ES"
    case de = "de-DE"
    case fr = "fr-FR"
    case ptBR = "pt-BR"
    case it = "it-IT"
    case nl = "nl-NL"
    case pl = "pl-PL"
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

        if matches(normalized, "zh-hant") || matches(normalized, "zh-tw")
            || matches(normalized, "zh-hk") || matches(normalized, "zh-mo") {
            return .zhHant
        }
        if matches(normalized, "zh") {
            return .zhHans
        }
        if matches(normalized, "en") { return .en }
        if matches(normalized, "ja") { return .ja }
        if matches(normalized, "ko") { return .ko }
        if matches(normalized, "es") { return .es }
        if matches(normalized, "de") { return .de }
        if matches(normalized, "fr") { return .fr }
        if matches(normalized, "pt") { return .ptBR }
        if matches(normalized, "it") { return .it }
        if matches(normalized, "nl") { return .nl }
        if matches(normalized, "pl") { return .pl }
        return nil
    }

    private static func matches(_ normalizedIdentifier: String, _ languageIdentifier: String) -> Bool {
        normalizedIdentifier == languageIdentifier || normalizedIdentifier.hasPrefix("\(languageIdentifier)-")
    }

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
