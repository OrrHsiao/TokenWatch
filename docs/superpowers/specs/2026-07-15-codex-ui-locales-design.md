# 对齐 Codex UI 语言的本地化设计

**日期**：2026-07-15
**状态**：设计已确认，待实施计划
**范围基准**：本机 Codex/ChatGPT 桌面客户端 `26.707.72221`

## 背景

TokenWatch 当前通过 `AppLanguage`、`AppLanguagePreference` 和 `AppStrings` 实现应用内即时语言切换。现有 12 种语言均有完整译文，共覆盖 139 个 `AppStringKey`，不是依赖英文回退的占位实现。

OpenAI 的公开文档没有给出 Codex 桌面 UI 的完整语言清单。本次以本机当前客户端中实际供语言设置加载的资源为可复现基准：`en-US` 加 64 个非英语 locale，共 65 个 locale。该清单是本次功能冻结的产品范围，不作为 OpenAI 未来版本支持承诺。

### 基准证据

- [Codex 桌面应用手册](https://developers.openai.com/codex/app)未发布完整 UI 语言清单。
- 本机 `/Applications/ChatGPT.app/Contents/Info.plist` 标识 bundle 为 `com.openai.codex`，版本为 `26.707.72221`。
- 该版本 `app.asar` 的设置代码以 `en-US` 为默认语言，并加载 64 个非英语 UI 翻译包；General 设置中的语言选择器直接由这组资源构建。
- `native-menu-locales` 和 macOS `.lproj/InfoPlist.strings` 只覆盖原生菜单或 bundle 元数据，不作为 UI 语言选择器的数据源。

## 目标

- TokenWatch 的语言设置包含与基准一致的 65 个 locale，另保留“跟随系统”。
- 65 个 locale 都提供完整译文，不允许以英文回退冒充翻译完成。
- 继续支持应用内即时切换，切换语言不触发数据重新扫描或聚合。
- 继续使用当前从左到右布局，包括阿拉伯语、波斯语和乌尔都语。
- 保持当前数字、日期、金额、图表布局和页面结构，不借本次本地化扩展重做格式化或 UI。
- 把大量译文从 Swift 源码迁移到按 locale 拆分的标准 `.strings` 资源，保持现有 `AppStrings.text` 调用接口。

## 非目标

- 不实现 RTL 镜像、双向文本专项布局或 RTL 导航行为。
- 不新增语言搜索器、语言管理页面或在线下载语言包。
- 不迁移到 `.xcstrings`，不引入第三方本地化库。
- 不增加复数规则、`.stringsdict`、日期/数字/货币地区化改造。
- 不新增截图，不重做现有控件尺寸或布局。
- 不翻译开发日志、测试名、代码注释、provider 名称、模型名称和数据库字段。

## 冻结的 locale 清单

设置项为“跟随系统”加以下 65 个 locale。顺序固定为下列基准顺序，避免语言切换后菜单因本地化排序变化而跳动。

```text
en-US
am
ar
bg-BG
bn-BD
bs-BA
ca-ES
cs-CZ
da-DK
de-DE
el-GR
es-419
es-ES
et-EE
fa
fi-FI
fr-CA
fr-FR
gu-IN
hi-IN
hr-HR
hu-HU
hy-AM
id-ID
is-IS
it-IT
ja-JP
ka-GE
kk
kn-IN
ko-KR
lt
lv-LV
mk-MK
ml
mn
mr-IN
ms-MY
my-MM
nb-NO
nl-NL
pa
pl-PL
pt-BR
pt-PT
ro-RO
ru-RU
sk-SK
sl-SI
so-SO
sq-AL
sr-RS
sv-SE
sw-TZ
ta-IN
te-IN
th-TH
tl
tr-TR
uk-UA
ur
vi-VN
zh-CN
zh-HK
zh-TW
```

相较当前实现，新增 53 个可选 locale。现有 12 种语言映射到对应的新 locale，已有译文作为这些资源的初始内容。

## 语言模型

### `AppLanguage`

`AppLanguage` 成为唯一的具体语言清单，raw value 使用上述 BCP-47 locale code。每个语言提供：

- `localeIdentifier`：日期和星期等现有 formatter 使用的 locale。
- `resourceIdentifier`：对应 `<locale>.lproj` 目录。
- `nativeDisplayName`：使用该 locale 的 `Locale` 生成本地自称；系统无法生成时回退 locale code。
- 仅用于保留现有展示规则的语言族属性，例如 CJK 紧凑星期符号、标题与后缀之间是否插入空格。

语言族属性由规范化后的语言 code 推导，不为 65 个 case 编写重复 switch。

### `AppLanguagePreference`

语言偏好只表达两种状态：

```swift
enum AppLanguagePreference: Equatable, Sendable {
    case system
    case language(AppLanguage)
}
```

偏好列表由 `.system` 加 `AppLanguage.allCases` 生成。设置页不再维护第二份 65 case 枚举，也不再通过固定索引假定两份枚举顺序一致。

### 偏好持久化与兼容

继续使用 `TokenWatch.languagePreference`。新值保存 `system` 或精确 locale code。读取时兼容旧版本值：

| 旧值 | 新值 |
|---|---|
| `en` | `en-US` |
| `zh-Hans` | `zh-CN` |
| `zh-Hant` | `zh-TW` |
| `ja` | `ja-JP` |
| `ko` | `ko-KR` |
| `es` | `es-ES` |
| `de` | `de-DE` |
| `fr` | `fr-FR` |
| `pt-BR` | `pt-BR` |
| `it` | `it-IT` |
| `nl` | `nl-NL` |
| `pl` | `pl-PL` |

旧值在读取时按上表解析；下次保存时写入新值。未知值仍按 `.system` 处理。

## 翻译资源

每个 locale 使用独立资源：

```text
TokenWatch/Localization/Resources/<locale>.lproj/Localizable.strings
```

例如：

```text
TokenWatch/Localization/Resources/en-US.lproj/Localizable.strings
TokenWatch/Localization/Resources/es-419.lproj/Localizable.strings
TokenWatch/Localization/Resources/zh-HK.lproj/Localizable.strings
```

`AppStringKey` 改为以 case 名称作为 raw value。现有 Swift 字典迁移到对应 `.strings` 文件后删除，避免同时维护两套来源。

审计发现 `AppLanguage.periodAxisValueName` 是当前 139 个 key 之外的用户可感知辅助功能文案。为满足“完整译文”，它迁移为新的 `AppStringKey`。因此迁移后每个 locale 直接覆盖 140 个 key；139 是当前基线数量，不包含这条散落在 `AppLanguage` 中的文案。

为允许不同语言调整语序，下列当前“标题 + 后缀”的 key 改为完整格式字符串，但不增加 key 数量：

- `periodNoTokenDataSuffix` 改为 `periodNoTokenDataFormat`。
- `chartTokenAccessibilitySuffix` 改为 `chartTokenAccessibilityFormat`。
- `chartCostAccessibilitySuffix` 改为 `chartCostAccessibilityFormat`。

格式字符串使用 `%@`、`%d` 或带位置的 `%1$@`、`%2$d`。调用方继续使用 `String(format:)`，但不再假设所有语言都能通过英文式拼接得到正确语序。

## `AppStrings` 查找行为

对外保留：

```swift
AppStrings.text(_ key: AppStringKey, language: AppLanguage) -> String
```

内部查找顺序：

1. 从目标 locale 的 bundle 读取 key。
2. 目标资源或 key 缺失时，从 `en-US` 读取。
3. 英文仍缺失时返回 key raw value。

目标 bundle 缺失、资源不可解析或 key 缺失时记录简洁错误日志。完整性测试直接检查资源内容，不经过回退，因此正常构建不应触发这些分支。

主窗口、状态栏、菜单、popover 和图表继续通过现有 `AppStrings.text` 接口取值，不需要了解资源文件结构。

## 系统语言解析

`Locale.preferredLanguages` 中的标识先把 `_` 统一为 `-`，再进行大小写无关的规范化匹配。解析规则为：

1. 按系统偏好顺序逐项检查。
2. 优先匹配完整 locale。
3. 没有完整匹配时按语言族映射到受支持变体。
4. 当前项完全不支持时继续检查下一项。
5. 所有项都不支持时回退 `en-US`。

需要显式固定的地区规则：

- `zh-Hans` 和中国大陆中文映射 `zh-CN`。
- 香港、澳门繁体中文映射 `zh-HK`。
- 台湾及未指定地区的繁体中文映射 `zh-TW`。
- 西班牙映射 `es-ES`；拉丁美洲地区及 `es-419` 映射 `es-419`；未指定地区的 `es` 保持现有行为并映射 `es-ES`。
- 加拿大法语映射 `fr-CA`；其他法语映射 `fr-FR`。
- 葡萄牙映射 `pt-PT`；巴西及未指定地区的葡萄牙语映射 `pt-BR`，保留现有默认行为。
- 只有一个受支持变体的语言按 language code 匹配该变体。

## 运行时数据流

```text
用户选择语言
  -> AppLanguageSettings 保存精确 locale
  -> 同步通知现有观察者
  -> 各控制器使用同一数据 snapshot 重新应用 AppStrings
  -> 窗口、主菜单、状态栏和 popover 更新
```

语言变化不得触发 provider 扫描、SQLite 查询、文件解析、用量聚合或定价计算。选择“跟随系统”时继续沿用现有约定：应用启动时解析系统语言，不新增运行中监听系统语言变化。

## 既有展示规则

本次保持现有 LTR 和格式行为：

- 所有 locale 都维持当前 left-to-right 布局和左对齐策略。
- 阿拉伯语、波斯语和乌尔都语只替换文案，不镜像侧边栏、表格、菜单或图表。
- 数字、金额、百分比、token 缩写和日期格式保持现有实现。
- 已经显式使用 `language.localeIdentifier` 的月份和星期 formatter 会自然使用新增 locale。
- CJK 语言继续使用现有紧凑星期、月份换行和全角括号规则；其他新增语言使用当前非 CJK 默认规则。
- 不因长译文调整窗口、控件尺寸或页面布局。

## 翻译规范

所有译文以英文语义为基准，并复用现有 12 种语言中已经确认的表达。以下名称保持原文：

- `AI Token Watch`
- `Claude Code`
- `Codex`
- `opencode`
- `Token`
- `SQLite`
- provider 名称、模型名称、session ID 和数据库文件名

允许按目标语言调整词序、标点和大小写。地区变体分别维护完整资源，尤其包括 `es-419`/`es-ES`、`fr-CA`/`fr-FR`、`pt-BR`/`pt-PT`、`zh-CN`/`zh-HK`/`zh-TW`，不通过运行时别名让其中一个地区文件冒充另一个地区文件。

## 错误处理

- 缺少目标 `.lproj`：记录 locale，并回退 `en-US`。
- `.strings` 不能解析：构建验证失败；运行时记录资源错误并回退英文。
- 缺少目标 key：记录 locale 和 key，回退英文。
- 英文也缺少 key：返回 key raw value，使问题可见而不是展示空白。
- 非法持久化偏好：按 `.system` 处理。
- 系统返回未知 locale：继续检查下一个首选语言，最后回退 `en-US`。

不为这些静态资源错误增加弹窗或用户可见错误状态。

## 测试与验证

### 语言清单

- `AppLanguage.allCases` 的 locale code 与冻结的 65 项完全一致，无重复。
- `AppLanguagePreference` 列表为 `.system` 加 65 个语言项，共 66 项。
- 每个语言的资源标识和本地自称非空。

### 资源完整性

- 65 个 `.lproj` 目录和 `Localizable.strings` 都存在且可解析。
- 每个资源的 key 集合与全部 140 个 `AppStringKey` 完全一致。
- 测试直接解析目标资源，不调用带英文回退的 `AppStrings.text` 来判断完整性。
- 所有值非空，无重复 key，无残留 raw key 名称。
- 所有格式占位符的类型和数量与英文一致，允许使用位置参数调整顺序。
- 与英文完全相同的值必须属于产品名、技术术语或明确允许项；其余相同值作为未翻译内容使测试或审查失败。

### 偏好与系统解析

- 12 个旧偏好值均映射到指定新 locale。
- 精确地区、语言族、大小写、`_/-` 变体解析正确。
- 首个系统语言不支持、第二个支持时选择第二个。
- 中文、西班牙语、法语和葡萄牙语地区规则分别覆盖。
- 不支持的列表回退 `en-US`。

### UI 行为

- 语言切换后设置页、Dashboard、主菜单、状态栏和 popover 同步刷新。
- 刷新文案不增加数据加载次数。
- 从新增语言中抽取不同文字系统做组件测试，包括 `ar`、`hi-IN`、`th-TH`、`uk-UA`、`vi-VN`、`zh-HK`、`es-419` 和 `pt-PT`。
- 阿拉伯语等语言仍保持当前 LTR 布局，符合本次明确约束。

### 构建产物

- Debug build 成功。
- 完整单元测试和 UI 测试通过。
- 构建后的 App bundle 包含全部 65 个本地化资源目录。
- 项目 `knownRegions` 与资源 locale 保持一致。

构建和测试继续使用项目规则指定的 `.build/DerivedData`；app-hosted tests 在沙盒限制下申请提升权限运行。

## 预计影响文件

| 文件或目录 | 改动 |
|---|---|
| `TokenWatch/Localization/AppLanguage.swift` | 65 locale、偏好模型、旧值兼容、系统语言解析和语言族属性 |
| `TokenWatch/Localization/AppStrings.swift` | raw key、locale bundle 查找、英文回退和日志；移除内联译文字典 |
| `TokenWatch/Localization/Resources/` | 新增 65 份 `Localizable.strings` |
| `TokenWatch/ViewController.swift` | 设置下拉改为使用统一偏好列表 |
| `TokenWatch/ViewControllers/MonthlyTokenChartBuilder.swift` | 完整格式 key 与语言族规则 |
| `TokenWatch/ViewControllers/MonthlyBarChartStyle.swift` | 用语言族属性替代 12 case switch |
| `TokenWatch/ViewControllers/CalendarHeatmapBuilder.swift` | 用语言族属性替代 12 case switch |
| `TokenWatch.xcodeproj/project.pbxproj` | 打包本地化资源并更新 known regions |
| `TokenWatchTests/Localization/` | 语言清单、迁移、解析、资源和占位符完整性测试 |
| 现有控制器测试与 UI 测试 | 更新偏好构造方式并增加新增语言抽样 |

实际实施仅修改为完成上述行为所必需的文件；不顺带重构 provider、聚合、定价或其他 UI。

## 验收标准

1. 设置页显示“跟随系统”及 65 个具体 locale。
2. 每个 locale 都直接提供全部 140 个用户文案 key，不依赖英文回退完成验收。
3. 旧用户语言偏好保持等价选择。
4. 系统语言按明确地区规则解析，未知语言最终回退英文。
5. 切换任一语言会立即刷新全部现有 UI 表面，且不重新加载数据。
6. 所有语言保持当前 LTR 布局及现有格式化行为。
7. 完整测试通过，构建产物包含 65 份语言资源。

## 已接受的权衡

- 65 份完整资源会显著增加仓库体积，但按语言拆分比单个近万行 Swift 字典或巨型 `.xcstrings` 更易审阅。
- RTL 语言的阅读顺序不会达到原生 RTL 应用体验；这是用户明确接受的约束。
- 不引入复数规则意味着少数计数句式仍受现有单一格式模型限制；本次只保证完整翻译现有语义，不扩展语法系统。
- 本地客户端资源是本次冻结清单的依据；未来 Codex 增减语言不会自动改变 TokenWatch，需要单独评估和更新。
