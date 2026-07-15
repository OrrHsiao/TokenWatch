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
    .init(localeIdentifier: "it-IT", key: .mainMenuZoom, reason: "Zoom 是意大利语 macOS 界面沿用的通用术语。"),

    .init(localeIdentifier: "nl-NL", key: .dashboardMetricRecords, reason: "Records 是荷兰语数据界面采用的英文指标名。"),
    .init(localeIdentifier: "nl-NL", key: .dashboardTrendTitle, reason: "Trend 在荷兰语中使用相同拼写。"),
    .init(localeIdentifier: "nl-NL", key: .dashboardCache, reason: "Cache 是荷兰语技术界面沿用的术语。"),
    .init(localeIdentifier: "nl-NL", key: .recentDetailsTool, reason: "Tool 在荷兰语开发工具语境中使用相同拼写。"),
    .init(localeIdentifier: "nl-NL", key: .recentDetailsProject, reason: "Project 在荷兰语中使用相同拼写。"),
    .init(localeIdentifier: "nl-NL", key: .recentDetailsModel, reason: "Model 在荷兰语中使用相同拼写。"),
    .init(localeIdentifier: "nl-NL", key: .recentDetailsRecords, reason: "Records 是荷兰语数据界面采用的英文列名。"),
    .init(localeIdentifier: "nl-NL", key: .mainMenuZoom, reason: "Zoom 是荷兰语 macOS 界面沿用的通用术语。"),
    .init(localeIdentifier: "nl-NL", key: .popoverWeek, reason: "Week 在荷兰语中使用相同拼写。"),

    .init(localeIdentifier: "pl-PL", key: .languageSystem, reason: "System 在波兰语中使用相同拼写。"),
    .init(localeIdentifier: "pl-PL", key: .dashboardTrendTitle, reason: "Trend 是波兰语数据界面沿用的术语。"),
    .init(localeIdentifier: "pl-PL", key: .recentDetailsModel, reason: "Model 在波兰语中使用相同拼写。"),
]
