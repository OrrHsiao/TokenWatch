# WidgetKit 桌面小组件设计

- 日期:2026-06-27
- 关联:`StatusPopoverViewController`、`CalendarHeatmapBuilder`、`MonthlyTokenChartBuilder`、`TokenStatsViewModel`

## 1. 范围与目标

新增 macOS 系统 WidgetKit 桌面小组件,让用户可以在桌面或通知中心直接查看 TokenWatch 的核心趋势:

- 一个近 22 周 token 热力图 widget。
- 一个今日 0 点到 23 点 token 用量折线图 widget。
- 图表视觉参考状态栏左键 popover 里的热力图和今日折线图。
- 主 App 负责读取 provider 数据、聚合统计并写入 App Group 快照。
- Widget Extension 只读取快照并渲染,不直接扫描用户目录。

不在本次范围:

- Widget 内授权用户目录。
- Widget 内 provider、模型、项目筛选。
- 点击小组件打开具体小时或日期详情。
- 成本图、饼图或其它主窗口图表。
- 改造现有 provider 扫描、解析和聚合口径。

## 2. 方案选择

推荐方案:新增 `TokenWatchWidgets` WidgetKit Extension,包含两个 widget kind,主 App 通过 App Group JSON 快照向 widget 供数。

备选方案:

1. Widget Extension 自己读取 provider 文件并聚合。优点是扩展数据独立;缺点是 WidgetKit 刷新时机不适合做重 IO,并且 security-scoped bookmark、沙盒授权和后台扫描成本都更复杂。
2. 主 App 生成 PNG 图表,Widget 只展示图片。优点是视觉最容易和 popover 完全一致;缺点是暗黑模式、尺寸适配、可访问性和清晰度都更弱,后续扩展也笨重。
3. 主 App 写结构化快照,Widget 用 SwiftUI/Charts 渲染。优点是符合 WidgetKit 模型,避免重复扫描本地文件,并保留动态尺寸和系统外观适配;缺点是需要维护一个共享快照模型和 App Group 存取层。

采用第 3 个方案。

## 3. Target 与工程结构

新增 target:

- `TokenWatchWidgets`: WidgetKit Extension。

新增目录建议:

```text
TokenWatchShared/
├── WidgetSnapshot.swift
└── WidgetSnapshotStore.swift

TokenWatchWidgets/
├── TokenWatchWidgetsBundle.swift
├── TokenWatchHeatmapWidget.swift
├── TokenWatchTodayLineWidget.swift
├── TokenWatchWidgetTimelineProvider.swift
├── TokenWatchHeatmapWidgetView.swift
├── TokenWatchTodayLineWidgetView.swift
└── Assets.xcassets
```

`TokenWatchShared` 放主 App 与 Widget Extension 都需要编译的纯 Swift 类型,不得 import AppKit。该目录包含:

- `WidgetSnapshot`: `Codable` 数据模型。
- `WidgetSnapshotStore`: 读写 App Group JSON 文件。
- 轻量格式化辅助,例如 token compact 文案。
- SwiftUI 可用的颜色 token,与现有热力图调色板保持一致。

`TokenWatchWidgets` 放 WidgetKit 入口、timeline provider 和 SwiftUI 视图。

## 4. App Group 与快照文件

使用 App Group 共享 JSON 快照。group identifier 建议为:

```text
group.com.xiaoao.TokenWatch
```

快照文件建议:

```text
<AppGroupContainer>/WidgetSnapshots/latest.json
```

`WidgetSnapshotStore` 行为:

- 写入时先编码到临时文件,再原子替换 `latest.json`。
- 读取失败、文件缺失或 JSON 损坏时返回空状态,Widget 不崩溃。
- 对外暴露注入式 `FileManager` / container URL provider,便于单元测试。
- 主 App 写入后调用 `WidgetCenter.shared.reloadAllTimelines()`。

## 5. 数据模型

Widget 专用快照与 AppKit 视图模型解耦,只保留展示所需字段:

```swift
struct TokenWatchWidgetSnapshot: Codable, Equatable, Sendable {
    let generatedAt: Date
    let languageIdentifier: String
    let status: TokenWatchWidgetDataStatus
    let heatmap: TokenWatchWidgetHeatmapSnapshot
    let todayLine: TokenWatchWidgetTodayLineSnapshot
}
```

状态:

