# 应用内语言切换设计

**日期**: 2026-06-24
**作者**: TokenWatch
**状态**: 设计已确认,待实现

## 背景与目标

TokenWatch 当前界面文案主要为中文硬编码。用户希望支持英文,并在应用内提供语言切换入口。入口放在设置页,形式为下拉列表,首批选项为 `跟随系统`、`中文`、`English`。后续会继续增加更多语言,因此本次设计需要避免把语言切换做成只适用于中英双语的临时结构。

本次目标:

- 在设置页新增语言下拉列表。
- 支持 `跟随系统`、`中文`、`English` 三种语言偏好。
- 语言切换后立即刷新主窗口、状态栏菜单、popover 和统计页文案。
- 将用户可见 UI 文案集中到可扩展的本地化入口,便于后续增加语言。

## 范围

### 本次包含

1. 新增应用语言偏好模型,持久化到 `UserDefaults`。
2. 新增集中式文案入口,覆盖当前主要用户可见 UI 文案。
3. 设置页新增语言下拉列表,选项来自语言偏好模型。
4. 切换语言后通过通知或观察机制刷新已创建的 UI 控件文案。
5. 覆盖主窗口侧边栏、设置页、总计页、时间窗口统计页、状态栏菜单、popover、图表标题、状态提示、授权提示和无数据提示。
6. 增加语言偏好、设置页和核心页面文案刷新测试。

### 本次不包含

- 新增除英文以外的其他语言。
- 本地化开发日志、测试名、代码注释或 fatalError 开发诊断文本。
- 本地化 provider 名称、模型名称、token 数、金额和系统符号名称。
- 改造扫描、解析、聚合、计费等数据逻辑。
- 新增第三方本地化库。

## 语言偏好设计

新增语言偏好枚举:

```swift
enum AppLanguagePreference: String, CaseIterable, Sendable {
    case system
    case zhHans
    case en
}
```

每个偏好提供:

- 持久化 key,用于 `UserDefaults`。
- 设置页展示名,展示名也按当前界面语言本地化。
- 实际语言解析结果,如 `system` 解析为 `zhHans` 或 `en`。

`跟随系统` 的解析规则:

1. 读取 `Locale.preferredLanguages` 的首选语言。
2. 语言码以 `zh` 开头时使用中文。
3. 语言码以 `en` 开头时使用英文。
4. 其他语言暂时回落到英文,避免系统语言不是中文时仍显示中文。

偏好保存到 `UserDefaults`。非法或缺失值回落到 `system`。

## 本地化入口

新增集中式文案入口,暂定为 `AppStrings`:

```swift
enum AppStrings {
    static func text(_ key: AppStringKey, language: AppLanguage) -> String
}
```

文案 key 使用稳定枚举,避免在 UI 层直接用字符串作为查找 key。首批语言包含 `zhHans` 和 `en`。运行时根据当前偏好解析出的实际语言返回文案。

需要本地化的文案类型:

- 导航:总计、最近 12 个月、最近 30 天、本日、设置。
- 设置页:标题、说明、通用访问权限、授权按钮、刷新全部数据、自动刷新间隔、语言。
- 自动刷新选项:30 秒、1 分钟、5 分钟、15 分钟、关闭自动刷新。
- 统计页:标题、副标题、Token 用量、费用、工具占比、模型占比、模型消耗、暂无模型数据。
- 状态文案:正在加载、需要授权、暂无 token 数据、部分数据仍在加载。
- 状态栏菜单:打开 TokenWatch、立即刷新、退出 TokenWatch。
- Popover:本月、本周、今日、日均、本日 token 消耗分档文案。
- 辅助功能与 tooltip:立即刷新、正在刷新、刷新总计数据、刷新用量数据、刷新本日 token 消耗。
- 图表与热力图辅助文字:月份标签、小时标签、其他、最近 22 周、图表 accessibility label。

## UI 设计

设置页新增一行语言设置,位于自动刷新间隔附近:

```text
语言  [ 跟随系统 ▼ ]
```

布局规则:

- 使用 `NSPopUpButton`,不使用分段按钮,为后续新增更多语言保留空间。
- 选项顺序固定为 `跟随系统`、`中文`、`English`。
- 选中项由 `AppLanguagePreference` 当前值驱动。
- 用户选择后立即保存偏好并触发界面刷新。
- 切换到英文时,同一个下拉列表展示 `System`、`Chinese`、`English`。
- 切换到中文时,展示 `跟随系统`、`中文`、`English`。

统计页面不增加额外语言控件,避免挤占图表和摘要区域。

## 运行时刷新

新增语言设置对象,暂定为 `AppLanguageSettings`。职责:

1. 读取和写入 `UserDefaults` 中的语言偏好。
2. 暴露当前实际语言。
3. 在偏好变化时发送通知或调用观察者。

已创建的控制器在 `viewDidLoad` 订阅语言变化,并在变化时重新应用静态文案:

- `ViewController` 刷新侧边栏表格和当前详情页标题。
- `SettingsViewController` 刷新自身标签、按钮和下拉列表选项。
- `TotalStatsViewController` 刷新标题、副标题、分区标题、按钮 tooltip 和状态文案。
- `MonthlyStatsViewController` 刷新标题、副标题、图表标题、饼图标题、按钮 tooltip 和状态文案。
- `StatusBarController` 重建右键菜单并刷新状态栏第二行文本。
- `StatusPopoverViewController` 刷新摘要卡标题、今日描述、按钮 tooltip 和 hover 文案。

刷新文案不得重新触发数据加载。数据 snapshot 保持不变,只重新渲染字符串。

## 状态处理

语言切换与现有数据状态组合时按以下规则处理:

- loading 状态保持当前 loading 图标与禁用状态,只替换 tooltip/accessibility 文案。
- 当前页面已有错误时,错误正文仍展示 provider 或系统返回的原文;通用包装文案本地化。
- 当前 hover 文案存在时,语言切换后用当前 snapshot 重新生成文案。
- 若系统语言变化而用户选择 `跟随系统`,下次应用启动按新系统语言解析。本次不监听系统语言运行时变化。

## 测试

新增或更新测试:

1. 语言偏好测试
   - 缺失值回落到 `system`。
   - 非法值回落到 `system`。
   - `system` 根据中文和英文系统语言解析正确。
   - 非中文非英文系统语言回落到英文。
2. 设置页测试
   - 语言下拉列表包含 `跟随系统`、`中文`、`English`。
   - 选择英文后保存偏好。
   - 语言切换后设置页标签和下拉列表选项刷新。
3. 页面文案测试
   - 侧边栏在英文下展示 `Total`、`Last 12 Months`、`Last 30 Days`、`Today`、`Settings`。
   - 总计页英文标题、说明、模型分区和状态提示正确。
   - 时间窗口页英文标题、说明、图表标题和状态提示正确。
   - 状态栏菜单英文菜单项正确。
   - Popover 英文摘要卡标题和今日描述正确。

## 影响面

| 文件 | 改动 |
|---|---|
| `TokenWatch/AppDelegate.swift` | 初始化或持有语言设置共享实例,必要时注入状态栏控制器 |
| `TokenWatch/ViewController.swift` | 设置页语言下拉列表、侧边栏文案刷新 |
| `TokenWatch/ViewControllers/TotalStatsViewController.swift` | 静态文案改为本地化并响应语言变化 |
| `TokenWatch/ViewControllers/MonthlyStatsViewController.swift` | 静态文案改为本地化并响应语言变化 |
| `TokenWatch/ViewControllers/StatusBarController.swift` | 状态栏菜单、标题第二行和刷新间隔文案本地化 |
| `TokenWatch/ViewControllers/StatusPopoverViewController.swift` | popover 摘要卡和今日描述本地化 |
| `TokenWatch/ViewControllers/MonthlyTokenChartBuilder.swift` | 周期标题、副标题、月份/小时标签本地化 |
| `TokenWatch/ViewControllers/MonthlyTokenChartView.swift` | 图表 accessibility label 和其他模型名本地化 |
| `TokenWatch/ViewControllers/MonthlyCostChartView.swift` | 图表 accessibility label 本地化 |
| `TokenWatch/ViewControllers/UsageSharePieChartView.swift` | 空状态和其他分组文案本地化 |
| `TokenWatch/ViewControllers/CalendarHeatmapBuilder.swift` | 热力图标题和星期标签本地化 |
| `TokenWatch/ViewModels/TokenStatsViewModel.swift` | 用户可见通用错误文案本地化 |
| `TokenWatch/Providers/UsageProvider.swift` | 授权面板用户可见文案本地化 |
| `TokenWatch/Services/SecurityScopedBookmarkManager.swift` | 授权 panel prompt 本地化 |
| `TokenWatchTests/...` | 新增语言设置和页面英文文案测试 |
| `TokenWatch.xcodeproj/project.pbxproj` | 添加新增源码和测试文件引用 |

## 验证命令

```bash
xcodebuild -project TokenWatch.xcodeproj -scheme TokenWatch -destination 'platform=macOS' -only-testing:TokenWatchTests/AppLanguageSettingsTests test
xcodebuild -project TokenWatch.xcodeproj -scheme TokenWatch -destination 'platform=macOS' -only-testing:TokenWatchTests/SettingsViewControllerTests test
xcodebuild -project TokenWatch.xcodeproj -scheme TokenWatch -destination 'platform=macOS' -only-testing:TokenWatchTests/TotalStatsViewControllerTests test
xcodebuild -project TokenWatch.xcodeproj -scheme TokenWatch -destination 'platform=macOS' -only-testing:TokenWatchTests/MonthlyStatsViewControllerTests test
xcodebuild -project TokenWatch.xcodeproj -scheme TokenWatch -destination 'platform=macOS' -only-testing:TokenWatchTests/StatusPopoverViewControllerTests test
xcodebuild -project TokenWatch.xcodeproj -scheme TokenWatch -destination 'platform=macOS' -only-testing:TokenWatchTests/StatusBarControllerTests test
xcodebuild -project TokenWatch.xcodeproj -scheme TokenWatch -destination 'platform=macOS' test
```

## 提交建议

实现提交使用:

```text
feat(i18n): 支持英文并新增语言切换
```
