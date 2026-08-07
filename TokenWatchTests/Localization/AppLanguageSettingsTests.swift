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

    @Test("已迁移语言的 Support 文案保持翻译")
    func supportStringCoversMigratedLanguages() {
        let expected: [AppLanguage: String] = [
            .zhHans: "支持",
            .zhHant: "支援",
            .en: "Support",
            .ja: "サポート",
            .ko: "지원",
            .es: "Soporte",
            .de: "Support",
            .fr: "Assistance",
            .ptBR: "Suporte",
            .it: "Supporto",
            .nl: "Ondersteuning",
            .pl: "Wsparcie",
        ]

        #expect(expected.count == 12)
        for (language, text) in expected {
            #expect(AppStrings.text(.support, language: language) == text)
        }
    }

    @Test("已迁移语言的首次目录授权引导文案保持翻译")
    func initialDirectoryAuthorizationGuideStringsCoverMigratedLanguages() {
        let expected: [AppLanguage: (title: String, message: String, openSettings: String, later: String)] = [
            .zhHans: ("设置数据文件夹", "请在设置中选择数据文件夹以查看用量。应用不会自动访问任何文件夹或请求权限。", "前往设置", "稍后"),
            .zhHant: ("設定資料檔案夾", "請在設定中選擇資料檔案夾以查看用量。應用程式不會自動存取任何資料夾或請求權限。", "前往設定", "稍後"),
            .en: ("Set Up Data Folders", "Choose data folders in Settings to view usage. The app will not access any folder or request permission automatically.", "Go to Settings", "Later"),
            .ja: ("データフォルダを設定", "使用量を表示するには、設定でデータフォルダを選択してください。アプリがフォルダに自動でアクセスしたり、権限を求めたりすることはありません。", "設定を開く", "あとで"),
            .ko: ("데이터 폴더 설정", "사용량을 보려면 설정에서 데이터 폴더를 선택하세요. 앱은 폴더에 자동으로 접근하거나 권한을 요청하지 않습니다.", "설정으로 이동", "나중에"),
            .es: ("Configura las carpetas de datos", "Para ver el uso, elige carpetas de datos en Configuración. La app no accederá a ninguna carpeta ni solicitará permisos automáticamente.", "Ir a Configuración", "Más tarde"),
            .de: ("Datenordner einrichten", "Um die Nutzung anzuzeigen, wähle Datenordner in den Einstellungen aus. Die App greift nicht automatisch auf Ordner zu und fordert keine Berechtigung an.", "Zu den Einstellungen", "Später"),
            .fr: ("Configurer les dossiers de données", "Pour afficher l’utilisation, choisissez des dossiers de données dans Paramètres. L’app n’accédera à aucun dossier et ne demandera pas d’autorisation automatiquement.", "Ouvrir les paramètres", "Plus tard"),
            .ptBR: ("Configurar pastas de dados", "Para ver o uso, escolha pastas de dados em Configurações. O app não acessará nenhuma pasta nem solicitará permissão automaticamente.", "Ir para Configurações", "Mais tarde"),
            .it: ("Configura le cartelle dati", "Per visualizzare l’utilizzo, scegli le cartelle dati in Impostazioni. L’app non accederà automaticamente a nessuna cartella né chiederà autorizzazioni.", "Vai a Impostazioni", "Più tardi"),
            .nl: ("Gegevensmappen instellen", "Kies gegevensmappen in Instellingen om het gebruik te bekijken. De app opent geen map en vraagt niet automatisch om toestemming.", "Ga naar Instellingen", "Later"),
            .pl: ("Skonfiguruj foldery danych", "Aby wyświetlić użycie, wybierz foldery danych w Ustawieniach. Aplikacja nie uzyska automatycznie dostępu do żadnego folderu ani nie poprosi o uprawnienia.", "Przejdź do Ustawień", "Później"),
        ]

        #expect(expected.count == 12)
        for (language, value) in expected {
            #expect(AppStrings.text(.initialDirectoryAuthorizationGuideTitle, language: language) == value.title)
            #expect(AppStrings.text(.initialDirectoryAuthorizationGuideMessage, language: language) == value.message)
            #expect(AppStrings.text(.initialDirectoryAuthorizationGuideOpenSettings, language: language) == value.openSettings)
            #expect(AppStrings.text(.initialDirectoryAuthorizationGuideLater, language: language) == value.later)
        }
    }

    @Test func loginItemStatusStringsCoverMigratedLanguages() {
        let expected: [AppLanguage: (approval: String, open: String)] = [
            .zhHans: ("需要在系统设置中批准开机自启动。", "打开登录项设置"),
            .zhHant: ("需要在「系統設定」中核准登入時啟動。", "打開登入項目設定"),
            .en: ("Approval is required in System Settings to launch at login.", "Open Login Items Settings"),
            .ja: ("ログイン時に起動するには、システム設定での承認が必要です。", "ログイン項目設定を開く"),
            .ko: ("로그인 시 실행하려면 시스템 설정에서 승인이 필요합니다.", "로그인 항목 설정 열기"),
            .es: ("Se requiere aprobación en Ajustes del Sistema para iniciar al iniciar sesión.", "Abrir ajustes de ítems de inicio"),
            .de: ("Für den Start bei der Anmeldung ist eine Genehmigung in den Systemeinstellungen erforderlich.", "Anmeldeobjekteinstellungen öffnen"),
            .fr: ("L’approbation dans Réglages Système est requise pour le lancement à l’ouverture de session.", "Ouvrir les réglages des éléments d’ouverture"),
            .ptBR: ("É necessária aprovação nos Ajustes do Sistema para iniciar ao entrar.", "Abrir ajustes de itens de início"),
            .it: ("Per l’avvio al login è necessaria l’approvazione in Impostazioni di Sistema.", "Apri le impostazioni degli elementi login"),
            .nl: ("Voor starten bij inloggen is goedkeuring in Systeeminstellingen vereist.", "Instellingen voor inlogonderdelen openen"),
            .pl: ("Uruchamianie przy logowaniu wymaga zatwierdzenia w Ustawieniach systemowych.", "Otwórz ustawienia rzeczy otwieranych"),
        ]

        #expect(expected.count == 12)
        for (language, value) in expected {
            #expect(AppStrings.text(.settingsLaunchAtLoginRequiresApproval, language: language) == value.approval)
            #expect(AppStrings.text(.settingsOpenLoginItemsSettings, language: language) == value.open)
        }
    }

    @Test
    func directoryAuthorizationStringsCoverMigratedLanguages() {
        let keys: [AppStringKey] = [
            .settingsDataFoldersTitle,
            .settingsDescription,
            .settingsDirectoryNotSelected,
            .settingsDirectorySelected,
            .settingsDirectoryNeedsReselection,
            .settingsDirectoryNoData,
            .settingsChooseDirectory,
            .settingsReselectDirectory,
            .settingsChooseAgain,
            .dashboardUnauthorized,
            .settingsAuthorized,
            .claudeDataDirectoryOpenPanelMessage,
            .codexDataDirectoryOpenPanelMessage,
            .openCodeDataDirectoryOpenPanelMessage,
            .chooseDirectoryPrompt,
            .statusNeedsDataDirectorySelection,
            .errorCannotAccessProviderDirectoryFormat,
            .errorProviderDirectoryAuthorizationFailedFormat,
        ]

        let expected: [AppLanguage: [String]] = [
            .zhHans: [
                "数据文件夹",
                "选择各数据源的数据文件夹并管理数据刷新。",
                "未选择",
                "已选择",
                "需要重新选择",
                "所选文件夹中未发现数据",
                "去授权",
                "重新选择",
                "再次选择",
                "未授权",
                "已授权",
                "请选择 Claude Code 的数据文件夹；通常为 ~/.claude。\n可通过 echo \"${CLAUDE_CONFIG_DIR:-$HOME/.claude}\" 命令找到。",
                "请选择 Codex 的数据文件夹；通常为 ~/.codex。\n可通过 echo \"${CODEX_HOME:-$HOME/.codex}\" 命令找到。",
                "请选择 opencode 的数据文件夹；通常为 ~/.local/share/opencode。\n可通过 echo \"${XDG_DATA_HOME:-$HOME/.local/share}/opencode\" 命令找到。",
                "选择",
                "请在设置中选择一个或多个数据文件夹",
                "无法访问 %@ 数据文件夹，请再次选择。",
                "无法保存 %@ 数据文件夹的访问权限，请重新选择。",
            ],
            .zhHant: [
                "資料檔案夾",
                "選擇各資料來源的資料檔案夾並管理資料重新整理。",
                "未選擇",
                "已選擇",
                "需要重新選擇",
                "找不到資料",
                "前往授權",
                "重新選擇",
                "再次選擇",
                "未授權",
                "已授權",
                "請選擇 Claude Code 的資料檔案夾；通常為 ~/.claude。\n可透過 echo \"${CLAUDE_CONFIG_DIR:-$HOME/.claude}\" 指令找到。",
                "請選擇 Codex 的資料檔案夾；通常為 ~/.codex。\n可透過 echo \"${CODEX_HOME:-$HOME/.codex}\" 指令找到。",
                "請選擇 opencode 的資料檔案夾；通常為 ~/.local/share/opencode。\n可透過 echo \"${XDG_DATA_HOME:-$HOME/.local/share}/opencode\" 指令找到。",
                "選擇",
                "請在設定中選擇一個或多個資料檔案夾",
                "無法存取已選擇的 %@ 資料檔案夾，請重新選擇",
                "無法儲存 %@ 資料檔案夾的存取權限，請再試一次",
            ],
            .en: [
                "Data Folders",
                "Choose provider data folders and manage data refresh.",
                "Not selected",
                "Selected",
                "Needs reselection",
                "No data found in the selected folder",
                "Authorize",
                "Reselect",
                "Choose Again",
                "Unauthorized",
                "Authorized",
                "Choose the Claude Code data folder; it is usually ~/.claude.\nRun echo \"${CLAUDE_CONFIG_DIR:-$HOME/.claude}\" to find it.",
                "Choose the Codex data folder; it is usually ~/.codex.\nRun echo \"${CODEX_HOME:-$HOME/.codex}\" to find it.",
                "Choose the opencode data folder; it is usually ~/.local/share/opencode.\nRun echo \"${XDG_DATA_HOME:-$HOME/.local/share}/opencode\" to find it.",
                "Choose",
                "Choose one or more data folders in Settings",
                "Cannot access the %@ data folder. Please choose it again.",
                "Could not save access to the %@ data folder. Please choose again.",
            ],
            .ja: [
                "データフォルダ",
                "各データソースのデータフォルダを選択し、データ更新を管理します。",
                "未選択",
                "選択済み",
                "再選択が必要です",
                "データが見つかりません",
                "許可",
                "フォルダを変更",
                "もう一度選択",
                "未許可",
                "許可済み",
                "Claude Code のデータフォルダを選択してください。通常は ~/.claude です。\necho \"${CLAUDE_CONFIG_DIR:-$HOME/.claude}\" コマンドで場所を確認できます。",
                "Codex のデータフォルダを選択してください。通常は ~/.codex です。\necho \"${CODEX_HOME:-$HOME/.codex}\" コマンドで場所を確認できます。",
                "opencode のデータフォルダを選択してください。通常は ~/.local/share/opencode です。\necho \"${XDG_DATA_HOME:-$HOME/.local/share}/opencode\" コマンドで場所を確認できます。",
                "選択",
                "設定で1つ以上のデータフォルダを選択してください",
                "選択した %@ のデータフォルダにアクセスできません。もう一度選択してください",
                "%@ のデータフォルダへのアクセス権を保存できませんでした。もう一度お試しください",
            ],
            .ko: [
                "데이터 폴더",
                "각 데이터 소스의 데이터 폴더를 선택하고 데이터 새로 고침을 관리합니다.",
                "선택 안 함",
                "선택됨",
                "다시 선택해야 함",
                "데이터를 찾을 수 없음",
                "권한 허용",
                "폴더 변경",
                "다시 선택",
                "미허용",
                "허용됨",
                "Claude Code 데이터 폴더를 선택하세요. 보통 ~/.claude입니다.\necho \"${CLAUDE_CONFIG_DIR:-$HOME/.claude}\" 명령으로 찾을 수 있습니다.",
                "Codex 데이터 폴더를 선택하세요. 보통 ~/.codex입니다.\necho \"${CODEX_HOME:-$HOME/.codex}\" 명령으로 찾을 수 있습니다.",
                "opencode 데이터 폴더를 선택하세요. 보통 ~/.local/share/opencode입니다.\necho \"${XDG_DATA_HOME:-$HOME/.local/share}/opencode\" 명령으로 찾을 수 있습니다.",
                "선택",
                "설정에서 하나 이상의 데이터 폴더를 선택하세요",
                "선택한 %@ 데이터 폴더에 접근할 수 없습니다. 다시 선택하세요",
                "%@ 데이터 폴더 접근 권한을 저장하지 못했습니다. 다시 시도하세요",
            ],
            .es: [
                "Carpetas de datos",
                "Elige las carpetas de datos de cada fuente y gestiona la actualización de datos.",
                "Sin seleccionar",
                "Seleccionada",
                "Debe volver a seleccionarse",
                "No se encontraron datos",
                "Autorizar",
                "Cambiar carpeta",
                "Elegir de nuevo",
                "No autorizado",
                "Autorizado",
                "Elige la carpeta de datos de Claude Code; normalmente está en ~/.claude.\nEjecuta echo \"${CLAUDE_CONFIG_DIR:-$HOME/.claude}\" para encontrarla.",
                "Elige la carpeta de datos de Codex; normalmente está en ~/.codex.\nEjecuta echo \"${CODEX_HOME:-$HOME/.codex}\" para encontrarla.",
                "Elige la carpeta de datos de opencode; normalmente está en ~/.local/share/opencode.\nEjecuta echo \"${XDG_DATA_HOME:-$HOME/.local/share}/opencode\" para encontrarla.",
                "Elegir",
                "Selecciona una o varias carpetas de datos en Configuración",
                "No se puede acceder a la carpeta de datos seleccionada para %@. Vuelve a elegirla",
                "No se pudo guardar el acceso a la carpeta de datos de %@. Inténtalo de nuevo",
            ],
            .de: [
                "Datenordner",
                "Wähle die Datenordner der einzelnen Quellen aus und verwalte die Datenaktualisierung.",
                "Nicht ausgewählt",
                "Ausgewählt",
                "Erneute Auswahl erforderlich",
                "Keine Daten gefunden",
                "Autorisieren",
                "Ordner ändern",
                "Erneut auswählen",
                "Nicht autorisiert",
                "Autorisiert",
                "Wähle den Datenordner von Claude Code; normalerweise liegt er unter ~/.claude.\nFühre echo \"${CLAUDE_CONFIG_DIR:-$HOME/.claude}\" aus, um ihn zu finden.",
                "Wähle den Datenordner von Codex; normalerweise liegt er unter ~/.codex.\nFühre echo \"${CODEX_HOME:-$HOME/.codex}\" aus, um ihn zu finden.",
                "Wähle den Datenordner von opencode; normalerweise liegt er unter ~/.local/share/opencode.\nFühre echo \"${XDG_DATA_HOME:-$HOME/.local/share}/opencode\" aus, um ihn zu finden.",
                "Auswählen",
                "Wähle in den Einstellungen mindestens einen Datenordner aus",
                "Auf den ausgewählten Datenordner von %@ kann nicht zugegriffen werden. Wähle ihn erneut aus",
                "Der Zugriff auf den Datenordner von %@ konnte nicht gespeichert werden. Versuche es erneut",
            ],
            .fr: [
                "Dossiers de données",
                "Choisissez les dossiers de données de chaque source et gérez l’actualisation des données.",
                "Non sélectionné",
                "Sélectionné",
                "Nouvelle sélection requise",
                "Aucune donnée trouvée",
                "Autoriser",
                "Changer de dossier",
                "Choisir à nouveau",
                "Non autorisé",
                "Autorisé",
                "Choisissez le dossier de données de Claude Code ; il se trouve généralement dans ~/.claude.\nExécutez echo \"${CLAUDE_CONFIG_DIR:-$HOME/.claude}\" pour le trouver.",
                "Choisissez le dossier de données de Codex ; il se trouve généralement dans ~/.codex.\nExécutez echo \"${CODEX_HOME:-$HOME/.codex}\" pour le trouver.",
                "Choisissez le dossier de données d’opencode ; il se trouve généralement dans ~/.local/share/opencode.\nExécutez echo \"${XDG_DATA_HOME:-$HOME/.local/share}/opencode\" pour le trouver.",
                "Choisir",
                "Sélectionnez un ou plusieurs dossiers de données dans Paramètres",
                "Impossible d'accéder au dossier de données sélectionné pour %@. Choisissez-le à nouveau",
                "Impossible d'enregistrer l'accès au dossier de données de %@. Réessayez",
            ],
            .ptBR: [
                "Pastas de dados",
                "Escolha as pastas de dados de cada fonte e gerencie a atualização dos dados.",
                "Não selecionada",
                "Selecionada",
                "Nova seleção necessária",
                "Nenhum dado encontrado",
                "Autorizar",
                "Alterar pasta",
                "Escolher novamente",
                "Não autorizado",
                "Autorizado",
                "Escolha a pasta de dados do Claude Code; normalmente ela fica em ~/.claude.\nExecute echo \"${CLAUDE_CONFIG_DIR:-$HOME/.claude}\" para encontrá-la.",
                "Escolha a pasta de dados do Codex; normalmente ela fica em ~/.codex.\nExecute echo \"${CODEX_HOME:-$HOME/.codex}\" para encontrá-la.",
                "Escolha a pasta de dados do opencode; normalmente ela fica em ~/.local/share/opencode.\nExecute echo \"${XDG_DATA_HOME:-$HOME/.local/share}/opencode\" para encontrá-la.",
                "Escolher",
                "Selecione uma ou mais pastas de dados em Configurações",
                "Não foi possível acessar a pasta de dados selecionada para %@. Escolha-a novamente",
                "Não foi possível salvar o acesso à pasta de dados de %@. Tente novamente",
            ],
            .it: [
                "Cartelle dati",
                "Scegli le cartelle dati di ogni origine e gestisci l’aggiornamento dei dati.",
                "Non selezionata",
                "Selezionata",
                "Nuova selezione necessaria",
                "Nessun dato trovato",
                "Autorizza",
                "Cambia cartella",
                "Scegli di nuovo",
                "Non autorizzato",
                "Autorizzato",
                "Scegli la cartella dati di Claude Code; di solito si trova in ~/.claude.\nEsegui echo \"${CLAUDE_CONFIG_DIR:-$HOME/.claude}\" per trovarla.",
                "Scegli la cartella dati di Codex; di solito si trova in ~/.codex.\nEsegui echo \"${CODEX_HOME:-$HOME/.codex}\" per trovarla.",
                "Scegli la cartella dati di opencode; di solito si trova in ~/.local/share/opencode.\nEsegui echo \"${XDG_DATA_HOME:-$HOME/.local/share}/opencode\" per trovarla.",
                "Scegli",
                "Seleziona una o più cartelle dati in Impostazioni",
                "Impossibile accedere alla cartella dati selezionata per %@. Selezionala di nuovo",
                "Impossibile salvare l'accesso alla cartella dati di %@. Riprova",
            ],
            .nl: [
                "Gegevensmappen",
                "Kies de gegevensmappen per bron en beheer het vernieuwen van gegevens.",
                "Niet geselecteerd",
                "Geselecteerd",
                "Opnieuw selecteren vereist",
                "Geen gegevens gevonden",
                "Autoriseren",
                "Map wijzigen",
                "Opnieuw kiezen",
                "Niet geautoriseerd",
                "Geautoriseerd",
                "Kies de gegevensmap van Claude Code; deze staat meestal in ~/.claude.\nVoer echo \"${CLAUDE_CONFIG_DIR:-$HOME/.claude}\" uit om deze te vinden.",
                "Kies de gegevensmap van Codex; deze staat meestal in ~/.codex.\nVoer echo \"${CODEX_HOME:-$HOME/.codex}\" uit om deze te vinden.",
                "Kies de gegevensmap van opencode; deze staat meestal in ~/.local/share/opencode.\nVoer echo \"${XDG_DATA_HOME:-$HOME/.local/share}/opencode\" uit om deze te vinden.",
                "Kiezen",
                "Selecteer een of meer gegevensmappen in Instellingen",
                "De geselecteerde gegevensmap voor %@ is niet toegankelijk. Kies deze opnieuw",
                "Toegang tot de gegevensmap van %@ kon niet worden opgeslagen. Probeer het opnieuw",
            ],
            .pl: [
                "Foldery danych",
                "Wybierz foldery danych dla poszczególnych źródeł i zarządzaj odświeżaniem danych.",
                "Nie wybrano",
                "Wybrano",
                "Wymaga ponownego wyboru",
                "Nie znaleziono danych",
                "Autoryzuj",
                "Zmień folder",
                "Wybierz ponownie",
                "Nieautoryzowane",
                "Autoryzowano",
                "Wybierz folder danych Claude Code; zwykle znajduje się w ~/.claude.\nUruchom echo \"${CLAUDE_CONFIG_DIR:-$HOME/.claude}\", aby go znaleźć.",
                "Wybierz folder danych Codex; zwykle znajduje się w ~/.codex.\nUruchom echo \"${CODEX_HOME:-$HOME/.codex}\", aby go znaleźć.",
                "Wybierz folder danych opencode; zwykle znajduje się w ~/.local/share/opencode.\nUruchom echo \"${XDG_DATA_HOME:-$HOME/.local/share}/opencode\", aby go znaleźć.",
                "Wybierz",
                "Wybierz co najmniej jeden folder danych w Ustawieniach",
                "Nie można uzyskać dostępu do folderu danych wybranego dla %@. Wybierz go ponownie",
                "Nie udało się zapisać dostępu do folderu danych dla %@. Spróbuj ponownie",
            ],
        ]

        #expect(keys.allSatisfy { AppStringKey.allCases.contains($0) })
        #expect(expected.count == 12)
        for (language, expectedValues) in expected {
            #expect(
                keys.map { AppStrings.text($0, language: language) }
                    == expectedValues
            )
        }

        let formatKeys: [AppStringKey] = [
            .errorCannotAccessProviderDirectoryFormat,
            .errorProviderDirectoryAuthorizationFailedFormat,
        ]
        for language in AppLanguage.allCases {
            for key in formatKeys {
                let format = AppStrings.text(key, language: language)
                #expect(
                    format.components(separatedBy: "%@").count == 2,
                    "\(key) must contain exactly one provider token in \(language)"
                )
                for providerName in ["Claude Code", "Codex", "opencode"] {
                    #expect(String(format: format, providerName).contains(providerName))
                }
            }
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
