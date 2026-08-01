# macOS 桌面图表小组件设计

- 日期：2026-07-15
- 目标平台：macOS 15+
- 关联：`StatusPopoverViewController`、`CalendarHeatmapBuilder`、`MonthlyTokenChartBuilder`、`TokenStatsViewModel`

## 1. 背景与目标

TokenWatch 当前在菜单栏左键 Popover 中展示近 22 周 Token 热力图和本日 24 小时 Token 折线图。本次新增两个可分别添加到 macOS 桌面的 Widget：

1. `Token 热力图`：展示最近 22 周每日 Token 用量强度。
2. `今日折线图`：展示本地自然日 0 至 23 时的 Token 用量趋势。

两个 Widget 均只支持系统中号尺寸，视觉样式沿用现有 Popover，但使用 WidgetKit 所需的纯 SwiftUI 实现。

成功标准：

- macOS 小组件库中能找到并分别添加两个 Widget。
- 两个 Widget 与 Popover 使用相同数据口径、时间范围、紧凑数字格式和核心视觉常量。
- 主应用刷新后，Widget 能读取一致的跨 Provider 快照。
- 主应用未运行时，Widget 显示最后一次有效快照，不自行扫描本地日志。
- 空数据、旧快照、损坏快照以及浅色/深色模式均有稳定表现。

## 2. 范围

### 2.1 本次包含

- 新增 Widget Extension 和 App Group 数据共享能力。
- 新增两个独立的静态 Widget configuration。
- 共享轻量、可版本化的 Codable 图表快照。
- 主应用刷新完成后发布快照并请求 WidgetKit 刷新。
- 纯 SwiftUI 热力图和 Swift Charts 折线图。
- 中号 Widget、浅色/深色模式和现有应用语言。
- 快照、存储、发布、Timeline 状态和图表数据的单元测试。

### 2.2 本次不包含

- 小号、大号或超大号 Widget。
- Provider、模型、项目、成本或时间范围配置。
- Widget 内手动刷新、hover、tooltip 或数据下钻。
- Widget Extension 直接读取安全作用域书签或扫描 Claude、Codex、OpenCode 数据。
- 共享完整 `AggregatedStats`、原始 `ParsedUsageEntry` 或日志内容。

## 3. 方案选择

采用“App Group + 渲染快照”方案。

主应用继续负责授权、扫描、解析和跨 Provider 聚合。所有 Provider 的一次全量刷新完成后，主应用使用现有 Builder 生成图表数据，再映射为轻量共享快照。Widget Extension 只读取并渲染该快照。

未采用的方案：

- 共享完整聚合树：会扩大 Codable 和 target membership 的影响面，并在 Extension 中重复日期、DST 和汇总逻辑。
- Widget 自行扫描日志：会重复重型工作，并引入安全作用域书签、沙盒权限和多进程一致性问题。

## 4. 工程结构

新增 `TokenWatchWidgets` Widget Extension，bundle identifier 使用 `com.xiaoao.tokenwatch.widgets`。Extension 内包含：

- `TokenWatchWidgetsBundle`：注册两个 Widget。
- `TokenHeatmapWidget`：热力图 configuration 和视图。
- `TokenHourlyLineWidget`：折线图 configuration 和视图。
- 共享的 `WidgetTimelineProvider`：读取共享快照并生成 Timeline entry。

主应用与 Extension 共同启用 App Group：

```text
group.com.xiaoao.tokenwatch
```

新增独立共享源码目录，由主应用和 Widget Extension 两个 target 同时编译。该目录只包含 Foundation 可用的 DTO、存储协议、紧凑格式化和颜色/图表常量，不依赖 AppKit、`TokenStatsViewModel` 或 Provider 实现。

主应用 target 内新增快照 Builder 和 Publisher。它们可以调用现有 `CalendarHeatmapBuilder`、`MonthlyTokenChartBuilder` 和应用本地化能力，但不进入 Extension target。

## 5. 共享快照

共享顶层模型 `WidgetUsageSnapshot` 的首版字段固定为：

