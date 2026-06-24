import Foundation

enum AppLanguage: String, Sendable, Equatable {
    case zhHans
    case en
}

enum AppLanguagePreference: String, CaseIterable, Sendable, Equatable {
    case system
    case zhHans = "zh-Hans"
    case en

    /// Returns the localized display title for this language preference.
    func title(language: AppLanguage) -> String {
        switch self {
        case .system:
            return AppStrings.text(.languageSystem, language: language)
        case .zhHans:
            return AppStrings.text(.languageChinese, language: language)
        case .en:
            return AppStrings.text(.languageEnglish, language: language)
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
        case .en:
            return .en
        }
    }

    /// Resolves a system language identifier list to the supported app language.
    static func resolveSystemLanguage(_ preferredLanguages: [String]) -> AppLanguage {
        guard let identifier = preferredLanguages.first?.lowercased() else {
            return .en
        }

        if identifier.hasPrefix("zh") {
            return .zhHans
        }

        if identifier.hasPrefix("en") {
            return .en
        }

        return .en
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
