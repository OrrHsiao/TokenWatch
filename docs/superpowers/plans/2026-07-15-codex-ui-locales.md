# 对齐 Codex UI 65 个 locale 实施计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 为 TokenWatch 增加与本机 Codex 26.707.72221 一致的 65 个 UI locale；每个 locale 直接提供全部 140 条完整译文，同时保留即时切换、现有 LTR 布局和现有数字/日期/金额格式。

**Architecture:** 以 AppLanguage 作为唯一具体 locale 目录，AppLanguagePreference 只表达“跟随系统”或一个 AppLanguage。AppStrings 保持现有调用接口，但改为从指定 locale 的 .lproj 子 Bundle 查找，显式按目标 locale → en-US → raw key 回退。先迁移现有 12 份资源并建立静态质量闸门，再分五批加入 53 份完整译文，最后一次性激活 65-locale 清单、系统解析和 Xcode localization 元数据。

**Tech Stack:** Swift 6、Foundation/AppKit、UTF-8 Localizable.strings、Swift Testing、XCTest UI Testing、Xcode 26 / xcodebuild

## Global Constraints

- 以 docs/superpowers/specs/2026-07-15-codex-ui-locales-design.md 为唯一产品规格；冻结清单为 65 个具体 locale，另有“跟随系统”。
- 最终每个 locale 必须直接定义全部 140 个 AppStringKey；资源完整性验收不得通过 AppStrings 的英文回退。
- 保持 AppStrings.text(_:language:) 现有二参调用接口，不引入第三方本地化库、不迁移到 .xcstrings。
- 保留 TokenWatch.languagePreference 存储 key，并兼容 12 个旧值；新写入值必须是 system 或精确 BCP-47 locale code。
- 所有 locale 继续使用当前从左到右布局；不增加 RTL 镜像、复数规则、语言搜索、控件尺寸调整或格式化迁移。
- AI Token Watch、Claude Code、Codex、opencode、Token、SQLite、provider/model/session ID 和数据库文件名保持原文。
- 三个标题拼接 key 改为完整格式字符串，允许位置参数调整语序；所有格式参数的数量与类型必须和 en-US 一致。
- 工程采用 PBXFileSystemSynchronizedRootGroup；资源目录会自动进入 app target。不要为 65 份文件新增 PBXBuildFile、PBXFileReference、PBXVariantGroup 或 Resources phase 条目。
- 所有构建与测试使用 -derivedDataPath .build/DerivedData。app-hosted test 遇到 testmanagerd 沙盒限制时，按项目规则申请提升权限，不能用 build-for-testing 冒充真实测试通过。
- 每个翻译批次提交前必须同时通过语法、重复 key、140-key 集合、占位符、英文残留和术语人工复核。

---

### Task 1: 规范现有 12 个 locale、偏好模型和语言族展示规则

**Files:**
- Modify: TokenWatch/Localization/AppLanguage.swift:3-224
- Modify: TokenWatch/Models/LocalHourBucketDescriptor.swift:44-55
- Modify: TokenWatch/ViewControllers/MonthlyTokenChartBuilder.swift:31-37
- Modify: TokenWatch/ViewControllers/MonthlyBarChartStyle.swift:21-42
- Modify: TokenWatch/ViewControllers/CalendarHeatmapBuilder.swift:236-245
- Modify: TokenWatch/ViewControllers/DashboardViewController.swift:1888-1894
- Modify: TokenWatch/ViewController.swift:456-460,556-564
- Modify: TokenWatchTests/Localization/AppLanguageSettingsTests.swift
- Modify: TokenWatchTests/AppMainMenuBuilderTests.swift
- Modify: TokenWatchTests/TokenWatchTests.swift
- Modify: TokenWatchTests/ViewControllers/CalendarHeatmapCollectionViewItemTests.swift
- Modify: TokenWatchTests/ViewControllers/StatusBarControllerTests.swift
- Modify: TokenWatchTests/ViewControllers/StatusPopoverViewControllerTests.swift

**Interfaces:**
- Consumes: 当前 AppLanguage case 名、TokenWatch.languagePreference、Locale.preferredLanguages、现有同步 observer。
- Produces: 精确 raw locale、resourceIdentifier、nativeDisplayName、baseLanguageCode、CJK 展示属性、AppLanguagePreference.system / .language(AppLanguage) 和手写 allCases。
- Preserves: 当前 12 种译文仍由内联表提供；资源迁移留到 Task 2。

- [ ] **Step 1: 先写 canonical locale、关联偏好、旧值与语言族属性测试**

在 AppLanguageSettingsTests 中把旧的固定 AppLanguagePreference case 清单测试替换为以下行为：

~~~swift
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
~~~

增加表驱动旧值测试，覆盖 en、zh-Hans、zh-Hant、ja、ko、es、de、fr、pt-BR、it、nl、pl；每个旧值读取后必须得到 .language(对应 AppLanguage)。把所有设置具体语言的现有测试改为 .language(.en) 等关联值写法，并把新保存英文的断言从 en 改为 en-US。

- [ ] **Step 2: 运行语言设置 suite，确认 RED**

Run:

~~~bash
xcodebuild -quiet -project TokenWatch.xcodeproj -scheme TokenWatch -destination 'platform=macOS' '-only-testing:TokenWatchTests/AppLanguageSettingsTests' -skip-testing:TokenWatchUITests -derivedDataPath .build/DerivedData -enableCodeCoverage NO test
~~~

Expected: 测试被发现；当前 raw values、关联 case 和语言族属性不满足新接口，因此编译或断言失败。

- [ ] **Step 3: 落地单一偏好模型和 canonical 存储**

在 AppLanguage 保留现有 Swift case 名，先只把 12 个 raw value 改成精确 locale：

~~~swift
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
~~~

增加这些派生属性：

~~~swift
var localeIdentifier: String { rawValue }
var resourceIdentifier: String { rawValue }
var baseLanguageCode: String {
    rawValue.split(separator: "-", maxSplits: 1).first.map(String.init)?.lowercased() ?? rawValue
}
var nativeDisplayName: String {
    Locale(identifier: rawValue).localizedString(forIdentifier: rawValue) ?? rawValue
}
var usesCompactCJKFormatting: Bool { ["zh", "ja", "ko"].contains(baseLanguageCode) }
var usesFullWidthParentheses: Bool { baseLanguageCode == "zh" }
var yearAxisSuffix: String? {
    switch baseLanguageCode {
    case "zh", "ja": "年"
    case "ko": "년"
    default: nil
    }
}
var hourSuffix: String? {
    switch baseLanguageCode {
    case "zh": "时"
    case "ja": "時"
    case "ko": "시"
    default: nil
    }
}
~~~

把 AppLanguagePreference 改为：

~~~swift
enum AppLanguagePreference: CaseIterable, Sendable, Equatable {
    case system
    case language(AppLanguage)

    static var allCases: [Self] {
        [.system] + AppLanguage.allCases.map(Self.language)
    }

    var storageValue: String {
        switch self {
        case .system: "system"
        case .language(let language): language.rawValue
        }
    }
}
~~~

具体语言 title 使用 language.nativeDisplayName；system 继续查 AppStrings.languageSystem。selectedPreference 读取顺序为 canonical AppLanguage raw value → 旧值映射 → system，写入 storageValue；resolvedLanguage 对 .language 直接返回关联值。未知持久化值仍按 .system。

- [ ] **Step 4: 用语言族属性消除会阻碍扩 enum 的 switch**