```swift
struct WidgetUsageSnapshot: Codable, Equatable, Sendable {
    let schemaVersion: Int
    let generatedAt: Date
    let localDayKey: String
    let localizedText: WidgetLocalizedText
    let heatmap: WidgetHeatmapSnapshot
    let hourlyLine: WidgetHourlyLineSnapshot
}
```

嵌套模型的首版字段固定为：

- `WidgetLocalizedText`：`heatmapTitle`、`todayUsageTitle`、按快照日期预先格式化的 `datedUsageTitle`、`updatedThroughTitle` 和 `notReadyMessage`。
- `WidgetHeatmapSnapshot`：`totalTokens`、`maxDailyTokens` 和固定 154 个 `cells`。
- `WidgetHeatmapCell`：可选 `dateKey`、`totalTokens`、`intensity` 和 `isPlaceholder`。
- `WidgetHourlyLineSnapshot`：`dayKey`、`totalTokens`、`maxHourlyTokens` 和固定 24 个 `points`。
- `WidgetHourlyPoint`：`hour`、`hourKey`、`hourLabel`、`totalTokens` 和 `isCurrentHour`。

其中：

- `schemaVersion` 首版固定为 `1`，读取端拒绝未知版本。
- `generatedAt` 表示快照内容最后一次发生变化的时间。
- `localDayKey` 使用应用当前 Calendar 和时区生成，用于识别跨日旧快照。
- `localizedText` 保存按应用当前语言解析后的 Widget 标题、空态和日期文案；应用语言变化时重新发布。
- `WidgetHeatmapSnapshot` 保存 22 × 7 的日期/占位单元、窗口总量和最大日用量。
- `WidgetHourlyLineSnapshot` 保存固定 24 个墙上小时、今日总量、当日最大小时用量和当前小时标记。

快照只包含渲染需要的整数、日期 key、标签和状态，不包含路径、会话、模型明细或 Provider 错误文本。

热力图和折线图的 Token 口径均沿用 Popover 的 `UsageSummary.totalTokens`，即跨所有 Provider 汇总，并包含 input、output、cache 和 reasoning Token。

## 6. 数据生成与发布

`TokenStatsViewModel.loadAllStats()` 已等待 task group 内所有 Provider 加载结束。快照发布放在该等待点之后，避免并发刷新期间写入“新旧 Provider 混合”的中间状态。

发布流程：

```text
loadAllStats()
    → 并发刷新所有 Provider
    → 等待全部任务结束
    → 使用完整 states 构建两张图的快照
    → 与 App Group 中现有快照做语义比较
    → 内容、日期或语言有变化时原子写入
    → reload heatmap/hourly timelines
```

具体规则：

- 复用 `CalendarHeatmapBuilder` 的 22 周窗口、每日求和和 0 至 4 强度分档。
- 复用 `MonthlyTokenChartBuilder(period: .today)` 和 `LocalHourBucketDescriptor` 的固定 24 个墙上小时；DST 跳时和回拨日仍显示 00 至 23 共 24 个位置。
- 快照通过 App Group 容器内的 `widget-usage-v1.json` 保存，使用原子替换，避免 Extension 读取半写入数据。
- Publisher 通过协议注入 `TokenStatsViewModel`，ViewModel 不直接依赖 WidgetKit。
- 只有快照语义内容、日期或语言变化时才写入并调用 `WidgetCenter.shared.reloadTimelines(ofKind:)`，避免默认定时刷新产生无意义重载。
- 应用语言改变时，以当前内存 states 重新构建快照，无需重新扫描日志。
- 若至少一个 Provider 持有有效 `stats`，即使总 Token 为零也写入正常零值快照。
- 若所有 Provider 都没有有效 `stats`，保留磁盘上的最后有效快照；首次使用且没有旧快照时，由 Widget 显示未准备状态。

## 7. Timeline

两个 Widget 共用同一种 Timeline entry 数据结构和读取逻辑，但使用不同 Widget kind。

