# 状态栏当日 Token 数显示 — 设计稿

- 日期:2026-06-15
- 作者:OrrHsiao(brainstorming with Claude)
- 关联:`TokenStatsViewModel`、`AppDelegate`、`ViewController`

## 1. 范围与目标

在 macOS 状态栏(menu bar)长驻一个图标 + 文本,展示「今日所有 provider 累加的 token 数」,让用户无需打开主窗口就能掌握当日用量。

### 用户故事

- 打开 TokenWatch 后,状态栏出现一个图标 + 数字(`▣ 1.2M`),代表 Claude Code + Codex + OpenCode 当日 token 总和。
- 数字会自动定时刷新,无需手动操作。
- 点击图标弹出菜单,可以「打开主窗口」「立即刷新」「退出」。
- 即便没授权或某 provider 出错,状态栏也不会变得突兀,只静默显示已知数据。

### 非目标(本次不做)

- 状态栏不展示费用、不分 provider 显示。
- 不做 popover 详情(主窗口已能完成)。
- 不做 LSUIElement(纯状态栏应用)模式 — 保留 Dock 图标 + 主窗口。
- 不做文件系统事件驱动刷新(后续可选)。

## 2. 架构

新增 `StatusBarController`(`@MainActor`),持有 `NSStatusItem`,并和现有 `TokenStatsViewModel` 协作。

```
            AppDelegate (@MainActor)
                  │ 持有
                  ▼
         TokenStatsViewModel ────────────┐
                  │                       │
                  │ observe(handler)      │ loadAllStats() / loadStats(for:)
                  ▼                       │
         StatusBarController              │
              ├─ NSStatusItem (button: 图标 + 文本)
              ├─ NSMenu (打开主窗口 / 立即刷新 / 退出)
              └─ Timer (每 30s 触发 loadAllStats)
```

### 关键设计点

1. **数据源复用**:不重复实现扫描/聚合,直接用 `TokenStatsViewModel.states[*].stats?.byDay["YYYY-MM-DD"]`。今日 key 用 `Calendar.current` + `yyyy-MM-dd`,与 `UsageAggregator` 保持一致;把三个 provider 的 `inputTokens + outputTokens + cacheReadTokens + cacheCreationTokens` 累加。
2. **职责单一**:`StatusBarController` 只负责状态栏视觉与交互,**不**直接读 JSONL,**不**做聚合;数据计算在 `TokenStatsViewModel` 已有方法上做最小扩展。
3. **生命周期**:`AppDelegate` 在 `applicationDidFinishLaunching` 创建并强引用,在 `applicationWillTerminate` 显式停 Timer + 清 `NSStatusBar` item,避免 leak。
4. **状态变更联动**:订阅 ViewModel 的 observer 回调,任一 provider 状态变化即重算汇总文本。

## 3. ViewModel 多订阅改造

### 问题

`TokenStatsViewModel.onStateChange` 是单一闭包属性,目前已被 `ViewController` 占用。`StatusBarController` 也需要订阅,直接覆盖会让主窗口失去刷新通知。

### 决策:改为多订阅 API

API 改为:

```swift
struct ObservationToken: Hashable, Sendable { let id: UUID }

private var observers: [ObservationToken: @MainActor (ProviderID) -> Void] = [:]

@discardableResult
func observe(_ handler: @escaping @MainActor (ProviderID) -> Void) -> ObservationToken {
    let token = ObservationToken(id: UUID())
    observers[token] = handler
    return token
}

func removeObserver(_ token: ObservationToken) {
    observers.removeValue(forKey: token)
}

private func notifyStateChange(_ id: ProviderID) {
    for handler in observers.values { handler(id) }
}
```

`onStateChange` 属性整体删除(只有一个 caller),`ViewController` 同步迁移到 `observe`,在 `deinit` 调 `removeObserver`,无兼容层 — 与「不无意义重构」一致,因为这是给本 feature 让路的最小必要改动。

### 备选(未采纳)

- B. `StatusBarController` 由 `ViewController` 转发:状态栏强依赖 VC,主窗口关闭后转发链断。
- C. `NotificationCenter` 广播:引入新通知类型,序列化 ProviderID 不优雅。

## 4. 组件细节

### 4.1 状态栏文本格式

新增纯函数 `formatCompact(_ tokens: Int) -> String`:

| 区间 | 示例 |
|------|------|
| `0..<1_000` | `0` / `823` |
| `1_000..<1_000_000` | `1.2k` / `99.9k` / `823k`(>=100k 去小数) |
| `>=1_000_000` | `1.2M` / `9.9M` / `12M`(>=10M 去小数) |

显示规则:

- 图标用 `NSImage(named: "StatusBarIcon")`,asset 中已配置 Render As: Template Image,跟随状态栏深浅色自动反相。
- 文本随状态计算:
  - 所有 provider `needsAuthorization == true` → `—`
  - 任一 provider `isLoading == true` 且**当前没有任何已计算 stats** → `…`
  - 否则 → `formatCompact(sum of byDay[today] across all providers)`,出错或无数据的 provider 视作 0
- `button.title` 以单空格连接图标和数字。

### 4.2 刷新调度

```swift
private var refreshTimer: Timer?

func startTimer() {
    refreshTimer?.invalidate()
    let timer = Timer(timeInterval: 30, repeats: true) { [weak self] _ in
        Task { @MainActor in await self?.viewModel.loadAllStats() }
    }
    RunLoop.main.add(timer, forMode: .common)   // .common 保证菜单展开时也会触发
    refreshTimer = timer
}
```

