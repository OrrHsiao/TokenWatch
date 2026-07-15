import Foundation
import Testing
@testable import TokenWatch

@MainActor
@Suite("AppLanguageSettings")
struct AppLanguageSettingsTests {
    @Test("缺失值回落到跟随系统")
    func missingPreferenceFallsBackToSystem() throws {
        withTemporaryDefaults { defaults in
            let settings = AppLanguageSettings(defaults: defaults, preferredLanguagesProvider: { ["zh-Hans-US"] })

            #expect(settings.selectedPreference == .system)
            #expect(settings.resolvedLanguage == .zhHans)
        }
    }

    @Test("非法值回落到跟随系统")
    func invalidPreferenceFallsBackToSystem() throws {
        withTemporaryDefaults { defaults in
            defaults.set("xx", forKey: AppLanguageSettings.storageKey)
            let settings = AppLanguageSettings(defaults: defaults, preferredLanguagesProvider: { ["en-US"] })

            #expect(settings.selectedPreference == .system)
            #expect(settings.resolvedLanguage == .en)
        }
    }

    @Test("中文系统语言解析为中文")
    func systemChineseResolvesToChinese() throws {
        withTemporaryDefaults { defaults in
            let settings = AppLanguageSettings(defaults: defaults, preferredLanguagesProvider: { ["zh-Hant-TW"] })

            #expect(settings.resolvedLanguage == .zhHant)
        }
    }

    @Test("英文系统语言解析为英文")
    func systemEnglishResolvesToEnglish() throws {
        withTemporaryDefaults { defaults in
            let settings = AppLanguageSettings(defaults: defaults, preferredLanguagesProvider: { ["en-US"] })

            #expect(settings.resolvedLanguage == .en)
        }
    }

    @Test("系统语言解析覆盖新增语言")
    func supportedSystemLanguagesResolveToMatchingLanguages() {
        let cases: [(String, AppLanguage)] = [
            ("zh-Hans-CN", .zhHans),
            ("zh-Hant-TW", .zhHant),
            ("ja-JP", .ja),
            ("ko-KR", .ko),
            ("es-ES", .es),
            ("de-DE", .de),
            ("fr-FR", .fr),
            ("pt-BR", .ptBR),
            ("it-IT", .it),
            ("nl-NL", .nl),
            ("pl-PL", .pl),
        ]

        for (identifier, language) in cases {
            #expect(AppLanguageSettings.resolveSystemLanguage([identifier]) == language)
        }
    }

    @Test("其他系统语言回落到英文")
    func unsupportedSystemLanguageFallsBackToEnglish() throws {
        withTemporaryDefaults { defaults in
            let settings = AppLanguageSettings(defaults: defaults, preferredLanguagesProvider: { ["sv-SE"] })

            #expect(settings.resolvedLanguage == .en)
        }
    }

