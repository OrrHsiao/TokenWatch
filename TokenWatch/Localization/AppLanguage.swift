import Foundation

enum AppLanguage: String, CaseIterable, Sendable, Equatable {
    case zhHans = "zh-Hans"
    case zhHant = "zh-Hant"
    case en
    case ja
    case ko
    case es
    case de
    case fr
    case ptBR = "pt-BR"
    case it
    case nl
    case pl
}

extension AppLanguage {
    var localeIdentifier: String {
        rawValue
    }

    var periodAxisValueName: String {
        switch self {
        case .zhHans, .zhHant:
            return "月份"
        case .ja:
            return "月"
        case .ko:
            return "월"
        case .en:
            return "Period"
        case .es:
            return "Periodo"
        case .de:
            return "Zeitraum"
        case .fr:
            return "Période"
        case .ptBR:
            return "Período"
        case .it:
            return "Periodo"
        case .nl:
            return "Periode"
        case .pl:
            return "Okres"
        }
    }
}

enum AppLanguagePreference: String, CaseIterable, Sendable, Equatable {
    case system
    case zhHans = "zh-Hans"
    case zhHant = "zh-Hant"
    case en
    case ja
    case ko
    case es
    case de
    case fr
    case ptBR = "pt-BR"
    case it
    case nl
    case pl

    /// Returns the localized display title for this language preference.
    func title(language: AppLanguage) -> String {
        switch self {
        case .system:
            return AppStrings.text(.languageSystem, language: language)
        case .zhHans:
            return "简体中文"
        case .zhHant:
            return "繁體中文"
        case .en:
            return "English"
        case .ja:
            return "日本語"
        case .ko:
            return "한국어"
        case .es:
            return "Español"
        case .de:
            return "Deutsch"
        case .fr:
            return "Français"
        case .ptBR:
            return "Português (Brasil)"
        case .it:
            return "Italiano"
        case .nl:
            return "Nederlands"
        case .pl:
            return "Polski"
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
            defaults.string(forKey: Self.storageKey)
                .flatMap(AppLanguagePreference.init(rawValue:))
                ?? .system
        }
        set {
            guard selectedPreference != newValue else { return }
            defaults.set(newValue.rawValue, forKey: Self.storageKey)
            notifyChange()
        }
    }

    /// The concrete language currently used by the app.
    var resolvedLanguage: AppLanguage {
        switch selectedPreference {
        case .system:
            return Self.resolveSystemLanguage(preferredLanguagesProvider())
        case .zhHans:
            return .zhHans
        case .zhHant:
            return .zhHant
        case .en:
            return .en
        case .ja:
            return .ja
        case .ko:
            return .ko
        case .es:
            return .es
        case .de:
            return .de
        case .fr:
            return .fr
        case .ptBR:
            return .ptBR
        case .it:
            return .it
        case .nl:
            return .nl
        case .pl:
            return .pl
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