- LocalHourBucketDescriptor.label 返回小时数字加可选 hourSuffix。
- MonthlyTokenChartBuilder 暂时用 usesCompactCJKFormatting 决定旧 suffix 前是否有空格；Task 2 再改为完整格式 key。
- MonthlyBarChartStyle 用 yearAxisSuffix 和 usesCompactCJKFormatting 保留现有 CJK 轴标签/hover 行为。
- CalendarHeatmapBuilder 用 usesCompactCJKFormatting 选择 veryShortStandaloneWeekdaySymbols，其余使用 shortStandaloneWeekdaySymbols。
- DashboardViewController 用 usesFullWidthParentheses 选择中文全角括号。
- AppLanguageSettings.resolvedLanguage 和 AppLanguagePreference.title 不再包含按语言逐 case switch。

此步骤不得改变数字、日期、金额或 token 缩写格式。

- [ ] **Step 5: 重跑语言与受影响组件测试**

Run:

~~~bash
xcodebuild -quiet -project TokenWatch.xcodeproj -scheme TokenWatch -destination 'platform=macOS' '-only-testing:TokenWatchTests/AppLanguageSettingsTests' '-only-testing:TokenWatchTests/CalendarHeatmapBuilderTests' '-only-testing:TokenWatchTests/MonthlyTokenChartBuilderTests' '-only-testing:TokenWatchTests/TodayHourlyTokenLineChartViewTests' -skip-testing:TokenWatchUITests -derivedDataPath .build/DerivedData -enableCodeCoverage NO test
~~~

Expected: 选中的测试全部通过；现有 12 种语言的小时、月份、星期和空状态输出不变，持久化新值为精确 locale。

- [ ] **Step 6: 检查并提交基础模型**

Run:

~~~bash
git diff --check
rg -n 'switch language|switch self' TokenWatch/Localization/AppLanguage.swift TokenWatch/Models/LocalHourBucketDescriptor.swift TokenWatch/ViewControllers/MonthlyTokenChartBuilder.swift TokenWatch/ViewControllers/MonthlyBarChartStyle.swift TokenWatch/ViewControllers/CalendarHeatmapBuilder.swift TokenWatch/ViewControllers/DashboardViewController.swift
git status --short
~~~

Expected: 除尚待 Task 2 移除的 periodAxisValueName 及与业务枚举有关的 switch 外，不再有会因新增 AppLanguage case 而不穷举的语言 switch。

Commit:

~~~bash
git add TokenWatch/Localization/AppLanguage.swift TokenWatch/Models/LocalHourBucketDescriptor.swift TokenWatch/ViewControllers/MonthlyTokenChartBuilder.swift TokenWatch/ViewControllers/MonthlyBarChartStyle.swift TokenWatch/ViewControllers/CalendarHeatmapBuilder.swift TokenWatch/ViewControllers/DashboardViewController.swift TokenWatch/ViewController.swift TokenWatchTests/Localization/AppLanguageSettingsTests.swift TokenWatchTests/AppMainMenuBuilderTests.swift TokenWatchTests/TokenWatchTests.swift TokenWatchTests/ViewControllers/CalendarHeatmapCollectionViewItemTests.swift TokenWatchTests/ViewControllers/StatusBarControllerTests.swift TokenWatchTests/ViewControllers/StatusPopoverViewControllerTests.swift
git commit -m "refactor(i18n): 统一语言偏好与 locale 模型"
~~~

---

### Task 2: 把现有 12 份内联译文迁移为 140-key .strings 资源

**Files:**
- Create: TokenWatch/Localization/Resources/en-US.lproj/Localizable.strings
- Create: TokenWatch/Localization/Resources/zh-CN.lproj/Localizable.strings
- Create: TokenWatch/Localization/Resources/zh-TW.lproj/Localizable.strings
- Create: TokenWatch/Localization/Resources/ja-JP.lproj/Localizable.strings
- Create: TokenWatch/Localization/Resources/ko-KR.lproj/Localizable.strings
- Create: TokenWatch/Localization/Resources/es-ES.lproj/Localizable.strings
- Create: TokenWatch/Localization/Resources/de-DE.lproj/Localizable.strings
- Create: TokenWatch/Localization/Resources/fr-FR.lproj/Localizable.strings
- Create: TokenWatch/Localization/Resources/pt-BR.lproj/Localizable.strings
- Create: TokenWatch/Localization/Resources/it-IT.lproj/Localizable.strings
- Create: TokenWatch/Localization/Resources/nl-NL.lproj/Localizable.strings
- Create: TokenWatch/Localization/Resources/pl-PL.lproj/Localizable.strings
- Modify: TokenWatch/Localization/AppStrings.swift:8-1890
- Modify: TokenWatch/Localization/AppLanguage.swift:18-49
- Modify: TokenWatch/ViewControllers/MonthlyTokenChartBuilder.swift:31-45
- Modify: TokenWatch/ViewControllers/DashboardTrendView.swift:474-476
- Modify: TokenWatch/ViewControllers/TodayHourlyTokenLineChartView.swift:234-236
- Create: TokenWatchTests/Localization/AppLocalizationResourcesTests.swift
- Create: TokenWatchTests/Localization/LocalizationEnglishReuseAllowlist.swift
- Modify: TokenWatchTests/Localization/AppLanguageSettingsTests.swift
- Modify: TokenWatchTests/ViewControllers/MonthlyTokenChartBuilderTests.swift

**Interfaces:**
- Consumes: 当前 12 × 139 内联字典、AppLanguage.resourceIdentifier、Bundle.main。
- Produces: String raw-valued AppStringKey（140 项）、Bundle 查找器、12 份完整资源、源码级资源验证 helper。
- Lookup contract: 目标 locale → en-US → key.rawValue；静态完整性测试不走该回退。

- [ ] **Step 1: 写资源语法、重复 key、完整性和占位符测试**

新建 @Suite("AppLocalizationResources")，从 #filePath 向上定位仓库根，再进入 TokenWatch/Localization/Resources。测试 helper 必须：

1. 用 PropertyListSerialization 把每份 Localizable.strings 解析成 [String: String]。
2. 从原始文本逐条扫描行首 quoted key 声明；断言声明数等于唯一 key 数，避免 plist 解析吞掉重复 key。
3. 断言每份 key Set 等于 Set(AppStringKey.allCases.map(\.rawValue))，且 AppStringKey.allCases.count == 140。
4. 断言值去除首尾空白后非空，且不等于 raw key。
5. 把 %@、%d、%1$@、%2$d 等格式符规范化为“参数位置 + 类型”；忽略 %%，拒绝未知格式符、隐式/显式位置混用和越界位置，并与 en-US 同 key 比较。
6. 直接打开每个 .lproj 子 Bundle，以缺失哨兵读取每个 key；不得调用 AppStrings.text。
7. 非英语值若与英文完全相同，只允许纯固定术语，或命中 LocalizationEnglishReuseAllowlist 中精确的 locale + key + 理由记录。
8. 去除固定术语、占位符、数字和标点后，若目标值仍包含与 en-US 相同的连续两个及以上 word n-gram，则要求同样的 exact allowlist 和人工理由；不能按整个 locale 放行。
9. 对英文基准中出现的 AI Token Watch、Claude Code、Codex、opencode、Token/ Tokens、SQLite 和 opencode.db 做大小写敏感的出现次数检查，目标资源不得丢失或翻译这些固定名称。

最终 11 个格式 key 的标准签名固定为：

