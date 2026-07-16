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

    @Test("完整 locale 匹配忽略大小写并接受下划线")
    func exactLocaleMatchingIsCaseInsensitiveAndAcceptsUnderscores() {
        let cases: [(String, AppLanguage)] = [
            ("en_us", .en),
            ("EN-us", .en),
            ("JA_jp", .ja),
        ]

        for (identifier, language) in cases {
            #expect(AppLanguageSettings.resolveSystemLanguage([identifier]) == language)
        }
    }

    @Test("每个规范 locale 均优先完整匹配")
    func everyCanonicalLocaleMatchesExactly() {
        for language in AppLanguage.allCases {
            #expect(AppLanguageSettings.resolveSystemLanguage([language.rawValue]) == language)
        }
    }

    @Test("首项不受支持时继续解析下一项")
    func unsupportedPreferenceContinuesToNextIdentifier() {
        #expect(AppLanguageSettings.resolveSystemLanguage(["xx-XX", "sv-SE"]) == .svSE)
    }

    @Test("中文按脚本与地区解析为三个冻结变体")
    func chineseIdentifiersResolveByScriptAndRegion() {
        let cases: [(String, AppLanguage)] = [
            ("zh-Hans", .zhHans),
            ("zh-CN", .zhHans),
            ("zh-HK", .zhHK),
            ("zh-MO", .zhHK),
            ("zh-Hant-HK", .zhHK),
            ("zh-Hans-HK", .zhHans),
            ("zh-Hans-TW", .zhHans),
            ("zh-Hant-CN", .zhHant),
            ("zh-TW", .zhHant),
            ("zh-Hant", .zhHant),
            ("zh", .zhHans),
        ]

        for (identifier, language) in cases {
            #expect(AppLanguageSettings.resolveSystemLanguage([identifier]) == language)
        }
    }

    @Test("BCP-47 扩展不参与脚本与地区解析")
    func bcp47ExtensionsDoNotAffectScriptOrRegionResolution() {
        let cases: [(String, AppLanguage)] = [
            ("fr-FR-u-ca-gregory", .fr),
            ("pt-BR-x-pt", .ptBR),
            ("es-ES-x-mx", .es),
            ("zh-Hans-CN-x-hk", .zhHans),
        ]

        for (identifier, language) in cases {
            #expect(AppLanguageSettings.resolveSystemLanguage([identifier]) == language)
        }
    }

    @Test("西班牙语按完整拉美地区集合解析")
    func spanishIdentifiersResolveByRegion() {
        let latinAmericanRegions = [
            "419", "AR", "BO", "BR", "CL", "CO", "CR", "CU", "DO", "EC", "GT",
            "HN", "MX", "NI", "PA", "PE", "PR", "PY", "SV", "US", "UY", "VE",
        ]

        #expect(AppLanguageSettings.resolveSystemLanguage(["es-ES"]) == .es)
        #expect(AppLanguageSettings.resolveSystemLanguage(["es"]) == .es)
        for region in latinAmericanRegions {
            #expect(AppLanguageSettings.resolveSystemLanguage(["es-\(region)"]) == .es419)
        }
        #expect(AppLanguageSettings.resolveSystemLanguage(["es-GQ"]) == .es)
    }

    @Test("法语默认法国并为加拿大保留地区变体")
    func frenchIdentifiersResolveByRegion() {
        let cases: [(String, AppLanguage)] = [
            ("fr-CA", .frCA),
            ("fr-FR", .fr),
            ("fr-BE", .fr),
            ("fr", .fr),
        ]

        for (identifier, language) in cases {
            #expect(AppLanguageSettings.resolveSystemLanguage([identifier]) == language)
        }
    }

    @Test("葡萄牙语默认巴西并为葡萄牙保留地区变体")
    func portugueseIdentifiersResolveByRegion() {
        let cases: [(String, AppLanguage)] = [
            ("pt-PT", .ptPT),
            ("pt-BR", .ptBR),
            ("pt", .ptBR),
        ]

        for (identifier, language) in cases {
            #expect(AppLanguageSettings.resolveSystemLanguage([identifier]) == language)
        }
    }

    @Test("只有一个支持变体的语言按 base code 匹配")
    func singleVariantLanguageMatchesBaseCode() {
        #expect(AppLanguageSettings.resolveSystemLanguage(["de-AT"]) == .de)
    }

    @Test("全部系统语言不受支持时回落到英文")
    func unsupportedSystemLanguagesFallBackToEnglish() {
        #expect(AppLanguageSettings.resolveSystemLanguage(["xx-XX", "yy-YY"]) == .en)
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
            #expect(AppLanguageSettings.storageKey == "TokenWatch.languagePreference")
            for (storedValue, language) in cases {
                defaults.set(storedValue, forKey: "TokenWatch.languagePreference")
                let settings = AppLanguageSettings(defaults: defaults)

                #expect(settings.selectedPreference == .language(language))
            }
        }
    }

    @Test("再次保存旧语言偏好会写回规范 locale")
    func savingLegacyPreferenceCanonicalizesStorage() {
        withTemporaryDefaults { defaults in
            defaults.set("en", forKey: AppLanguageSettings.storageKey)
            let settings = AppLanguageSettings(defaults: defaults)
            var notificationCount = 0
            _ = settings.observe { notificationCount += 1 }

            settings.selectedPreference = .language(.en)

            #expect(defaults.string(forKey: AppLanguageSettings.storageKey) == "en-US")
            #expect(notificationCount == 1)
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

    @Test("代表性新增语言返回已审定的设置标题")
    func representativeLocalesReturnApprovedSettingsTitles() {
        let samples: [(AppLanguage, String)] = [
            (.ar, "الإعدادات"),
            (.hiIN, "सेटिंग्ज़"),
            (.thTH, "การตั้งค่า"),
            (.ukUA, "Параметри"),
            (.viVN, "Cài đặt"),
            (.zhHK, "設定"),
            (.es419, "Configuración"),
            (.ptPT, "Definições"),
        ]

        for (language, expectedTitle) in samples {
            #expect(AppStrings.text(.settingsTitle, language: language) == expectedTitle)
        }
    }

    @Test func migratedLoginItemStatusStringsRemainUnchanged() {
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