TimelineProvider 行为：

- `placeholder` 和小组件库预览使用固定、无用户数据的示例快照。
- `getSnapshot` 优先读取共享快照；缺失时返回未准备 entry。
- `getTimeline` 读取一次共享快照，并至少安排下一次本地午夜刷新，使旧快照标题及时从“今日”切换为具体日期。
- 主应用写入新快照后主动请求两个 kind 刷新；实际刷新时机仍由系统调度。
- TimelineProvider 不访问用户目录、不尝试恢复 bookmark，也不启动 Provider 扫描。

## 8. Widget 界面

### 8.1 通用规则

- 两个 Widget 都使用 `StaticConfiguration`，仅支持 `.systemMedium`。
- 使用系统 Widget container background 和默认内容边距。
- 使用系统语义前景色并适配浅色/深色模式。
- 数字沿用应用紧凑格式，例如 `99.9k`、`1.2M`。
- 点击 Widget 打开 TokenWatch 主应用。
- 不提供 hover、tooltip、刷新按钮、筛选或点击下钻。
- 提供清晰的 accessibility label，描述图表范围、总量和数据日期。

### 8.2 Token 热力图

布局：

- 顶部左侧显示“最近 22 周”，右侧显示窗口 Token 总量。
- 下方显示 22 列 × 7 行热力格。
- 格子尺寸依据 Widget 可用宽度计算，保持约 3pt 间距和 2pt 圆角。
- 未来/补齐位置透明，不显示星期标题、图例或格内文字。

颜色严格沿用现有 GitHub 风格浅色/深色五档调色板。颜色常量从当前 AppKit 实现提取为与 UI 框架无关的共享 RGBA 值，由 AppKit 和 SwiftUI 分别转换，避免两套颜色漂移。

### 8.3 今日折线图

布局：

- 顶部左侧显示“今日用量”，右侧显示今日 Token 总量。
- 图表显示 0 至 23 时固定 24 个点。
- X 轴仅显示 `0 / 6 / 12 / 18 / 23`，Y 轴保持约 3 个紧凑刻度。

样式沿用 Popover：

- 系统强调色、Catmull-Rom、2pt 折线。
- 当前小时显示强调色圆点。
- 折线下方使用热力图最高档绿色，从顶部 0.8 到底部 0.05 的渐变面积。
- 全零时使用稳定的非零 Y 轴域，显示平坦趋势，不产生 NaN 或布局跳动。

折线、面积、关键轴刻度和点大小等常量从现有实现提取为共享样式常量，现有 Popover 外观不得因此发生变化。

## 9. 空态、旧快照与错误处理

### 9.1 首次未准备

没有共享快照时，显示中性零值热力格或平坦折线，并提示“打开 TokenWatch 刷新数据”。该状态与“已加载但 Token 为零”明确区分。

### 9.2 已加载零数据

只要至少一个 Provider 成功产生 `stats`，即视为有效数据。总量为零时正常显示 `0`、零强度方格和零值折线，不显示授权或失败提示。

### 9.3 跨日旧快照

当 `localDayKey` 与当前本地日期不同：

- 保留最后有效图表，不清空数据。
- 折线标题改为快照对应日期的“日期用量”，不再称为“今日用量”。
- 热力图标题附加“更新至 M/d”。

### 9.4 读取和写入失败

- 文件缺失、JSON 损坏或 schema 不支持时，Extension 返回未准备 entry，不崩溃。
- 原子写入失败时不替换旧文件，也不请求 Timeline 刷新。
- 主应用和 Extension 使用 `Logger` 记录简洁的读取、版本和写入错误，不记录用户路径或原始用量明细。
- 部分 Provider 刷新失败时，现有内存 stats 仍可参与快照；没有任何有效 stats 时不覆盖旧快照。

## 10. 本地化与系统外观