- dashboardTotalSourcesProjectsFormat：1:d, 2:d
- dashboardScanUpdatedFormat：1:@
- dashboardMinutesAgoFormat：1:d
- dashboardHoursAgoFormat：1:d
- dashboardShowingSessionsFormat：1:@, 2:@, 3:@
- periodNoTokenDataFormat：1:@
- chartTokenAccessibilityFormat：1:@
- chartCostAccessibilityFormat：1:@
- errorOpenCodeDatabaseNotFoundFormat：1:@
- errorOpenCodeDatabaseOpenFailedFormat：1:d, 2:@
- errorOpenCodeDatabaseQueryFailedFormat：1:d, 2:@

首个测试只锁定 Task 2 的 12 个 locale：

~~~swift
private let migratedLocaleIdentifiers = [
    "en-US", "zh-CN", "zh-TW", "ja-JP", "ko-KR", "es-ES",
    "de-DE", "fr-FR", "pt-BR", "it-IT", "nl-NL", "pl-PL",
]

@Test("迁移的十二份资源均直接定义全部 140 个 key")
func migratedResourcesDefineAllKeys() throws {
    #expect(AppStringKey.allCases.count == 140)
    try assertCompleteResources(migratedLocaleIdentifiers)
}
~~~

在 MonthlyTokenChartBuilderTests 增加格式字符串能完整控制语序的测试；英文期望 Today has no token data，中文期望 本日暂无 Token 数据，并验证 token/cost accessibility label 也把 period title 作为唯一 %@ 参数传入。

- [ ] **Step 2: 运行资源与图表测试，确认 RED**

Run:

~~~bash
xcodebuild -quiet -project TokenWatch.xcodeproj -scheme TokenWatch -destination 'platform=macOS' '-only-testing:TokenWatchTests/AppLocalizationResourcesTests' '-only-testing:TokenWatchTests/MonthlyTokenChartBuilderTests' -skip-testing:TokenWatchUITests -derivedDataPath .build/DerivedData -enableCodeCoverage NO test
~~~

Expected: 当前没有 Resources 目录，AppStringKey 也没有 rawValue/第 140 项，测试编译或资源存在性断言失败。

- [ ] **Step 3: 建立 140-key 英文基准并机械迁移现有译文**

把 AppStringKey 改为 String, CaseIterable, Sendable；case raw value 由 Swift case 名自动推导。保留当前 139 项，不删除当前未被运行时调用的 languageChinese、languageEnglish、chartTokenAccessibility、chartCostAccessibility。

做以下精确变更：

- periodNoTokenDataSuffix → periodNoTokenDataFormat
- chartTokenAccessibilitySuffix → chartTokenAccessibilityFormat
- chartCostAccessibilitySuffix → chartCostAccessibilityFormat
- 新增 periodAxisValueName

en-US 的四个目标值为：

~~~text
"periodNoTokenDataFormat" = "%@ has no token data";
"chartTokenAccessibilityFormat" = "%@ token bar chart";
"chartCostAccessibilityFormat" = "%@ cost bar chart";
"periodAxisValueName" = "Period";
~~~

把当前 12 张 Swift 表中的其余 136 个值逐字迁移到对应 canonical .lproj；对三个 format key 把原来由调用方拼接的 period title 纳入格式字符串；把 AppLanguage.periodAxisValueName 的 12 个现有值迁入第 140 项。每个文件固定按 AppStringKey 声明顺序排列，一条 key/value 占一行，UTF-8 编码。

- [ ] **Step 4: 实现显式 locale Bundle 查找和回退**

AppStrings.text(_:language:) 使用 Bundle.main，并增加 internal bundle overload 与查找 closure seam。实现逻辑固定为：

~~~swift
static func text(_ key: AppStringKey, language: AppLanguage) -> String {
    text(key, language: language, bundle: .main)
}

static func text(_ key: AppStringKey, language: AppLanguage, bundle: Bundle) -> String {
    text(key, language: language) { targetLanguage, targetKey in
        localizedValue(targetKey, language: targetLanguage, bundle: bundle)
    }
}

static func text(
    _ key: AppStringKey,
    language: AppLanguage,
    lookup: (AppLanguage, AppStringKey) -> String?
) -> String {
    lookup(language, key) ?? lookup(.en, key) ?? key.rawValue
}
~~~

localizedValue 必须用 bundle.url(forResource: language.resourceIdentifier, withExtension: "lproj") 创建子 Bundle，再以唯一缺失哨兵调用 localizedString(forKey:value:table: "Localizable")。目标 bundle/key 缺失时记录 locale + key；英文缺失时返回 raw key。删除 12 张 Swift 字典和 localizedTables。

用 lookup seam 更新现有“目标缺失 → 英文 → raw key”测试，不创建只为测试而存在的生产字典接口。

- [ ] **Step 5: 改用完整格式 key 与本地化 period 轴名**

MonthlyTokenChartBuilder 的三个方法均读取完整 format，并以 period title 作为参数调用 String(format:locale:arguments:)；不再自行添加空格。DashboardTrendView 和 TodayHourlyTokenLineChartView 改为 AppStrings.text(.periodAxisValueName, language: language)。删除 AppLanguage.periodAxisValueName switch。

- [ ] **Step 6: 运行静态资源质量闸门和受影响回归**

Run:

~~~bash
find TokenWatch/Localization/Resources -type f -name Localizable.strings -exec plutil -lint {} +
xcodebuild -quiet -project TokenWatch.xcodeproj -scheme TokenWatch -destination 'platform=macOS' '-only-testing:TokenWatchTests/AppLocalizationResourcesTests' '-only-testing:TokenWatchTests/AppLanguageSettingsTests' '-only-testing:TokenWatchTests/MonthlyTokenChartBuilderTests' '-only-testing:TokenWatchTests/TodayHourlyTokenLineChartViewTests' -skip-testing:TokenWatchUITests -derivedDataPath .build/DerivedData -enableCodeCoverage NO test
~~~

Expected: 12 份文件均 plutil OK；每份恰好 140 个唯一 key，占位符签名与 en-US 一致，lookup 回退和图表文本测试通过。

- [ ] **Step 7: 检查并提交资源迁移**

Run:

~~~bash
git diff --check
rg -n 'private static let (zhHans|zhHant|en|ja|ko|es|de|fr|ptBR|it|nl|pl)|localizedTables|periodNoTokenDataSuffix|chartTokenAccessibilitySuffix|chartCostAccessibilitySuffix|periodAxisValueName' TokenWatch -g '*.swift'
git status --short
~~~

Expected: 内联翻译表和三个旧 suffix case 无匹配；periodAxisValueName 只作为 AppStringKey/调用出现，不再是 AppLanguage 属性。

Commit:

~~~bash
git add TokenWatch/Localization/AppLanguage.swift TokenWatch/Localization/AppStrings.swift TokenWatch/Localization/Resources TokenWatch/ViewControllers/MonthlyTokenChartBuilder.swift TokenWatch/ViewControllers/DashboardTrendView.swift TokenWatch/ViewControllers/TodayHourlyTokenLineChartView.swift TokenWatchTests/Localization/AppLanguageSettingsTests.swift TokenWatchTests/Localization/AppLocalizationResourcesTests.swift TokenWatchTests/Localization/LocalizationEnglishReuseAllowlist.swift TokenWatchTests/ViewControllers/MonthlyTokenChartBuilderTests.swift
git commit -m "refactor(i18n): 迁移现有译文到 locale 资源"
~~~

---

