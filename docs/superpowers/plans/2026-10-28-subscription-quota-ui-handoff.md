# Claude 开发交接：本地订阅额度

日期：2026-10-28。本文是开发入口和检查清单，具体设计以 [订阅额度设计](../specs/2026-10-28-subscription-quota-ui-design.md) 为准。

## 可直接交给 Claude 的任务

> 请先阅读项目根目录的 `CLAUDE.md` 和 `AGENT_GUIDE.md`，再阅读 `docs/superpowers/specs/2026-10-28-subscription-quota-ui-design.md`，实现已确认的 Claude / Codex 本地订阅额度功能。
>
> 视觉参考为 `docs/design/subscription-quota-ui/preview.html`，可编辑源为同目录 `preview.fragment.html`。预览中的原统计区使用已有截图，仅作样式参照；实现必须复用当前原生视图。
>
> 状态栏：圆环中尽量大的 Agent 图标居中，小号 5H / 7D 直接叠在图标同一中心，右侧显示剩余百分比。不要把图标和周期上下排列，也不要把图标缩小给文字让位。
>
> 左键弹窗：只在原内容上方新增订阅区。原今日描述、原刷新按钮、四个摘要卡片、热力图、小时趋势图和原背景样式全部保留。只允许原区域整体下移并增加弹窗总高度；不得缩图、缩字体、改颜色、圆角、描边、间距，也不得按旧示意图重画原区域。不要新增“用量概览”标题、页脚、第二个刷新按钮或标签页。
>
> Claude 读取用户授权的 `.claude.json` 中 `cachedUsageUtilization`；Codex 读取现有授权目录下 rollout JSONL 的 `token_count.rate_limits`。首版只读本地，不读取登录凭据，不联网，不接入 App Server。
>
> 为解析、缺失窗口、旧记录、跨重置点、账号隔离及增量更新补充必要测试。按项目规则优先用 Xcode MCP 构建、测试，并用同数据、同外观的前后截图证明原弹窗区域样式保持。先检查现有代码与测试，再做最小范围实现。

## 建议阅读的现有代码

| 文件 | 作用 |
|---|---|
| `TokenWatch/ViewControllers/StatusBarController.swift` | 菜单栏按钮、Popover 生命周期、鼠标与键盘行为 |
| `TokenWatch/ViewControllers/StatusBarTitleBuilder.swift` | 现有今日 token 文本及图标逻辑 |
| `TokenWatch/ViewControllers/StatusPopoverViewController.swift` | 当前 370 × 355pt 弹窗；原样式的权威来源 |
| `TokenWatch/ViewControllers/TodayHourlyTokenLineChartView.swift` | 已有小时趋势图，保持原样 |
| `TokenWatch/ViewModels/TokenStatsViewModel.swift` | 已有刷新与观察流程 |
| `TokenWatch/Providers/Claude/ClaudeProvider.swift` | Claude 数据目录接入 |
| `TokenWatch/Providers/Codex/CodexRecord.swift` | 目前只保留了 `rate_limits.limit_id`，需独立保留额度窗口 |
| `TokenWatch/Providers/Codex/CodexRolloutParsingState.swift` | token 用量去重，不应吞掉独立额度更新 |
| `TokenWatch/Providers/Codex/CodexRolloutParser.swift` | 已有增量解析和缓存流程 |
| `TokenWatch/Services/SecurityScopedBookmarkManager.swift` | 已有文件访问授权管理 |
| `TokenWatch/TokenWatch.entitlements` | App Sandbox 与用户选择文件只读权限 |
| `TokenWatch/Localization/AppStrings.swift` | 新文案沿现有本地化方式加入 |

## 实施顺序

1. **记录原界面基线**：固定演示数据和外观，保存原左键弹窗截图、370 × 355pt 尺寸与关键布局；不先调整原视图。
2. **完成本地读取**：小范围加入订阅快照模型、两个来源读取及 Claude 单文件 bookmark；复用既有 Codex 目录权限。
3. **接入更新流程**：额度与 token 消费独立，支持空 `info` 的额度事件、追加半行、原文件变化、账号隔离和缓存策略。来源时间始终来自快照。
4. **完成状态栏**：四个圆环、居中大图标与叠加小周期、固定百分比宽度、必要显示模式。保留原点击、高亮和关闭行为。
5. **只插入订阅区**：新增独立区块，原内容按原尺寸整体下移；新高度累加到原高度，不压缩原内容。
6. **验证**：解析和状态单测、原 token 统计回归、原生构建测试、新旧区域对照截图。

## 必须验证

- Claude 两层 `utilization` 路径、毫秒时间戳、ISO 8601 / `null` 重置时间。
- Codex 300 / 10080 分钟窗口、Unix 秒重置时间、跨文件按事件时间选择最新额度。
- primary / secondary 顺序变化不导致窗口误认；一个窗口缺失不吞掉另一个。
- 额度事件 `info == nil` 也可更新；已有 token 快照去重与成本结果保持。
- 0%、100%、小于 1% 的正剩余、未授权、未记录、旧记录、解析错误和跨重置点。
- 两 Agent 状态互不影响，账号 / 额度桶不混合；不记录凭据或完整配置。
- 新订阅数据失败不使原统计区被新增 loading / error 覆盖。
- 新旧截图对比：只存在新增订阅区、必要分隔线和原区域整体位移；原区域尺寸、字体、颜色、间距及交互保持。
- 浅深色、中文和英文、Retina 菜单栏的小号周期可辨认，数字变化不抖动。
- 用户未启用或没有订阅额度时，现有 token 统计继续可用。

本次交接不要求提交代码、创建 PR 或发布应用；这些操作按后续用户指令执行。