    @Test("现有语言先使用精确 locale code")
    func existingLanguagesUseCanonicalLocaleCodes() {
        #expect(AppLanguage.allCases.map(\.rawValue) == [
            "zh-CN", "zh-TW", "en-US", "ja-JP", "ko-KR", "es-ES",
            "de-DE", "fr-FR", "pt-BR", "it-IT", "nl-NL", "pl-PL",
        ])
    }

    @Test("偏好列表由跟随系统与具体语言组成")
    func preferencesAreSystemFollowedByLanguages() {
        #expect(
            AppLanguagePreference.allCases
                == [AppLanguagePreference.system]
                    + AppLanguage.allCases.map(AppLanguagePreference.language)
        )
    }

    @Test("语言族属性保留当前展示规则")
    func languageFamilyPropertiesPreserveFormatting() {
        #expect(AppLanguage.zhHans.baseLanguageCode == "zh")
        #expect(AppLanguage.zhHant.usesCompactCJKFormatting)
        #expect(AppLanguage.ja.yearAxisSuffix == "年")
        #expect(AppLanguage.ko.yearAxisSuffix == "년")
        #expect(AppLanguage.en.yearAxisSuffix == nil)
        #expect(AppLanguage.zhHans.hourSuffix == "时")
        #expect(AppLanguage.ja.hourSuffix == "時")
        #expect(AppLanguage.ko.hourSuffix == "시")
        #expect(AppLanguage.en.hourSuffix == nil)
        #expect(AppLanguage.zhHans.usesFullWidthParentheses)
        #expect(!AppLanguage.ja.usesFullWidthParentheses)
    }

    @Test("旧语言偏好值会迁移到具体语言")
    func legacyLanguagePreferenceValuesResolveToLanguages() {
        let cases: [(String, AppLanguage)] = [
            ("en", .en),
            ("zh-Hans", .zhHans),
            ("zh-Hant", .zhHant),
            ("ja", .ja),
            ("ko", .ko),
            ("es", .es),
            ("de", .de),
            ("fr", .fr),
            ("pt-BR", .ptBR),
            ("it", .it),
            ("nl", .nl),
            ("pl", .pl),
        ]

        withTemporaryDefaults { defaults in
            for (storedValue, language) in cases {
                defaults.set(storedValue, forKey: AppLanguageSettings.storageKey)
                let settings = AppLanguageSettings(defaults: defaults)

                #expect(settings.selectedPreference == .language(language))
            }
        }
    }

    @Test("选择英文会持久化并通知观察者")
    func selectingEnglishPersistsAndNotifies() throws {
        withTemporaryDefaults { defaults in
            let settings = AppLanguageSettings(defaults: defaults, preferredLanguagesProvider: { ["zh-Hans-US"] })
            var notificationCount = 0
            let token = settings.observe { notificationCount += 1 }

            settings.selectedPreference = .language(.en)

            #expect(defaults.string(forKey: AppLanguageSettings.storageKey) == "en-US")
            #expect(settings.resolvedLanguage == .en)
            #expect(notificationCount == 1)

            settings.removeObserver(token)
            settings.selectedPreference = .language(.zhHans)
            #expect(notificationCount == 1)
        }
    }

    @Test("基础文案按语言返回")
    func stringsReturnLocalizedText() {
        #expect(AppStrings.text(.settingsTitle, language: .zhHans) == "设置")
        #expect(AppStrings.text(.settingsTitle, language: .zhHant) == "設定")
        #expect(AppStrings.text(.settingsTitle, language: .en) == "Settings")
        #expect(AppStrings.text(.settingsTitle, language: .ja) == "設定")
        #expect(AppStrings.text(.settingsTitle, language: .ko) == "설정")
        #expect(AppStrings.text(.settingsTitle, language: .es) == "Configuración")
        #expect(AppStrings.text(.settingsTitle, language: .de) == "Einstellungen")
        #expect(AppStrings.text(.settingsTitle, language: .fr) == "Paramètres")
        #expect(AppStrings.text(.settingsTitle, language: .ptBR) == "Configurações")
        #expect(AppStrings.text(.settingsTitle, language: .it) == "Impostazioni")
        #expect(AppStrings.text(.settingsTitle, language: .nl) == "Instellingen")
        #expect(AppStrings.text(.settingsTitle, language: .pl) == "Ustawienia")
        #expect(AppLanguagePreference.system.title(language: .zhHans) == "跟随系统")
        #expect(AppLanguagePreference.system.title(language: .en) == "System")
        #expect(
            AppLanguagePreference.language(.zhHant).title(language: .zhHans)
                == AppLanguage.zhHant.nativeDisplayName
        )
        #expect(
            AppLanguagePreference.language(.ptBR).title(language: .en)
                == AppLanguage.ptBR.nativeDisplayName
        )
    }

    @Test func loginItemStatusStringsCoverEverySupportedLanguage() {
        let expected: [AppLanguage: (approval: String, unavailable: String, open: String)] = [
            .zhHans: ("需要在系统设置中批准开机自启动。", "当前无法使用开机自启动。", "打开登录项设置"),
            .zhHant: ("需要在「系統設定」中核准登入時啟動。", "目前無法使用登入時啟動。", "打開登入項目設定"),
            .en: ("Approval is required in System Settings to launch at login.", "Launch at login is currently unavailable.", "Open Login Items Settings"),
            .ja: ("ログイン時に起動するには、システム設定での承認が必要です。", "現在、ログイン時の起動は利用できません。", "ログイン項目設定を開く"),
            .ko: ("로그인 시 실행하려면 시스템 설정에서 승인이 필요합니다.", "현재 로그인 시 실행을 사용할 수 없습니다.", "로그인 항목 설정 열기"),
            .es: ("Se requiere aprobación en Ajustes del Sistema para iniciar al iniciar sesión.", "El inicio al iniciar sesión no está disponible actualmente.", "Abrir ajustes de ítems de inicio"),
            .de: ("Für den Start bei der Anmeldung ist eine Genehmigung in den Systemeinstellungen erforderlich.", "Der Start bei der Anmeldung ist derzeit nicht verfügbar.", "Anmeldeobjekteinstellungen öffnen"),
            .fr: ("L’approbation dans Réglages Système est requise pour le lancement à l’ouverture de session.", "Le lancement à l’ouverture de session est actuellement indisponible.", "Ouvrir les réglages des éléments d’ouverture"),
            .ptBR: ("É necessária aprovação nos Ajustes do Sistema para iniciar ao entrar.", "A inicialização ao entrar não está disponível no momento.", "Abrir ajustes de itens de início"),
            .it: ("Per l’avvio al login è necessaria l’approvazione in Impostazioni di Sistema.", "L’avvio al login non è attualmente disponibile.", "Apri le impostazioni degli elementi login"),
            .nl: ("Voor starten bij inloggen is goedkeuring in Systeeminstellingen vereist.", "Starten bij inloggen is momenteel niet beschikbaar.", "Instellingen voor inlogonderdelen openen"),
            .pl: ("Uruchamianie przy logowaniu wymaga zatwierdzenia w Ustawieniach systemowych.", "Uruchamianie przy logowaniu jest obecnie niedostępne.", "Otwórz ustawienia rzeczy otwieranych"),
        ]

        #expect(expected.count == AppLanguage.allCases.count)
        for (language, value) in expected {
            #expect(AppStrings.text(.settingsLaunchAtLoginRequiresApproval, language: language) == value.approval)
            #expect(AppStrings.text(.settingsLaunchAtLoginUnavailable, language: language) == value.unavailable)
            #expect(AppStrings.text(.settingsOpenLoginItemsSettings, language: language) == value.open)
        }
    }

    @Test("英文文案表覆盖所有 key")
    func englishStringTableCoversAllKeys() {
        for key in AppStringKey.allCases {
            #expect(
                AppStrings.text(key, language: .en) != String(describing: key),
                "Missing English string for \(key)"
            )
        }
    }

    @Test("所有文案 key 均解析为非空字符串")
    func allStringKeysResolveToNonEmptyText() {
        for key in AppStringKey.allCases {
            for language in AppLanguage.allCases {
                #expect(
                    !AppStrings.text(key, language: language).trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                    "Empty string for \(key) in \(language)"
                )
            }
        }
    }

    @Test("已移除页面副标题文案 key")
    func removedPageSubtitleKeysAreNotLocalized() {
        let keyNames = Set(AppStringKey.allCases.map { String(describing: $0) })

        #expect(!keyNames.contains("totalSubtitle"))
        #expect(!keyNames.contains("periodSubtitleSuffix"))
    }

    @Test("缺失目标文案时依次回落到英文与 raw key")
    func missingStringsFallBackToEnglishThenRawKey() {
        var requestedLanguages: [AppLanguage] = []
        #expect(
            AppStrings.text(.settingsTitle, language: .zhHans) { language, key in
                requestedLanguages.append(language)
                return language == .en && key == .settingsTitle ? "Settings" : nil
            } == "Settings"
        )
        #expect(requestedLanguages == [.zhHans, .en])

        requestedLanguages.removeAll()
        #expect(
            AppStrings.text(.settingsTitle, language: .zhHans) { language, _ in
                requestedLanguages.append(language)
                return language == .zhHans ? "设置" : "Settings"
            } == "设置"
        )
        #expect(requestedLanguages == [.zhHans])

        requestedLanguages.removeAll()
        #expect(
            AppStrings.text(.settingsTitle, language: .zhHans) { language, _ in
                requestedLanguages.append(language)
                return nil
            }
                == AppStringKey.settingsTitle.rawValue
        )
        #expect(requestedLanguages == [.zhHans, .en])
    }
}

private func withTemporaryDefaults(_ body: (UserDefaults) throws -> Void) rethrows {
    let suiteName = "AppLanguageSettingsTests.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suiteName)!
    defer { defaults.removePersistentDomain(forName: suiteName) }
    try body(defaults)
}