### Task 3: 添加西欧、北欧与地区变体的 10 份完整译文

**Files:**
- Create: TokenWatch/Localization/Resources/ca-ES.lproj/Localizable.strings
- Create: TokenWatch/Localization/Resources/da-DK.lproj/Localizable.strings
- Create: TokenWatch/Localization/Resources/es-419.lproj/Localizable.strings
- Create: TokenWatch/Localization/Resources/fi-FI.lproj/Localizable.strings
- Create: TokenWatch/Localization/Resources/fr-CA.lproj/Localizable.strings
- Create: TokenWatch/Localization/Resources/is-IS.lproj/Localizable.strings
- Create: TokenWatch/Localization/Resources/nb-NO.lproj/Localizable.strings
- Create: TokenWatch/Localization/Resources/pt-PT.lproj/Localizable.strings
- Create: TokenWatch/Localization/Resources/ro-RO.lproj/Localizable.strings
- Create: TokenWatch/Localization/Resources/sv-SE.lproj/Localizable.strings
- Modify: TokenWatchTests/Localization/AppLocalizationResourcesTests.swift
- Modify: TokenWatchTests/Localization/LocalizationEnglishReuseAllowlist.swift

**Interfaces:**
- Consumes: en-US 140-key 语义基准与 Task 2 的 assertCompleteResources。
- Produces: 10 份尚未在 AppLanguage 中激活、但已可独立审阅和验证的完整资源。

- [ ] **Step 1: 增加固定批次测试并确认缺文件 RED**

增加 westernAndRegionalResourcesAreComplete()，硬编码上述 10 个 locale 并调用 assertCompleteResources。运行：

~~~bash
xcodebuild -quiet -project TokenWatch.xcodeproj -scheme TokenWatch -destination 'platform=macOS' '-only-testing:TokenWatchTests/AppLocalizationResourcesTests/westernAndRegionalResourcesAreComplete()' -skip-testing:TokenWatchUITests -derivedDataPath .build/DerivedData -enableCodeCoverage NO test
~~~

Expected: 测试被发现并因 10 个资源目录尚不存在而失败。

- [ ] **Step 2: 提供 10 × 140 条完整译文**

逐文件翻译全部 140 项。es-419 不复制 es-ES 冒充完成，fr-CA 不复制 fr-FR，pt-PT 不复制 pt-BR；地区自然表达、标点和术语分别审阅。格式 key 可用位置参数改变语序，但签名必须一致。

- [ ] **Step 3: 运行语法、完整性和英文残留检查**

Run:

~~~bash
find TokenWatch/Localization/Resources -type f -name Localizable.strings -exec plutil -lint {} +
xcodebuild -quiet -project TokenWatch.xcodeproj -scheme TokenWatch -destination 'platform=macOS' '-only-testing:TokenWatchTests/AppLocalizationResourcesTests' -skip-testing:TokenWatchUITests -derivedDataPath .build/DerivedData -enableCodeCoverage NO test
~~~

Expected: 现有 12 份与本批 10 份全部通过。逐项人工复核 Dashboard、设置、菜单、状态栏、popover、辅助功能六类语境；只有正确且不可翻译的英文同值才可加入 exact allowlist，并在同一行说明理由。

- [ ] **Step 4: 提交本批**

~~~bash
git diff --check
git add TokenWatch/Localization/Resources/ca-ES.lproj TokenWatch/Localization/Resources/da-DK.lproj TokenWatch/Localization/Resources/es-419.lproj TokenWatch/Localization/Resources/fi-FI.lproj TokenWatch/Localization/Resources/fr-CA.lproj TokenWatch/Localization/Resources/is-IS.lproj TokenWatch/Localization/Resources/nb-NO.lproj TokenWatch/Localization/Resources/pt-PT.lproj TokenWatch/Localization/Resources/ro-RO.lproj TokenWatch/Localization/Resources/sv-SE.lproj TokenWatchTests/Localization/AppLocalizationResourcesTests.swift TokenWatchTests/Localization/LocalizationEnglishReuseAllowlist.swift
git commit -m "feat(i18n): 添加西欧与北欧译文"
~~~

---

### Task 4: 添加中东欧拉丁文字的 11 份完整译文

**Files:**
- Create: TokenWatch/Localization/Resources/bs-BA.lproj/Localizable.strings
- Create: TokenWatch/Localization/Resources/cs-CZ.lproj/Localizable.strings
- Create: TokenWatch/Localization/Resources/et-EE.lproj/Localizable.strings
- Create: TokenWatch/Localization/Resources/hr-HR.lproj/Localizable.strings
- Create: TokenWatch/Localization/Resources/hu-HU.lproj/Localizable.strings
- Create: TokenWatch/Localization/Resources/lt.lproj/Localizable.strings
- Create: TokenWatch/Localization/Resources/lv-LV.lproj/Localizable.strings
- Create: TokenWatch/Localization/Resources/sk-SK.lproj/Localizable.strings
- Create: TokenWatch/Localization/Resources/sl-SI.lproj/Localizable.strings
- Create: TokenWatch/Localization/Resources/sq-AL.lproj/Localizable.strings
- Create: TokenWatch/Localization/Resources/tr-TR.lproj/Localizable.strings
- Modify: TokenWatchTests/Localization/AppLocalizationResourcesTests.swift
- Modify: TokenWatchTests/Localization/LocalizationEnglishReuseAllowlist.swift

**Interfaces:**
- Produces: bs-BA、cs-CZ、et-EE、hr-HR、hu-HU、lt、lv-LV、sk-SK、sl-SI、sq-AL、tr-TR 的 140-key 直接资源。

- [ ] **Step 1: 增加 centralEuropeanLatinResourcesAreComplete() 并运行确认 RED**

~~~bash
xcodebuild -quiet -project TokenWatch.xcodeproj -scheme TokenWatch -destination 'platform=macOS' '-only-testing:TokenWatchTests/AppLocalizationResourcesTests/centralEuropeanLatinResourcesAreComplete()' -skip-testing:TokenWatchUITests -derivedDataPath .build/DerivedData -enableCodeCoverage NO test
~~~

Expected: 因本批 11 个目录缺失而失败。

- [ ] **Step 2: 完成 11 × 140 条译文并逐语言审校**

以 en-US 的完整句义为基准；保留固定技术术语，不能把相邻语言资源整体复制。对匈牙利语、土耳其语等语序不同的格式句优先用位置参数表达自然语序。

- [ ] **Step 3: 跑全量现有资源闸门并提交**

~~~bash
find TokenWatch/Localization/Resources -type f -name Localizable.strings -exec plutil -lint {} +
xcodebuild -quiet -project TokenWatch.xcodeproj -scheme TokenWatch -destination 'platform=macOS' '-only-testing:TokenWatchTests/AppLocalizationResourcesTests' -skip-testing:TokenWatchUITests -derivedDataPath .build/DerivedData -enableCodeCoverage NO test
git diff --check
git add TokenWatch/Localization/Resources/bs-BA.lproj TokenWatch/Localization/Resources/cs-CZ.lproj TokenWatch/Localization/Resources/et-EE.lproj TokenWatch/Localization/Resources/hr-HR.lproj TokenWatch/Localization/Resources/hu-HU.lproj TokenWatch/Localization/Resources/lt.lproj TokenWatch/Localization/Resources/lv-LV.lproj TokenWatch/Localization/Resources/sk-SK.lproj TokenWatch/Localization/Resources/sl-SI.lproj TokenWatch/Localization/Resources/sq-AL.lproj TokenWatch/Localization/Resources/tr-TR.lproj TokenWatchTests/Localization/AppLocalizationResourcesTests.swift TokenWatchTests/Localization/LocalizationEnglishReuseAllowlist.swift
git commit -m "feat(i18n): 添加中东欧拉丁文字译文"
~~~