- 有效快照的 Widget 内容语言跟随 TokenWatch 的应用语言设置，而不是独立读取 Extension 的 `UserDefaults.standard`。
- 快照保存已解析的 Widget 文案和小时标签；语言变更会触发重新发布与 Timeline 刷新。
- 首次尚无有效快照时，Extension 无法得知应用偏好，未准备提示使用系统语言；主应用产生首份快照后切换为应用语言。
- 日期格式使用对应语言和当前 Calendar/时区。
- 浅色/深色热力颜色与 Popover 一致；其余文本、背景和强调色使用系统语义样式。
- 系统可能根据桌面 Widget 渲染环境调整材质与对比度；设计保证信息层级和可读性，不绕过系统容器行为。

## 11. 测试策略

实现使用 Swift Testing，遵循失败测试 → 最小实现 → 全量回归。

### 11.1 快照 Builder

- 生成固定 154 个热力位置和 24 个墙上小时。
- 跨 Provider 日/小时 Token 正确相加。
- 缺失日期和小时补零。
- 强度映射为 0 至 4，最大日为最高档。
- DST 跳时和回拨日仍为 24 个唯一墙上小时位置。
- 当前小时、窗口总量、今日总量和应用语言标签正确。
- 没有有效 stats 与有效零数据能被区分。

### 11.2 Codable 与存储

- schema 1 编解码往返一致。
- 未知 schema、缺失文件和损坏 JSON 返回明确读取结果。
- 临时目录中的原子保存/读取往返一致。
- 写入失败不破坏旧文件。
- 语义未变化时不重复写入或刷新 Timeline。

### 11.3 发布与 Timeline 状态

- `loadAllStats()` 完成所有 Provider 后只发布一致快照，不发布中间状态。
- 部分失败时保留可用 stats；全无有效 stats 时保留旧快照。
- 语言变化使用当前 states 重新发布。
- 当前日、跨日旧快照和未准备 entry 生成正确标题与状态。
- 下一次 Timeline 刷新边界为下一个本地午夜。

### 11.4 UI 与工程验证

- 使用固定中号 frame 验证热力格数量、折线点数、关键轴标签和 accessibility 文案。
- 构建主应用、Widget Extension 和单元测试。
- 检查最终 App bundle 内嵌 Widget `.appex`。
- 检查主应用与 Extension 的签名 entitlement 都包含同一 App Group。
- 人工在桌面添加两个 Widget，检查浅色/深色、首次未准备、真实数据、全零和旧快照表现。

## 12. 签名与发布风险

- `group.com.xiaoao.tokenwatch` 必须在开发者账户中注册，并同时加入主应用和 Widget Extension 的签名能力与 provisioning profile。
- App Store/Release 构建需要同步更新 Extension bundle identifier、App Group 和嵌入配置；仅 Debug 本地可运行不能替代 Release 签名验证。
- WidgetKit 的刷新是系统调度，`reloadTimelines` 是刷新请求而非实时执行保证；产品文案不得承诺秒级同步。

## 13. 预计影响面

| 区域 | 改动 |
| --- | --- |
| `TokenWatch.xcodeproj` | 新增 Widget target、product、依赖、嵌入阶段和签名配置 |
| 主应用 entitlement | 新增 App Group |
| Widget entitlement | 新增 App Sandbox/App Group |
| 共享源码 | DTO、存储、格式化、图表视觉常量 |
| 主应用 | 快照 Builder、Publisher、刷新完成和语言变化接入 |
| Widget Extension | Bundle、两个 Widget、TimelineProvider、两个 SwiftUI 图表视图 |
| 现有图表 | 改为读取共享视觉常量，保持当前视觉不变 |
| 单元测试 | Builder、Codable、存储、发布、Timeline 和布局测试 |

## 14. 提交拆分建议

实现阶段保持单一职责，建议至少拆分为：

1. `test(widget): 添加共享快照与存储失败测试`
2. `feat(widget): 添加共享快照存储与发布`
3. `test(widget): 添加图表数据与 Timeline 测试`
4. `feat(widget): 新增热力图与折线图桌面小组件`
5. `chore(widget): 配置 App Group、Extension 嵌入与发布签名`