要点:

- 间隔 **30 秒**,固定常量(下次需要再做配置面板)。
- 用 `RunLoop.common` 而非默认 mode,避免菜单弹出时被冻结。
- `applicationWillTerminate` 调 `refreshTimer?.invalidate()`,防止 Timer 持有 self。
- 「立即刷新」菜单项直接复用 `viewModel.loadAllStats()`,不重置 Timer 周期。

### 4.3 跨日切换

定时器内部检查「上次显示用的 day key」与当前 `today` 不同时,即使数据没变也强制重绘文本(避免跨过 0 点仍显示昨天的值)。

### 4.4 双模式 + 「打开 TokenWatch」行为

保留 `LSUIElement = NO`(默认),处理三种状态:

1. 主窗口可见 → `NSApp.activate(ignoringOtherApps: true)` + `mainWindow.makeKeyAndOrderFront(nil)`。
2. 主窗口已关闭(macOS 默认会留 process) → 通过 `NSApp.windows.first { $0.contentViewController is ViewController }` 重新 `orderFront`。
3. 没有窗口对象(罕见) → 不做事(不重新初始化 storyboard,后续再考虑)。

不引入 `applicationShouldHandleReopen`,只做菜单点击触发。

### 4.5 菜单结构

```
▣ 1.2M
─────────────────
打开 TokenWatch          ⌘0
立即刷新                  ⌘R
─────────────────
退出 TokenWatch           ⌘Q
```

- 菜单只在创建时构建一次,后续不变化(各 provider 明细 / 今日总费用 选项未启用)。
- key equivalent 用 `⌘0 / ⌘R / ⌘Q`,只在 status item 菜单生效,不影响主窗口快捷键。

### 4.6 状态栏图标资产

- 在 `Assets.xcassets` 新建 Image Set **`StatusBarIcon`**,提供 18×18 @1x、36×36 @2x、54×54 @3x。
- attribute inspector 设 **Render As: Template Image**(asset 层声明,代码不再 `isTemplate = true`)。
- 实际 PNG 文件由用户后续提供;PR 阶段先放一张灰阶占位图,主线代码不阻塞。

## 5. 文件落点

```
TokenWatch/
├── ViewControllers/
│   └── StatusBarController.swift        ← 新增
├── ViewModels/
│   └── TokenStatsViewModel.swift        ← 改:onStateChange → observe/removeObserver
├── ViewController.swift                 ← 改:迁移到 observe API,deinit 移除
├── AppDelegate.swift                    ← 改:创建 StatusBarController,terminate 时释放
└── Assets.xcassets/
    └── StatusBarIcon.imageset/          ← 新增 Image Set(Template Image)

TokenWatchTests/
├── ViewModels/
│   └── TokenStatsViewModelObserverTests.swift  ← 新增:多订阅 + remove
├── Util/
│   └── CompactNumberFormatterTests.swift       ← 新增:formatCompact 边界
└── ViewControllers/
    └── StatusBarTitleBuilderTests.swift        ← 新增:title 构建逻辑(纯函数)
```

> 把「计算 title 的纯逻辑」从 `StatusBarController` 中抽成独立的 `enum StatusBarTitleBuilder` 静态函数(输入 `[ProviderID: ProviderState] + todayKey`,输出 `String?`),便于在没有 `NSStatusItem` 的情况下做单元测试。

## 6. 错误处理

- **未授权**:文本降级为 `—`,不在状态栏弹任何 alert。
- **Bookmark 失效**:走 ViewModel 现有错误流;状态栏静默(失败 provider 视作 0,其它仍累加)。
- **Timer 漂移**:macOS 休眠唤醒后 Timer 会延迟,但不影响正确性(下次 fire 时完整重算)。
- **跨日**:见 4.3。
- **菜单弹出时数据更新**:`observe` 回调在 main actor,直接更新 `statusItem.button?.title` 不会和已展开 menu 冲突(menu 内容静态)。

## 7. 测试策略

| 测试 | 目标 |
|------|------|
| `CompactNumberFormatterTests` | `0`/`999`/`1_000`/`99_999`/`100_000`/`9_999_999`/`10_000_000` 等边界,Locale 中立 |
| `StatusBarTitleBuilderTests` | 全部未授权 → `—`;全部 loading 且无旧数据 → `…`;部分有 stats → 求和;跨日 today key 切换;某 provider `byDay[today] == nil` → 视作 0 |
| `TokenStatsViewModelObserverTests` | `observe` 返回不同 token;多 observer 同时收到通知;`removeObserver` 后不再收到 |
| 现有测试 | 全部仍通过(确认 `ViewController` 迁移没破坏行为) |

UI 层(Timer / NSStatusItem 实例化 / 菜单点击)不写自动化测试 — UI test bundle 启动状态栏 mock 成本高,人肉验收 + 单元覆盖纯逻辑足够。

## 8. 实现顺序

1. ViewModel 多订阅改造 + 单测 + 迁移 `ViewController`。
2. 抽 `StatusBarTitleBuilder` + `formatCompact` 纯函数 + 单测。
3. 新增 `StatusBarController`(Timer + NSStatusItem + Menu),`AppDelegate` 装配。
4. 添加 `StatusBarIcon` Image Set(占位 PNG,等用户给最终图)。
5. 人工验收:启动后看到图标 + 数字、定时刷新、菜单交互正常、跨日切换正常。