Expected: 当前累计 33 份资源全部满足 140-key 和质量闸门。

---

### Task 5: 添加东欧、高加索与中亚文字的 10 份完整译文

**Files:**
- Create: TokenWatch/Localization/Resources/bg-BG.lproj/Localizable.strings
- Create: TokenWatch/Localization/Resources/el-GR.lproj/Localizable.strings
- Create: TokenWatch/Localization/Resources/hy-AM.lproj/Localizable.strings
- Create: TokenWatch/Localization/Resources/ka-GE.lproj/Localizable.strings
- Create: TokenWatch/Localization/Resources/kk.lproj/Localizable.strings
- Create: TokenWatch/Localization/Resources/mk-MK.lproj/Localizable.strings
- Create: TokenWatch/Localization/Resources/mn.lproj/Localizable.strings
- Create: TokenWatch/Localization/Resources/ru-RU.lproj/Localizable.strings
- Create: TokenWatch/Localization/Resources/sr-RS.lproj/Localizable.strings
- Create: TokenWatch/Localization/Resources/uk-UA.lproj/Localizable.strings
- Modify: TokenWatchTests/Localization/AppLocalizationResourcesTests.swift
- Modify: TokenWatchTests/Localization/LocalizationEnglishReuseAllowlist.swift

**Interfaces:**
- Produces: 西里尔、希腊、亚美尼亚、格鲁吉亚等文字系统的 10 × 140 条直接资源。

- [ ] **Step 1: 增加 easternEuropeanAndCentralAsianResourcesAreComplete() 并确认 RED**

~~~bash
xcodebuild -quiet -project TokenWatch.xcodeproj -scheme TokenWatch -destination 'platform=macOS' '-only-testing:TokenWatchTests/AppLocalizationResourcesTests/easternEuropeanAndCentralAsianResourcesAreComplete()' -skip-testing:TokenWatchUITests -derivedDataPath .build/DerivedData -enableCodeCoverage NO test
~~~

Expected: 因本批目录缺失失败。

- [ ] **Step 2: 完成 10 × 140 条译文**

每个资源直接翻译所有项；同为西里尔文字不代表语义相同，bg-BG、mk-MK、ru-RU、sr-RS、uk-UA 必须分别审校。动态占位符和固定数据库/产品名保持原样。

- [ ] **Step 3: 跑全量现有资源闸门并提交**

~~~bash
find TokenWatch/Localization/Resources -type f -name Localizable.strings -exec plutil -lint {} +
xcodebuild -quiet -project TokenWatch.xcodeproj -scheme TokenWatch -destination 'platform=macOS' '-only-testing:TokenWatchTests/AppLocalizationResourcesTests' -skip-testing:TokenWatchUITests -derivedDataPath .build/DerivedData -enableCodeCoverage NO test
git diff --check
git add TokenWatch/Localization/Resources/bg-BG.lproj TokenWatch/Localization/Resources/el-GR.lproj TokenWatch/Localization/Resources/hy-AM.lproj TokenWatch/Localization/Resources/ka-GE.lproj TokenWatch/Localization/Resources/kk.lproj TokenWatch/Localization/Resources/mk-MK.lproj TokenWatch/Localization/Resources/mn.lproj TokenWatch/Localization/Resources/ru-RU.lproj TokenWatch/Localization/Resources/sr-RS.lproj TokenWatch/Localization/Resources/uk-UA.lproj TokenWatchTests/Localization/AppLocalizationResourcesTests.swift TokenWatchTests/Localization/LocalizationEnglishReuseAllowlist.swift
git commit -m "feat(i18n): 添加东欧与中亚译文"
~~~

Expected: 当前累计 43 份资源全部通过。

---

### Task 6: 添加中东与南亚文字的 12 份完整译文

**Files:**
- Create: TokenWatch/Localization/Resources/ar.lproj/Localizable.strings
- Create: TokenWatch/Localization/Resources/bn-BD.lproj/Localizable.strings
- Create: TokenWatch/Localization/Resources/fa.lproj/Localizable.strings
- Create: TokenWatch/Localization/Resources/gu-IN.lproj/Localizable.strings
- Create: TokenWatch/Localization/Resources/hi-IN.lproj/Localizable.strings
- Create: TokenWatch/Localization/Resources/kn-IN.lproj/Localizable.strings
- Create: TokenWatch/Localization/Resources/ml.lproj/Localizable.strings
- Create: TokenWatch/Localization/Resources/mr-IN.lproj/Localizable.strings
- Create: TokenWatch/Localization/Resources/pa.lproj/Localizable.strings
- Create: TokenWatch/Localization/Resources/ta-IN.lproj/Localizable.strings
- Create: TokenWatch/Localization/Resources/te-IN.lproj/Localizable.strings
- Create: TokenWatch/Localization/Resources/ur.lproj/Localizable.strings
- Modify: TokenWatchTests/Localization/AppLocalizationResourcesTests.swift
- Modify: TokenWatchTests/Localization/LocalizationEnglishReuseAllowlist.swift

**Interfaces:**
- Produces: ar、bn-BD、fa、gu-IN、hi-IN、kn-IN、ml、mr-IN、pa、ta-IN、te-IN、ur 的 12 × 140 条直接资源。
- Preserves: 即使目标文字通常使用 RTL，资源加入不改变任何布局方向或约束。

- [ ] **Step 1: 增加 middleEasternAndSouthAsianResourcesAreComplete() 并确认 RED**

~~~bash
xcodebuild -quiet -project TokenWatch.xcodeproj -scheme TokenWatch -destination 'platform=macOS' '-only-testing:TokenWatchTests/AppLocalizationResourcesTests/middleEasternAndSouthAsianResourcesAreComplete()' -skip-testing:TokenWatchUITests -derivedDataPath .build/DerivedData -enableCodeCoverage NO test
~~~

Expected: 因本批目录缺失失败。

- [ ] **Step 2: 完成 12 × 140 条译文**

阿拉伯语、波斯语和乌尔都语只写译文，不加入 Unicode 方向控制字符，不改 leading/trailing 约束，不设置 RTL semantic direction。南亚九种语言分别翻译，不以印地语文本替代其他文字。

- [ ] **Step 3: 检查方向控制字符、资源质量并提交**

Run:

~~~bash
rg -n '[\x{202A}-\x{202E}\x{2066}-\x{2069}]' TokenWatch/Localization/Resources/ar.lproj TokenWatch/Localization/Resources/fa.lproj TokenWatch/Localization/Resources/ur.lproj
find TokenWatch/Localization/Resources -type f -name Localizable.strings -exec plutil -lint {} +
xcodebuild -quiet -project TokenWatch.xcodeproj -scheme TokenWatch -destination 'platform=macOS' '-only-testing:TokenWatchTests/AppLocalizationResourcesTests' -skip-testing:TokenWatchUITests -derivedDataPath .build/DerivedData -enableCodeCoverage NO test
~~~

Expected: rg 无输出；当前累计 55 份资源全部通过。

Commit:

~~~bash
git diff --check
git add TokenWatch/Localization/Resources/ar.lproj TokenWatch/Localization/Resources/bn-BD.lproj TokenWatch/Localization/Resources/fa.lproj TokenWatch/Localization/Resources/gu-IN.lproj TokenWatch/Localization/Resources/hi-IN.lproj TokenWatch/Localization/Resources/kn-IN.lproj TokenWatch/Localization/Resources/ml.lproj TokenWatch/Localization/Resources/mr-IN.lproj TokenWatch/Localization/Resources/pa.lproj TokenWatch/Localization/Resources/ta-IN.lproj TokenWatch/Localization/Resources/te-IN.lproj TokenWatch/Localization/Resources/ur.lproj TokenWatchTests/Localization/AppLocalizationResourcesTests.swift TokenWatchTests/Localization/LocalizationEnglishReuseAllowlist.swift
git commit -m "feat(i18n): 添加中东与南亚译文"
~~~

---

### Task 7: 添加非洲、东南亚与香港中文的最后 10 份完整译文

**Files:**
- Create: TokenWatch/Localization/Resources/am.lproj/Localizable.strings
- Create: TokenWatch/Localization/Resources/id-ID.lproj/Localizable.strings
- Create: TokenWatch/Localization/Resources/ms-MY.lproj/Localizable.strings
- Create: TokenWatch/Localization/Resources/my-MM.lproj/Localizable.strings
- Create: TokenWatch/Localization/Resources/so-SO.lproj/Localizable.strings
- Create: TokenWatch/Localization/Resources/sw-TZ.lproj/Localizable.strings
- Create: TokenWatch/Localization/Resources/th-TH.lproj/Localizable.strings
- Create: TokenWatch/Localization/Resources/tl.lproj/Localizable.strings
- Create: TokenWatch/Localization/Resources/vi-VN.lproj/Localizable.strings
- Create: TokenWatch/Localization/Resources/zh-HK.lproj/Localizable.strings
- Modify: TokenWatchTests/Localization/AppLocalizationResourcesTests.swift
- Modify: TokenWatchTests/Localization/LocalizationEnglishReuseAllowlist.swift

**Interfaces:**
- Produces: 最后 10 × 140 条资源；完成磁盘上的冻结 65-locale 资源全集。

- [ ] **Step 1: 增加 africanSoutheastAsianAndHongKongResourcesAreComplete() 并确认 RED**

~~~bash
xcodebuild -quiet -project TokenWatch.xcodeproj -scheme TokenWatch -destination 'platform=macOS' '-only-testing:TokenWatchTests/AppLocalizationResourcesTests/africanSoutheastAsianAndHongKongResourcesAreComplete()' -skip-testing:TokenWatchUITests -derivedDataPath .build/DerivedData -enableCodeCoverage NO test
~~~

Expected: 因本批目录缺失失败。

- [ ] **Step 2: 完成 10 × 140 条译文**

zh-HK 使用香港繁体自然表达，不直接复制 zh-TW；id-ID 与 ms-MY、so-SO 与 sw-TZ 分别审校。缅甸、泰、阿姆哈拉文字资源保持 UTF-8 且不混入英文占位句。

- [ ] **Step 3: 添加冻结资源目录全集断言**

在 AppLocalizationResourcesTests 增加 independent frozenCodexLocaleIdentifiers 常量，按设计文档的 65 项精确顺序列出；测试源码 Resources 下的 .lproj 集合与该常量完全一致，并对 65 份全部调用 assertCompleteResources。此常量不得从 AppLanguage.allCases 生成，避免实现与测试共享同一错误。

- [ ] **Step 4: 跑 65 份静态资源闸门并提交**

~~~bash
find TokenWatch/Localization/Resources -type f -name Localizable.strings -exec plutil -lint {} +
xcodebuild -quiet -project TokenWatch.xcodeproj -scheme TokenWatch -destination 'platform=macOS' '-only-testing:TokenWatchTests/AppLocalizationResourcesTests' -skip-testing:TokenWatchUITests -derivedDataPath .build/DerivedData -enableCodeCoverage NO test
git diff --check
git add TokenWatch/Localization/Resources/am.lproj TokenWatch/Localization/Resources/id-ID.lproj TokenWatch/Localization/Resources/ms-MY.lproj TokenWatch/Localization/Resources/my-MM.lproj TokenWatch/Localization/Resources/so-SO.lproj TokenWatch/Localization/Resources/sw-TZ.lproj TokenWatch/Localization/Resources/th-TH.lproj TokenWatch/Localization/Resources/tl.lproj TokenWatch/Localization/Resources/vi-VN.lproj TokenWatch/Localization/Resources/zh-HK.lproj TokenWatchTests/Localization/AppLocalizationResourcesTests.swift TokenWatchTests/Localization/LocalizationEnglishReuseAllowlist.swift
git commit -m "feat(i18n): 添加非洲与亚洲新增译文"
~~~

Expected: 恰有 65 个 .lproj，每份恰有 140 个唯一、非空、可直接读取的 key。

---

### Task 8: 激活冻结的 65-locale 清单、系统解析与 Xcode regions

**Files:**
- Modify: TokenWatch/Localization/AppLanguage.swift
- Modify: TokenWatch.xcodeproj/project.pbxproj:190-195
- Modify: TokenWatchTests/Localization/AppLanguageSettingsTests.swift
- Create: TokenWatchTests/Localization/AppLanguageCatalogTests.swift
- Modify: TokenWatchTests/Localization/AppLocalizationResourcesTests.swift
- Modify: TokenWatchTests/TokenWatchTests.swift

**Interfaces:**
- Consumes: 已验证的 65 份磁盘资源、动态 AppLanguagePreference.allCases。
- Produces: 最终 65-case AppLanguage、66 项偏好列表、地区敏感系统语言解析、65 knownRegions + Base。

- [ ] **Step 1: 写独立冻结目录、66 项偏好与系统解析测试**

AppLanguageCatalogTests 中硬编码以下列表，断言 AppLanguage.allCases.map(\.rawValue) 与顺序完全一致、无重复，resourceIdentifier 与 rawValue 一致，nativeDisplayName 非空：

~~~swift
let frozenLocaleIdentifiers = [
    "en-US", "am", "ar", "bg-BG", "bn-BD", "bs-BA", "ca-ES", "cs-CZ",
    "da-DK", "de-DE", "el-GR", "es-419", "es-ES", "et-EE", "fa", "fi-FI",
    "fr-CA", "fr-FR", "gu-IN", "hi-IN", "hr-HR", "hu-HU", "hy-AM", "id-ID",
    "is-IS", "it-IT", "ja-JP", "ka-GE", "kk", "kn-IN", "ko-KR", "lt",
    "lv-LV", "mk-MK", "ml", "mn", "mr-IN", "ms-MY", "my-MM", "nb-NO",
    "nl-NL", "pa", "pl-PL", "pt-BR", "pt-PT", "ro-RO", "ru-RU", "sk-SK",
    "sl-SI", "so-SO", "sq-AL", "sr-RS", "sv-SE", "sw-TZ", "ta-IN", "te-IN",
    "th-TH", "tl", "tr-TR", "uk-UA", "ur", "vi-VN", "zh-CN", "zh-HK", "zh-TW",
]
~~~

断言 AppLanguagePreference.allCases.count == 66，首项 .system，其余等于 AppLanguage.allCases.map(.language)。

在 AppLanguageSettingsTests 增加以下表驱动行为：

