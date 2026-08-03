@testable import TokenWatch

struct LocalizationEnglishReuseAllowance: Hashable {
    let localeIdentifier: String
    let key: AppStringKey
    let reason: String
}

let localizationEnglishReuseAllowlist: [LocalizationEnglishReuseAllowance] = [
    .init(localeIdentifier: "zh-CN", key: .languageEnglish, reason: "英语的语言自称按产品约定显示为 English。"),
    .init(localeIdentifier: "zh-TW", key: .languageEnglish, reason: "英語的語言自稱按產品約定顯示為 English。"),

    .init(localeIdentifier: "es-ES", key: .sidebarTotal, reason: "Total 是西班牙语中拼写相同的常用汇总标签。"),
    .init(localeIdentifier: "es-ES", key: .mainMenuZoom, reason: "Zoom 是西班牙语 macOS 界面沿用的通用术语。"),

    .init(localeIdentifier: "de-DE", key: .languageSystem, reason: "System 在德语中使用相同拼写。"),
    .init(localeIdentifier: "de-DE", key: .dashboardTrendTitle, reason: "Trend 在德语数据界面中使用相同拼写。"),
    .init(localeIdentifier: "de-DE", key: .dashboardCache, reason: "Cache 是德语技术界面沿用的术语。"),
    .init(localeIdentifier: "de-DE", key: .dashboardWidgetsSubtitle, reason: "保留 TokenWatch 产品名后与英文存在词组重叠。"),
    .init(localeIdentifier: "de-DE", key: .dashboardReasoning, reason: "Reasoning 是模型能力名称，德语界面保留英文。"),
    .init(localeIdentifier: "de-DE", key: .recentDetailsTool, reason: "Tool 是开发工具语境中保留的英文列名。"),

    .init(localeIdentifier: "fr-FR", key: .sidebarTotal, reason: "Total 是法语中拼写相同的汇总标签。"),
    .init(localeIdentifier: "fr-FR", key: .dashboardSessionsNavigation, reason: "Sessions 是法语中拼写相同的复数名词。"),
    .init(localeIdentifier: "fr-FR", key: .dashboardSessionsTitle, reason: "Sessions 是法语中拼写相同的页面标题。"),
    .init(localeIdentifier: "fr-FR", key: .dashboardMetricSessions, reason: "Sessions 是法语中拼写相同的指标名。"),
    .init(localeIdentifier: "fr-FR", key: .dashboardCache, reason: "Cache 是法语技术界面沿用的术语。"),
    .init(localeIdentifier: "fr-FR", key: .autoRefreshMinute1, reason: "minute 是法语中拼写相同的单数时间单位。"),
    .init(localeIdentifier: "fr-FR", key: .autoRefreshMinutes5, reason: "minutes 是法语中拼写相同的复数时间单位。"),
    .init(localeIdentifier: "fr-FR", key: .autoRefreshMinutes15, reason: "minutes 是法语中拼写相同的复数时间单位。"),
    .init(localeIdentifier: "fr-FR", key: .recentDetailsSession, reason: "Session 是法语中拼写相同的列名。"),
    .init(localeIdentifier: "fr-FR", key: .mainMenuZoom, reason: "Zoom 是法语 macOS 界面沿用的通用术语。"),

    .init(localeIdentifier: "pt-BR", key: .sidebarTotal, reason: "Total 是巴西葡萄牙语中拼写相同的汇总标签。"),
    .init(localeIdentifier: "pt-BR", key: .dashboardCache, reason: "Cache 是巴西葡萄牙语技术界面沿用的术语。"),
    .init(localeIdentifier: "pt-BR", key: .mainMenuZoom, reason: "Zoom 是巴西葡萄牙语界面沿用的通用术语。"),

    .init(localeIdentifier: "it-IT", key: .dashboardInput, reason: "Input 是模型用量语境中保留的英文指标名。"),
    .init(localeIdentifier: "it-IT", key: .dashboardOutput, reason: "Output 是模型用量语境中保留的英文指标名。"),
    .init(localeIdentifier: "it-IT", key: .dashboardCache, reason: "Cache 是意大利语技术界面沿用的术语。"),
    .init(localeIdentifier: "it-IT", key: .dashboardWidgetsSubtitle, reason: "保留 TokenWatch 产品名后与英文存在词组重叠。"),
    .init(localeIdentifier: "it-IT", key: .mainMenuZoom, reason: "Zoom 是意大利语 macOS 界面沿用的通用术语。"),

    .init(localeIdentifier: "nl-NL", key: .dashboardMetricRecords, reason: "Records 是荷兰语数据界面采用的英文指标名。"),
    .init(localeIdentifier: "nl-NL", key: .dashboardTrendTitle, reason: "Trend 在荷兰语中使用相同拼写。"),
    .init(localeIdentifier: "nl-NL", key: .dashboardCache, reason: "Cache 是荷兰语技术界面沿用的术语。"),
    .init(localeIdentifier: "nl-NL", key: .dashboardWidgetsSubtitle, reason: "保留 TokenWatch 产品名后与英文存在词组重叠。"),
    .init(localeIdentifier: "nl-NL", key: .recentDetailsTool, reason: "Tool 在荷兰语开发工具语境中使用相同拼写。"),
    .init(localeIdentifier: "nl-NL", key: .recentDetailsProject, reason: "Project 在荷兰语中使用相同拼写。"),
    .init(localeIdentifier: "nl-NL", key: .recentDetailsModel, reason: "Model 在荷兰语中使用相同拼写。"),
    .init(localeIdentifier: "nl-NL", key: .recentDetailsRecords, reason: "Records 是荷兰语数据界面采用的英文列名。"),
    .init(localeIdentifier: "nl-NL", key: .mainMenuZoom, reason: "Zoom 是荷兰语 macOS 界面沿用的通用术语。"),
    .init(localeIdentifier: "nl-NL", key: .popoverWeek, reason: "Week 在荷兰语中使用相同拼写。"),

    .init(localeIdentifier: "pl-PL", key: .languageSystem, reason: "System 在波兰语中使用相同拼写。"),
    .init(localeIdentifier: "pl-PL", key: .dashboardTrendTitle, reason: "Trend 是波兰语数据界面沿用的术语。"),
    .init(localeIdentifier: "pl-PL", key: .recentDetailsModel, reason: "Model 在波兰语中使用相同拼写。"),

    .init(localeIdentifier: "ca-ES", key: .sidebarTotal, reason: "Total 是加泰罗尼亚语中拼写相同的常用汇总标签。"),
    .init(localeIdentifier: "ca-ES", key: .dashboardSessionsNavigation, reason: "Sessions 是加泰罗尼亚语中拼写相同的复数名词。"),
    .init(localeIdentifier: "ca-ES", key: .dashboardSessionsTitle, reason: "Sessions 是加泰罗尼亚语中拼写相同的页面标题。"),
    .init(localeIdentifier: "ca-ES", key: .dashboardMetricSessions, reason: "Sessions 是加泰罗尼亚语中拼写相同的指标名。"),
    .init(localeIdentifier: "ca-ES", key: .chartCost, reason: "Cost 是加泰罗尼亚语中拼写相同的费用指标。"),
    .init(localeIdentifier: "ca-ES", key: .recentDetailsModel, reason: "Model 是加泰罗尼亚语中拼写相同的列名。"),
    .init(localeIdentifier: "ca-ES", key: .recentDetailsCost, reason: "Cost 是加泰罗尼亚语中拼写相同的列名。"),
    .init(localeIdentifier: "ca-ES", key: .mainMenuZoom, reason: "Zoom 是加泰罗尼亚语 macOS 界面沿用的通用术语。"),

    .init(localeIdentifier: "da-DK", key: .languageSystem, reason: "System 在丹麦语中使用相同拼写。"),
    .init(localeIdentifier: "da-DK", key: .dashboardCache, reason: "Cache 是丹麦语技术界面沿用的术语。"),
    .init(localeIdentifier: "da-DK", key: .recentDetailsSession, reason: "Session 是丹麦语技术界面采用的常用列名。"),
    .init(localeIdentifier: "da-DK", key: .recentDetailsModel, reason: "Model 在丹麦语中使用相同拼写。"),
    .init(localeIdentifier: "da-DK", key: .mainMenuZoom, reason: "Zoom 是丹麦语 macOS 界面沿用的通用术语。"),

    .init(localeIdentifier: "es-419", key: .sidebarTotal, reason: "Total 是拉丁美洲西班牙语中拼写相同的常用汇总标签。"),
    .init(localeIdentifier: "es-419", key: .mainMenuZoom, reason: "Zoom 是拉丁美洲西班牙语 macOS 界面沿用的通用术语。"),

    .init(localeIdentifier: "fr-CA", key: .sidebarTotal, reason: "Total 是加拿大法语中拼写相同的汇总标签。"),
    .init(localeIdentifier: "fr-CA", key: .dashboardSessionsNavigation, reason: "Sessions 是加拿大法语中拼写相同的复数名词。"),
    .init(localeIdentifier: "fr-CA", key: .dashboardSessionsTitle, reason: "Sessions 是加拿大法语中拼写相同的页面标题。"),
    .init(localeIdentifier: "fr-CA", key: .dashboardMetricSessions, reason: "Sessions 是加拿大法语中拼写相同的指标名。"),
    .init(localeIdentifier: "fr-CA", key: .autoRefreshMinute1, reason: "minute 是加拿大法语中拼写相同的单数时间单位。"),
    .init(localeIdentifier: "fr-CA", key: .autoRefreshMinutes5, reason: "minutes 是加拿大法语中拼写相同的复数时间单位。"),
    .init(localeIdentifier: "fr-CA", key: .autoRefreshMinutes15, reason: "minutes 是加拿大法语中拼写相同的复数时间单位。"),
    .init(localeIdentifier: "fr-CA", key: .recentDetailsSession, reason: "Session 是加拿大法语中拼写相同的列名。"),
    .init(localeIdentifier: "fr-CA", key: .mainMenuZoom, reason: "Zoom 是加拿大法语 macOS 界面沿用的通用术语。"),

    .init(localeIdentifier: "nb-NO", key: .languageSystem, reason: "System 在书面挪威语中使用相同拼写。"),
    .init(localeIdentifier: "nb-NO", key: .mainMenuZoom, reason: "Zoom 是书面挪威语 macOS 界面沿用的通用术语。"),

    .init(localeIdentifier: "pt-PT", key: .sidebarTotal, reason: "Total 是欧洲葡萄牙语中拼写相同的常用汇总标签。"),
    .init(localeIdentifier: "pt-PT", key: .dashboardCache, reason: "Cache 是欧洲葡萄牙语技术界面沿用的术语。"),
    .init(localeIdentifier: "pt-PT", key: .mainMenuZoom, reason: "Zoom 是欧洲葡萄牙语 macOS 界面沿用的通用术语。"),

    .init(localeIdentifier: "ro-RO", key: .sidebarTotal, reason: "Total 是罗马尼亚语中拼写相同的常用汇总标签。"),
    .init(localeIdentifier: "ro-RO", key: .chartCost, reason: "Cost 是罗马尼亚语中拼写相同的费用指标。"),
    .init(localeIdentifier: "ro-RO", key: .recentDetailsModel, reason: "Model 是罗马尼亚语中拼写相同的列名。"),
    .init(localeIdentifier: "ro-RO", key: .recentDetailsCost, reason: "Cost 是罗马尼亚语中拼写相同的列名。"),
    .init(localeIdentifier: "ro-RO", key: .mainMenuZoom, reason: "Zoom 是罗马尼亚语 macOS 界面沿用的通用术语。"),

    .init(localeIdentifier: "sv-SE", key: .languageSystem, reason: "System 在瑞典语中使用相同拼写。"),
    .init(localeIdentifier: "sv-SE", key: .dashboardTrendTitle, reason: "Trend 在瑞典语数据界面中使用相同拼写。"),
    .init(localeIdentifier: "sv-SE", key: .dashboardCache, reason: "Cache 是瑞典语技术界面沿用的术语。"),
    .init(localeIdentifier: "sv-SE", key: .recentDetailsSession, reason: "Session 是瑞典语技术界面采用的常用列名。"),
    .init(localeIdentifier: "sv-SE", key: .periodAxisValueName, reason: "Period 在瑞典语中使用相同拼写。"),

    .init(localeIdentifier: "bs-BA", key: .dashboardTrendTitle, reason: "Trend 是波斯尼亚语数据界面中拼写相同的自然标题。"),
    .init(localeIdentifier: "bs-BA", key: .recentDetailsModel, reason: "Model 是波斯尼亚语中拼写相同的自然列名。"),
    .init(localeIdentifier: "bs-BA", key: .periodAxisValueName, reason: "Period 是波斯尼亚语中拼写相同的时间轴名称。"),

    .init(localeIdentifier: "cs-CZ", key: .dashboardTrendTitle, reason: "Trend 是捷克语数据界面中拼写相同的自然标题。"),
    .init(localeIdentifier: "cs-CZ", key: .recentDetailsModel, reason: "Model 是捷克语中拼写相同的自然列名。"),

    .init(localeIdentifier: "hr-HR", key: .dashboardTrendTitle, reason: "Trend 是克罗地亚语数据界面中拼写相同的自然标题。"),
    .init(localeIdentifier: "hr-HR", key: .recentDetailsModel, reason: "Model 是克罗地亚语中拼写相同的自然列名。"),

    .init(localeIdentifier: "sk-SK", key: .dashboardTrendTitle, reason: "Trend 是斯洛伐克语数据界面中拼写相同的自然标题。"),
    .init(localeIdentifier: "sk-SK", key: .recentDetailsModel, reason: "Model 是斯洛伐克语中拼写相同的自然列名。"),

    .init(localeIdentifier: "tr-TR", key: .recentDetailsModel, reason: "Model 是土耳其语中拼写相同的自然列名。"),

    .init(localeIdentifier: "id-ID", key: .recentDetailsModel, reason: "Model 是印尼语技术界面中拼写相同且通行的模型列名。"),

    .init(localeIdentifier: "ms-MY", key: .dashboardInput, reason: "Input 是马来语模型用量界面中通行的输入指标名。"),
    .init(localeIdentifier: "ms-MY", key: .dashboardOutput, reason: "Output 是马来语模型用量界面中通行的输出指标名。"),
    .init(localeIdentifier: "ms-MY", key: .dashboardCache, reason: "Cache 是马来语技术界面中通行的缓存指标名。"),
    .init(localeIdentifier: "ms-MY", key: .recentDetailsModel, reason: "Model 是马来语技术界面中拼写相同且通行的模型列名。"),

    .init(localeIdentifier: "tl", key: .recentDetailsTool, reason: "Tool 是菲律宾语开发工具界面中通行且拼写相同的工具列名。"),

    // 已迁移语言的目录说明保留命令、环境变量与固定文件名，因而与英文存在技术短语重叠。
    .init(localeIdentifier: "zh-CN", key: .claudeDataDirectoryOpenPanelMessage, reason: "目录说明保留固定命令、环境变量和文件名。"),
    .init(localeIdentifier: "zh-CN", key: .codexDataDirectoryOpenPanelMessage, reason: "目录说明保留固定命令、环境变量和文件名。"),
    .init(localeIdentifier: "zh-CN", key: .openCodeDataDirectoryOpenPanelMessage, reason: "目录说明保留固定命令、环境变量和文件名。"),
    .init(localeIdentifier: "zh-TW", key: .claudeDataDirectoryOpenPanelMessage, reason: "目錄說明保留固定命令、環境變數和檔名。"),
    .init(localeIdentifier: "zh-TW", key: .codexDataDirectoryOpenPanelMessage, reason: "目錄說明保留固定命令、環境變數和檔名。"),
    .init(localeIdentifier: "zh-TW", key: .openCodeDataDirectoryOpenPanelMessage, reason: "目錄說明保留固定命令、環境變數和檔名。"),
    .init(localeIdentifier: "ja-JP", key: .claudeDataDirectoryOpenPanelMessage, reason: "ディレクトリ説明で固定コマンド、環境変数、ファイル名を保持するため。"),
    .init(localeIdentifier: "ja-JP", key: .codexDataDirectoryOpenPanelMessage, reason: "ディレクトリ説明で固定コマンド、環境変数、ファイル名を保持するため。"),
    .init(localeIdentifier: "ja-JP", key: .openCodeDataDirectoryOpenPanelMessage, reason: "ディレクトリ説明で固定コマンド、環境変数、ファイル名を保持するため。"),
    .init(localeIdentifier: "ko-KR", key: .claudeDataDirectoryOpenPanelMessage, reason: "디렉터리 설명에 고정 명령, 환경 변수 및 파일 이름이 포함됩니다。"),
    .init(localeIdentifier: "ko-KR", key: .codexDataDirectoryOpenPanelMessage, reason: "디렉터리 설명에 고정 명령, 환경 변수 및 파일 이름이 포함됩니다。"),
    .init(localeIdentifier: "ko-KR", key: .openCodeDataDirectoryOpenPanelMessage, reason: "디렉터리 설명에 고정 명령, 환경 변수 및 파일 이름이 포함됩니다。"),
    .init(localeIdentifier: "es-ES", key: .claudeDataDirectoryOpenPanelMessage, reason: "La explicación conserva comandos, variables de entorno y nombres de archivo fijos。"),
    .init(localeIdentifier: "es-ES", key: .codexDataDirectoryOpenPanelMessage, reason: "La explicación conserva comandos, variables de entorno y nombres de archivo fijos。"),
    .init(localeIdentifier: "es-ES", key: .openCodeDataDirectoryOpenPanelMessage, reason: "La explicación conserva comandos, variables de entorno y nombres de archivo fijos。"),
    .init(localeIdentifier: "de-DE", key: .claudeDataDirectoryOpenPanelMessage, reason: "Die Ordnerbeschreibung enthält feste Befehle, Umgebungsvariablen und Dateinamen。"),
    .init(localeIdentifier: "de-DE", key: .codexDataDirectoryOpenPanelMessage, reason: "Die Ordnerbeschreibung enthält feste Befehle, Umgebungsvariablen und Dateinamen。"),
    .init(localeIdentifier: "de-DE", key: .openCodeDataDirectoryOpenPanelMessage, reason: "Die Ordnerbeschreibung enthält feste Befehle, Umgebungsvariablen und Dateinamen。"),
    .init(localeIdentifier: "de-DE", key: .support, reason: "Support 是德语中通用的支持入口术语。"),
    .init(localeIdentifier: "de-DE", key: .widgetHeatmapTitle, reason: "Heatmap 是德语数据可视化界面沿用的通用术语。"),
    .init(localeIdentifier: "fr-FR", key: .claudeDataDirectoryOpenPanelMessage, reason: "La description conserve les commandes, variables d’environnement et noms de fichiers fixes。"),
    .init(localeIdentifier: "fr-FR", key: .codexDataDirectoryOpenPanelMessage, reason: "La description conserve les commandes, variables d’environnement et noms de fichiers fixes。"),
    .init(localeIdentifier: "fr-FR", key: .openCodeDataDirectoryOpenPanelMessage, reason: "La description conserve les commandes, variables d’environnement et noms de fichiers fixes。"),
    .init(localeIdentifier: "pt-BR", key: .claudeDataDirectoryOpenPanelMessage, reason: "A descrição mantém comandos, variáveis de ambiente e nomes de arquivo fixos。"),
    .init(localeIdentifier: "pt-BR", key: .codexDataDirectoryOpenPanelMessage, reason: "A descrição mantém comandos, variáveis de ambiente e nomes de arquivo fixos。"),
    .init(localeIdentifier: "pt-BR", key: .openCodeDataDirectoryOpenPanelMessage, reason: "A descrição mantém comandos, variáveis de ambiente e nomes de arquivo fixos。"),
    .init(localeIdentifier: "it-IT", key: .claudeDataDirectoryOpenPanelMessage, reason: "La descrizione conserva comandi, variabili d’ambiente e nomi file fissi。"),
    .init(localeIdentifier: "it-IT", key: .codexDataDirectoryOpenPanelMessage, reason: "La descrizione conserva comandi, variabili d’ambiente e nomi file fissi。"),
    .init(localeIdentifier: "it-IT", key: .openCodeDataDirectoryOpenPanelMessage, reason: "La descrizione conserva comandi, variabili d’ambiente e nomi file fissi。"),
    .init(localeIdentifier: "nl-NL", key: .claudeDataDirectoryOpenPanelMessage, reason: "De mapbeschrijving behoudt vaste opdrachten, omgevingsvariabelen en bestandsnamen。"),
    .init(localeIdentifier: "nl-NL", key: .codexDataDirectoryOpenPanelMessage, reason: "De mapbeschrijving behoudt vaste opdrachten, omgevingsvariabelen en bestandsnamen。"),
    .init(localeIdentifier: "nl-NL", key: .openCodeDataDirectoryOpenPanelMessage, reason: "De mapbeschrijving behoudt vaste opdrachten, omgevingsvariabelen en bestandsnamen。"),
    .init(localeIdentifier: "nl-NL", key: .initialDirectoryAuthorizationGuideLater, reason: "Later 是荷兰语界面中可接受的稍后按钮文案。"),
    .init(localeIdentifier: "nl-NL", key: .widgetNotReadyMessage, reason: "Open TokenWatch 是荷兰语中自然的产品启动指令。"),
    .init(localeIdentifier: "pl-PL", key: .claudeDataDirectoryOpenPanelMessage, reason: "Opis folderu zachowuje stałe polecenia, zmienne środowiskowe i nazwy plików。"),
    .init(localeIdentifier: "pl-PL", key: .codexDataDirectoryOpenPanelMessage, reason: "Opis folderu zachowuje stałe polecenia, zmienne środowiskowe i nazwy plików。"),
    .init(localeIdentifier: "pl-PL", key: .openCodeDataDirectoryOpenPanelMessage, reason: "Opis folderu zachowuje stałe polecenia, zmienne środowiskowe i nazwy plików。"),
]