- `.ready`: 有可展示数据。
- `.needsAuthorization`: 主 App 未获得用户目录授权。
- `.empty`: 已授权但没有 token 数据。
- `.stale`: 读取到旧快照但主 App 长时间未刷新。该状态可通过 `generatedAt` 派生,无需单独持久化也可以。

热力图字段:

- `title`: 例如“近 22 周”。
- `summary`: month/week/today/averageDaily tokens。
- `cells`: 固定 22 * 7 个单元,包含 placeholder/day、dateKey、totalTokens、intensity、isToday、isFuture。
- `maxDailyTokens`。

今日折线字段:

- `totalTokens`。
- `maxHourlyTokens`。
- `currentHourKey`。
- `buckets`: 固定 24 个小时桶,包含 hourKey、hourLabel、totalTokens、normalizedHeight、isCurrentHour。

转换入口放在主 App 侧,例如 `WidgetSnapshotBuilder.build(states:now:calendar:language:)`:

- 热力图复用 `CalendarHeatmapBuilder.build(...)`。
- 今日折线复用 `MonthlyTokenChartBuilder.build(period: .today, ...)`。
- token 口径沿用 `UsageSummary.totalTokens`。
- 未授权、加载中、错误状态从 `TokenStatsViewModel.ProviderState` 折算为 widget 的轻量状态。

## 6. 主 App 写入时机

主 App 在统计状态稳定后写快照:

- 启动自动加载完成后写入。
- 用户点击状态栏 popover 或主菜单刷新完成后写入。
- 用户在单个 provider 页面刷新完成后写入。
- 单个 provider 状态变化时可以延迟合并写入,避免并发刷新时多次触发 Widget reload。

推荐实现:

- 在 `TokenStatsViewModel.loadAllStats()` 的 task group 完成后调用一次快照写入。
- 在 `TokenStatsViewModel.loadStats(for:)` 单个 provider 完成后也触发发布,但由发布器合并同一轮刷新中的重复请求。
- 在 `requestAuthorization(for:)` 成功并加载完成后同样会通过 `loadAllStats()` 写入。
- 对外保留一个 `WidgetSnapshotPublisher` 小组件发布器,集中负责 build、store、reload timeline 和日志。

日志:

- 成功写入时记录生成时间和快照状态。
- 写入失败时记录错误,不影响主 App 正常展示。
- `WidgetCenter.shared.reloadAllTimelines()` 只负责通知系统刷新时间线,不作为主 App 数据加载成功与否的判据。

## 7. Widget Timeline

两个 widget 可以共用一个 timeline provider,读取同一份最新快照:

- `placeholder`: 使用静态示例数据,便于系统预览。
- `getSnapshot`: 优先读取真实快照,缺失时用空状态。
- `getTimeline`: 读取最新快照并生成一个 entry,下一次刷新建议为 15 到 30 分钟后。

WidgetKit 不能保证实时刷新,所以 UI 需要展示快照更新时间:

- 小尺寸只在空间允许时显示相对更新时间。
- 中/大尺寸显示“更新于 HH:mm”。
- 若 `generatedAt` 超过阈值,显示淡化的“数据可能不是最新”提示。

## 8. 热力图 Widget UI

视觉要求:

- 绿色阶梯色沿用 `CalendarHeatmapGitHubPalette` 的明暗模式色值。
- 网格维持 22 列 * 7 行,单元间距按 widget 尺寸缩放。
- 今日单元加轻量描边或更高对比边框。
- 不使用额外装饰卡片;遵守系统 widget 背景和 `containerBackground`。

尺寸适配:

- `.systemSmall`: 显示标题、今日 token、热力图网格。摘要压缩为 1 个重点数字。
- `.systemMedium`: 显示标题、更新时间、月/周/今日/日均摘要和完整网格。
- `.systemLarge`: 使用更舒展的摘要和网格,可增加简短图例。

空状态:

- `needsAuthorization`: 显示“打开 TokenWatch 完成授权”。
- `empty`: 显示“暂无 token 数据”。
- 读取失败: 显示“等待 TokenWatch 刷新”。

## 9. 今日折线图 Widget UI

视觉要求:

- 使用 Swift Charts 渲染 `AreaMark` + `LineMark` + 当前小时 `PointMark`。
- 面积渐变使用热力图最高强度绿色,透明度参考 popover 现有折线图。
- 折线使用系统 accent color。
- 全零数据保持稳定 y 轴域,不出现 NaN 或布局跳动。
- 不实现 hover,因为系统桌面小组件没有状态栏 popover 那种鼠标悬停交互。