- 完整 locale 匹配忽略大小写并接受下划线，例如 en_us → en-US。
- 首项 xx-XX 不支持、第二项 sv-SE 支持时选 sv-SE。
- zh-Hans/zh-CN → zh-CN；zh-HK/zh-MO/zh-Hant-HK → zh-HK；zh-TW/zh-Hant → zh-TW；裸 zh → zh-CN。
- es-ES/裸 es → es-ES；es-419 和拉美地区（至少 MX、AR、BR、CL、CO、PE）→ es-419。
- fr-CA → fr-CA；其他法语 → fr-FR。
- pt-PT → pt-PT；pt-BR/裸 pt → pt-BR。
- 仅有一个受支持变体的语言按 base code 匹配，例如 de-AT → de-DE。
- 全部不支持时回退 en-US。
- 12 个旧持久化值继续映射到 Task 1 指定 locale。

- [ ] **Step 2: 运行 catalog 与 resolver 测试，确认 RED**

~~~bash
xcodebuild -quiet -project TokenWatch.xcodeproj -scheme TokenWatch -destination 'platform=macOS' '-only-testing:TokenWatchTests/AppLanguageCatalogTests' '-only-testing:TokenWatchTests/AppLanguageSettingsTests' -skip-testing:TokenWatchUITests -derivedDataPath .build/DerivedData -enableCodeCoverage NO test
~~~

Expected: 当前 AppLanguage 只有 12 项，地区变体规则不完整，测试失败。

- [ ] **Step 3: 按冻结顺序扩展 AppLanguage 到 65 case**

保留已有 12 个 Swift case 名以减少无关调用方改动；最终 enum 精确写为：

~~~swift
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
~~~

不得手写第二份 preference case；AppLanguagePreference.allCases 继续动态映射。

Task 1/2 已移除所有按 12 case 穷举的展示 switch；扩 enum 后先运行：

~~~bash
rg -n 'case \.zhHans.*\.zhHant|case \.en.*\.es|switch language' TokenWatch -g '*.swift'
xcodebuild -quiet -project TokenWatch.xcodeproj -scheme TokenWatch -destination 'platform=macOS' -skip-testing:TokenWatchUITests -derivedDataPath .build/DerivedData build-for-testing
~~~

Expected: 没有遗漏导致的 enum exhaustion 编译错误。

- [ ] **Step 4: 实现 exact → 地区族 → 单变体 → 下一偏好 → en-US 解析**

每个 preferred identifier 先把下划线改为连字符并 lowercased；先与所有 rawValue 做完整匹配。多变体语言按 Step 1 固定规则处理；其他 base language 只在 AppLanguage 中恰有一个候选时返回该候选。当前 identifier 完全不支持时返回 nil，让外层继续检查下一项；列表耗尽才返回 .en。

西班牙语拉美集合显式包含 419、AR、BO、BR、CL、CO、CR、CU、DO、EC、GT、HN、MX、NI、PA、PE、PR、PY、SV、US、UY、VE；其他未识别西语地区回到 es-ES，避免把赤道几内亚等非拉美地区错误归入 es-419。

- [ ] **Step 5: 更新 project localization 元数据**

把 developmentRegion 从 en 改为 "en-US"；knownRegions 按冻结顺序列出 65 个 locale，再保留 Base。不要修改三个 Resources build phase，也不要创建文件引用。

在 AppLocalizationResourcesTests 从 project.pbxproj 的 knownRegions block 读取条目，断言集合恰为 frozen 65 + Base，且 developmentRegion 为 en-US。

- [ ] **Step 6: 验证 catalog、解析、资源与设置菜单**

~~~bash
xcodebuild -quiet -project TokenWatch.xcodeproj -scheme TokenWatch -destination 'platform=macOS' '-only-testing:TokenWatchTests/AppLanguageCatalogTests' '-only-testing:TokenWatchTests/AppLanguageSettingsTests' '-only-testing:TokenWatchTests/AppLocalizationResourcesTests' '-only-testing:TokenWatchTests/TokenWatchTests/settingsShowsLanguageMenu()' -skip-testing:TokenWatchUITests -derivedDataPath .build/DerivedData -enableCodeCoverage NO test
~~~

Expected: 65 locale、66 偏好、迁移、地区解析、140-key 资源和项目 regions 全部通过；设置菜单首项为本地化的 System，其余 65 项按冻结顺序显示 nativeDisplayName。

- [ ] **Step 7: 提交 catalog 激活**

~~~bash
git diff --check
git diff -- TokenWatch/Localization/AppLanguage.swift TokenWatch.xcodeproj/project.pbxproj TokenWatchTests/Localization TokenWatchTests/TokenWatchTests.swift
git add TokenWatch/Localization/AppLanguage.swift TokenWatch.xcodeproj/project.pbxproj TokenWatchTests/Localization/AppLanguageSettingsTests.swift TokenWatchTests/Localization/AppLanguageCatalogTests.swift TokenWatchTests/Localization/AppLocalizationResourcesTests.swift TokenWatchTests/TokenWatchTests.swift
git commit -m "feat(i18n): 激活 Codex 65 个 locale"
~~~

---

### Task 9: 验证新增文字系统的 UI 即时刷新与固定 LTR 行为

**Files:**
- Modify: TokenWatchTests/Localization/AppLanguageSettingsTests.swift
- Modify: TokenWatchTests/AppMainMenuBuilderTests.swift
- Modify: TokenWatchTests/TokenWatchTests.swift
- Modify: TokenWatchTests/ViewControllers/StatusBarControllerTests.swift
- Modify: TokenWatchTests/ViewControllers/StatusPopoverViewControllerTests.swift
- Modify: TokenWatchTests/ViewControllers/CalendarHeatmapBuilderTests.swift
- Modify: TokenWatchTests/ViewControllers/MonthlyTokenChartBuilderTests.swift
- Modify: TokenWatchUITests/TokenWatchUITests.swift:108-124

**Interfaces:**
- Consumes: 65-locale AppStrings、现有同步 observer、DashboardViewController.refreshAction 测试注入、UI test languagePreference launch argument。
- Produces: 跨文字系统组件覆盖、无数据重载证明、Arabic LTR UI 冒烟测试。

- [ ] **Step 1: 写八种代表 locale 的显式译文样本测试**

用资源中已人工审校的精确值断言 settingsTitle，至少覆盖：

~~~swift
let samples: [(AppLanguage, String)] = [
    (.ar, "الإعدادات"),
    (.hiIN, "सेटिंग्स"),
    (.thTH, "การตั้งค่า"),
    (.ukUA, "Налаштування"),
    (.viVN, "Cài đặt"),
    (.zhHK, "設定"),
    (.es419, "Configuración"),
    (.ptPT, "Definições"),
]
~~~

如果本批最终审校采用更自然的同义词，先更新这里的显式期望与资源为同一已审定表达，不能改成“非空”或从资源反读自身作为期望。

- [ ] **Step 2: 写 UI 切换和不重载数据测试**

扩展现有测试以证明：

- Settings 的语言菜单有 66 项，选择 pt-PT 后存储 pt-PT、选中项保持并立即显示葡萄牙译文。
- Dashboard 从 zh-CN 切换 uk-UA 后可见标题立即变化。
- 通过 DashboardViewController 注入 refreshAction 计数；语言 observer 触发 render 后计数仍为 0。stateProvider 可被重新读取以构造现有 snapshot，但不能把它当作 provider load 计数。
- 主菜单用 th-TH、状态栏用 vi-VN、popover 用 hi-IN、星期/图表用 zh-HK 与 es-419 各验证一个显式可见字符串。

Run:

