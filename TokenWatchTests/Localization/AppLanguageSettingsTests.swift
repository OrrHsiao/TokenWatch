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

    @Test("语言偏好包含三阶段新增语言")
    func languagePreferencesIncludePlannedLanguages() {
        #expect(AppLanguagePreference.allCases == [
            .system,
            .zhHans,
            .zhHant,
            .en,
            .ja,
            .ko,
            .es,
            .de,
            .fr,
            .ptBR,
            .it,
            .nl,
            .pl,
        ])
    }

    @Test("选择英文会持久化并通知观察者")
    func selectingEnglishPersistsAndNotifies() throws {
        withTemporaryDefaults { defaults in
            let settings = AppLanguageSettings(defaults: defaults, preferredLanguagesProvider: { ["zh-Hans-US"] })
            var notificationCount = 0
            let token = settings.observe { notificationCount += 1 }

            settings.selectedPreference = .en

            #expect(defaults.string(forKey: AppLanguageSettings.storageKey) == "en")
            #expect(settings.resolvedLanguage == .en)
            #expect(notificationCount == 1)

            settings.removeObserver(token)
            settings.selectedPreference = .zhHans
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
        #expect(AppLanguagePreference.zhHant.title(language: .zhHans) == "繁體中文")
        #expect(AppLanguagePreference.ptBR.title(language: .en) == "Português (Brasil)")
    }

    @Test("Support 文案显式覆盖全部支持语言")
    func supportStringCoversEverySupportedLanguage() {
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

        #expect(expected.count == AppLanguage.allCases.count)
        for (language, text) in expected {
            #expect(AppStrings.text(.support, language: language) == text)
        }
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

    @Test
    func directoryAuthorizationStringsCoverEverySupportedLanguage() {
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
                "请选择 Claude Code 的数据文件夹，名称通常为“.claude”。",
                "请选择 Codex 的数据文件夹，名称通常为“.codex”。",
                "请选择 opencode 的数据文件夹，名称通常为“opencode”，其中包含“opencode.db”。",
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
                "請選擇 Claude Code 的資料檔案夾，名稱通常為「.claude」。",
                "請選擇 Codex 的資料檔案夾，名稱通常為「.codex」。",
                "請選擇 opencode 的資料檔案夾，名稱通常為「opencode」，其中包含「opencode.db」。",
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
                "Choose the Claude Code data folder. It is usually named \".claude\".",
                "Choose the Codex data folder. It is usually named \".codex\".",
                "Choose the opencode data folder. It is usually named \"opencode\" and contains \"opencode.db\".",
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
                "Claude Code のデータフォルダを選択してください。通常の名前は「.claude」です。",
                "Codex のデータフォルダを選択してください。通常の名前は「.codex」です。",
                "opencode のデータフォルダを選択してください。通常の名前は「opencode」で、「opencode.db」を含みます。",
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
                "Claude Code 데이터 폴더를 선택하세요. 일반적인 이름은 “.claude”입니다.",
                "Codex 데이터 폴더를 선택하세요. 일반적인 이름은 “.codex”입니다.",
                "opencode 데이터 폴더를 선택하세요. 일반적인 이름은 “opencode”이며 “opencode.db”를 포함합니다.",
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
                "Elige la carpeta de datos de Claude Code. Suele llamarse \".claude\".",
                "Elige la carpeta de datos de Codex. Suele llamarse \".codex\".",
                "Elige la carpeta de datos de opencode. Suele llamarse \"opencode\" y contiene \"opencode.db\".",
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
                "Wähle den Datenordner von Claude Code. Er heißt normalerweise „.claude“.",
                "Wähle den Datenordner von Codex. Er heißt normalerweise „.codex“.",
                "Wähle den Datenordner von opencode. Er heißt normalerweise „opencode“ und enthält „opencode.db“.",
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
                "Choisissez le dossier de données de Claude Code. Il s’appelle généralement « .claude ».",
                "Choisissez le dossier de données de Codex. Il s’appelle généralement « .codex ».",
                "Choisissez le dossier de données d’opencode. Il s’appelle généralement « opencode » et contient « opencode.db ».",
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
                "Escolha a pasta de dados do Claude Code. Ela normalmente se chama \".claude\".",
                "Escolha a pasta de dados do Codex. Ela normalmente se chama \".codex\".",
                "Escolha a pasta de dados do opencode. Ela normalmente se chama \"opencode\" e contém \"opencode.db\".",
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
                "Scegli la cartella dati di Claude Code. Di solito si chiama \".claude\".",
                "Scegli la cartella dati di Codex. Di solito si chiama \".codex\".",
                "Scegli la cartella dati di opencode. Di solito si chiama \"opencode\" e contiene \"opencode.db\".",
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
                "Kies de gegevensmap van Claude Code. Deze heet meestal \".claude\".",
                "Kies de gegevensmap van Codex. Deze heet meestal \".codex\".",
                "Kies de gegevensmap van opencode. Deze heet meestal \"opencode\" en bevat \"opencode.db\".",
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
                "Wybierz folder danych Claude Code. Zwykle nazywa się \".claude\".",
                "Wybierz folder danych Codex. Zwykle nazywa się \".codex\".",
                "Wybierz folder danych opencode. Zwykle nazywa się \"opencode\" i zawiera \"opencode.db\".",
                "Wybierz",
                "Wybierz co najmniej jeden folder danych w Ustawieniach",
                "Nie można uzyskać dostępu do folderu danych wybranego dla %@. Wybierz go ponownie",
                "Nie udało się zapisać dostępu do folderu danych dla %@. Spróbuj ponownie",
            ],
        ]

        #expect(keys.allSatisfy { AppStringKey.allCases.contains($0) })
        #expect(expected.count == AppLanguage.allCases.count)
        for language in AppLanguage.allCases {
            #expect(expected[language] != nil)
            if let expectedValues = expected[language] {
                #expect(
                    keys.map { AppStrings.text($0, language: language) }
                        == expectedValues
                )
            }
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

    @Test("缺失中英文文案时回落到 key 名称")
    func missingStringsFallBackToKeyName() {
        #expect(
            AppStrings.text(.settingsTitle, language: .zhHans, zhHans: [:], en: [:]) == "settingsTitle"
        )
    }
}

private func withTemporaryDefaults(_ body: (UserDefaults) throws -> Void) rethrows {
    let suiteName = "AppLanguageSettingsTests.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suiteName)!
    defer { defaults.removePersistentDomain(forName: suiteName) }
    try body(defaults)
}