尺寸适配:

- `.systemSmall`: 显示今日总 token、迷你折线和更新时间。
- `.systemMedium`: 显示 24 小时折线、关键横轴 `0/6/12/18/23`、今日总量。
- `.systemLarge`: 显示更完整纵轴、关键摘要和更宽松折线图。

空状态与热力图 widget 保持一致。

## 10. 本地化与格式化

Widget 快照记录 `languageIdentifier`,Widget 渲染时优先按快照语言展示文案。原因是 Widget Extension 读取不到主 App 内存里的 `AppLanguageSettings`,而主 App 写快照时知道当前语言。

初期文案:

- 复用 `AppStrings` 对应语言文本时,需要将必要字符串抽到 shared 层或在 widget 中维护最小文案表。
- token 数继续使用紧凑格式,与 `CompactNumberFormatter` 结果一致。
- 小组件内避免长句,保证小尺寸不截断关键数字。

## 11. 测试策略

单元测试:

1. `WidgetSnapshotBuilderTests`
   - 从 provider states 构建 ready 快照。
   - 未授权状态映射为 `needsAuthorization`。
   - 无数据映射为 `empty`。
   - 热力图 cells 数量固定为 154。
   - 今日小时 buckets 数量固定为 24。
2. `WidgetSnapshotStoreTests`
   - 能写入并读取 JSON。
   - 缺失文件返回空状态。
   - 损坏 JSON 不崩溃。
   - 写入使用可注入临时目录。
3. Widget view/debug tests
   - 热力图不同尺寸选择正确布局分支。
   - 折线图全零数据稳定。
   - 空状态文案按状态展示。
4. `TokenStatsViewModel` 或发布器测试
   - `loadAllStats()` 完成后触发一次快照发布。
   - `loadStats(for:)` 完成后触发发布,并避免全量刷新时为每个 provider 立刻重复 reload timeline。
   - 发布失败不会改变 provider state。

验证命令:

```bash
xcodebuild -project TokenWatch.xcodeproj -scheme TokenWatch -destination 'platform=macOS' -only-testing:TokenWatchTests test
xcodebuild -project TokenWatch.xcodeproj -scheme TokenWatch -configuration Debug build
```

如果新增独立 Widget scheme,额外运行:

```bash
xcodebuild -project TokenWatch.xcodeproj -scheme TokenWatchWidgetsExtension -configuration Debug build
```

## 12. 风险与处理

- App Group 配置错误:通过 store 测试和实际 build 验证 container URL 可用;Widget 空状态兜底。
- Widget 数据不是实时:展示更新时间,主 App 刷新后主动 reload timelines。
- Widget Extension 重复依赖 AppKit 文件:共享层只放 Foundation/SwiftUI 兼容类型,避免 import AppKit。
- Xcode 工程手动 target 配置复杂:使用现有 filesystem-synchronized group 风格,但 Widget target、extension product、embed app extension build phase 必须明确加入 project。
- 小尺寸文字拥挤:小尺寸只保留关键数字和图形,中/大尺寸再显示摘要。
- 主 App 刷新期间多次写快照:集中在发布器中节流或仅在 `loadAllStats()` 完成后写一次。

## 13. 影响面

| 文件或目录 | 改动 |
|---|---|
| `TokenWatchShared/` | 新增 Widget 快照模型、store、共享格式化和颜色 |
| `TokenWatchWidgets/` | 新增 WidgetKit Extension 入口、timeline provider 和两个 widget 视图 |
| `TokenWatch/ViewModels/TokenStatsViewModel.swift` | 刷新完成后触发快照发布 |
| `TokenWatch/AppDelegate.swift` | 启动流程间接受益于刷新后发布快照,必要时注入 publisher |
| `TokenWatch.xcodeproj/project.pbxproj` | 新增 Widget target、产品、embed extension、共享源码 target membership 和 App Group 设置 |
| `TokenWatchTests/` | 新增快照 builder/store/publisher 和 widget 视图相关测试 |

## 14. 提交建议

实现提交建议拆分:

```text
feat(widget): 新增桌面小组件共享快照
feat(widget): 添加热力图桌面小组件
feat(widget): 添加今日 token 折线图小组件
```