~~~bash
xcodebuild -quiet -project TokenWatch.xcodeproj -scheme TokenWatch -destination 'platform=macOS' '-only-testing:TokenWatchTests/TokenWatchTests/settingsShowsLanguageMenu()' '-only-testing:TokenWatchTests/TokenWatchTests/languageChangeDoesNotInvokeDashboardRefreshAction()' '-only-testing:TokenWatchTests/AppMainMenuBuilderTests' '-only-testing:TokenWatchTests/StatusBarControllerTests' '-only-testing:TokenWatchTests/StatusPopoverViewControllerTests' '-only-testing:TokenWatchTests/CalendarHeatmapBuilderTests' '-only-testing:TokenWatchTests/MonthlyTokenChartBuilderTests' -skip-testing:TokenWatchUITests -derivedDataPath .build/DerivedData -enableCodeCoverage NO test
~~~

Expected: 这些是验收型测试。若现有实现已满足要求，应直接通过且不修改生产代码；若失败，只修复对应 UI 表面的 locale wiring。不得在语言变化回调中调用 refreshAction、provider scanner、SQLite 或聚合器。

- [ ] **Step 3: 更新 UI launch 默认值并增加 Arabic LTR 冒烟**

把 launchForUITesting 默认旧值 zh-Hans 改为 zh-CN。新增 testArabicLaunchUsesLocalizedCopyAndKeepsLTRLayout：

- 以 languagePreference: "ar" 启动。
- 等待 Arabic 的 Dashboard 标题/设置标题出现，证明不是英文回退。
- 比较 DashboardNav.overview 的 frame.minX 小于主内容标题 frame.minX，证明侧栏仍在左、内容仍在右。
- 不断言或设置 RTL，不新增 semantic direction 生产代码。

Run:

~~~bash
xcodebuild -quiet -project TokenWatch.xcodeproj -scheme TokenWatch -destination 'platform=macOS' '-only-testing:TokenWatchUITests/TokenWatchUITests/testArabicLaunchUsesLocalizedCopyAndKeepsLTRLayout' -derivedDataPath .build/DerivedData -enableCodeCoverage NO test
~~~

Expected: 测试真实执行 1 项并通过；Arabic 文案可见且窗口结构保持 LTR。

- [ ] **Step 4: 提交 UI 验收覆盖**

~~~bash
git diff --check
git add TokenWatchTests/Localization/AppLanguageSettingsTests.swift TokenWatchTests/AppMainMenuBuilderTests.swift TokenWatchTests/TokenWatchTests.swift TokenWatchTests/ViewControllers/StatusBarControllerTests.swift TokenWatchTests/ViewControllers/StatusPopoverViewControllerTests.swift TokenWatchTests/ViewControllers/CalendarHeatmapBuilderTests.swift TokenWatchTests/ViewControllers/MonthlyTokenChartBuilderTests.swift TokenWatchUITests/TokenWatchUITests.swift
git commit -m "test(i18n): 覆盖新增语言即时刷新与 LTR"
~~~

---

### Task 10: 验证完整测试、构建产物和 65 份实际打包资源

**Files:**
- Verify only: TokenWatch/Localization/Resources/
- Verify only: .build/DerivedData/Build/Products/Debug/AI Token Watch.app/Contents/Resources/

**Interfaces:**
- Produces: 源资源、完整 app-hosted 测试、UI 测试和最终 app bundle 的验收证据。

- [ ] **Step 1: 运行全部源资源静态检查**

~~~bash
find TokenWatch/Localization/Resources -type f -name Localizable.strings -exec plutil -lint {} +
xcodebuild -quiet -project TokenWatch.xcodeproj -scheme TokenWatch -destination 'platform=macOS' '-only-testing:TokenWatchTests/AppLocalizationResourcesTests' '-only-testing:TokenWatchTests/AppLanguageCatalogTests' '-only-testing:TokenWatchTests/AppLanguageSettingsTests' -skip-testing:TokenWatchUITests -derivedDataPath .build/DerivedData -enableCodeCoverage NO test
~~~

Expected: 65 份 plutil OK；三个 localization suite 全部真实执行并通过。

- [ ] **Step 2: 运行完整单元测试和 UI 测试**

~~~bash
xcodebuild -quiet -project TokenWatch.xcodeproj -scheme TokenWatch -destination 'platform=macOS' -only-testing:TokenWatchTests -skip-testing:TokenWatchUITests -derivedDataPath .build/DerivedData -enableCodeCoverage NO test
xcodebuild -quiet -project TokenWatch.xcodeproj -scheme TokenWatch -destination 'platform=macOS' -only-testing:TokenWatchUITests -derivedDataPath .build/DerivedData -enableCodeCoverage NO test
~~~

Expected: 两条命令均为 TEST SUCCEEDED；不得以 0 tests 或 build-for-testing 代替。

- [ ] **Step 3: 构建 Debug 并核对 app bundle**

~~~bash
xcodebuild -quiet -project TokenWatch.xcodeproj -scheme TokenWatch -configuration Debug -derivedDataPath .build/DerivedData build
APP='.build/DerivedData/Build/Products/Debug/AI Token Watch.app'
test "$(find "$APP/Contents/Resources" -mindepth 2 -maxdepth 2 -type f -path '*.lproj/Localizable.strings' | wc -l | tr -d ' ')" = 65
diff -u <(find TokenWatch/Localization/Resources -mindepth 1 -maxdepth 1 -type d -name '*.lproj' -exec basename {} .lproj \; | LC_ALL=C sort) <(find "$APP/Contents/Resources" -mindepth 1 -maxdepth 1 -type d -name '*.lproj' -exec basename {} .lproj \; | LC_ALL=C sort)
find "$APP/Contents/Resources" -mindepth 2 -maxdepth 2 -type f -path '*.lproj/Localizable.strings' -exec plutil -lint {} +
~~~

Expected: BUILD SUCCEEDED；计数断言成功；diff 无输出；构建产物中的 65 份 Localizable.strings 全部 plutil OK。

- [ ] **Step 4: 最终审计**

~~~bash
git diff --check
git status --short
rg -n 'zh-Hans|zh-Hant|TokenWatch.languagePreference.*en([^A-Za-z-]|$)|periodNoTokenDataSuffix|chartTokenAccessibilitySuffix|chartCostAccessibilitySuffix' TokenWatch TokenWatchTests TokenWatchUITests -g '*.swift'
~~~

Expected: 除旧偏好迁移表及明确的系统语言解析测试外，不再有旧 locale 值；三个 suffix 旧名无匹配；工作树只包含计划内变更。若验证暴露问题，回到所属任务做最小修复并重跑该任务及本任务验证，不创建混合职责的“杂项修复”提交。

## Plan Self-Review

- [x] 65 个冻结 locale 在资源批次中恰好覆盖一次：现有 12 + 10 + 11 + 10 + 12 + 10 = 65。
- [x] 最终 key 数统一为 140：当前 139 + periodAxisValueName；三个 suffix 只是重命名，不增加数量。
- [x] Tasks 1–8 都有有效 RED、最小实现、验证和单一职责提交边界；Tasks 9–10 是验收闸门，不伪造失败。
- [x] 资源批次先落盘后激活 enum，任何中间提交都不会让用户看到依赖英文回退的新增 locale。
- [x] 没有 TODO、TBD、占位译文、伪代码文件或未决定接口。
- [x] 最终验证同时覆盖源码、运行时查找、app-hosted unit tests、UI tests 和构建产物。
