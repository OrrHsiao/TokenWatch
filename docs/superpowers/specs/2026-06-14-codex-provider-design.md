# Codex Provider 接入设计

**日期**: 2026-06-14
**目标**: 在现有 Claude Code 统计能力之上,接入 OpenAI Codex CLI / Codex Desktop 的 token 用量统计;同时把多 provider 抽象层立起来,为后续 Gemini CLI 等数据源铺路。

## 背景

TokenWatch 目前完整支持 Claude Code(扫描 `~/.claude/projects/`,按 `message.id` 去重,内置 LiteLLM 价位)。Phase 8 计划列出的「支持更多数据源(Codex, Gemini CLI 等)」是接下来的重点。

参考方案:

- **ccusage** (`/rust/crates/ccusage/src/adapter/`):每个 provider 独立 `paths.rs / parser.rs / loader.rs / report.rs`,对外暴露统一 row 形态;聚合、定价、渲染共享。
- **TokenTracker** (`/src/lib/codex-rollout-parser.js` + `rollout.js`):per-provider 增量解析,但聚合层耦合(`rollout.js` 直接调具体函数)。

我们采纳 ccusage 的 **Parser-level adapter** 边界:provider 只负责扫描 + 解析,后续 PricingEngine / UsageAggregator / ViewModel 全部共享。

## Codex 数据格式速查

```
~/.codex/sessions/YYYY/MM/DD/rollout-<TIMESTAMP>-<UUID>.jsonl
~/.codex/archived_sessions/...                              # 同名时 sessions/ 优先
```

每行一个事件,关键 type:

| type | payload 关键字段 | 用途 |
|------|------------------|------|
| `session_meta` | `id` / `cwd` / `model_provider` | 会话元数据 |
| `turn_context` | `model`(如 `gpt-5.5`) | 模型切换;后续 `token_count` 归属此 model |
| `event_msg` (`payload.type=token_count`) | `info.last_token_usage` / `info.total_token_usage` | **唯一 token 来源** |

`token_count.info` 例:

```json
{
  "total_token_usage": {"input_tokens": 79149, "cached_input_tokens": 41216,
                       "output_tokens": 1150, "reasoning_output_tokens": 804,
                       "total_tokens": 80299},
  "last_token_usage":  {"input_tokens": 41071, "cached_input_tokens": 37760,
                       "output_tokens": 443,  "reasoning_output_tokens": 288,
                       "total_tokens": 41514},
  "model_context_window": 258400
}
```

注意点(参考 ccusage / TokenTracker 共识):

1. `input_tokens` **包含** `cached_input_tokens` — 计费时需扣减,避免双计。
2. `output_tokens` **已包含** `reasoning_output_tokens` — `reasoning_*` 仅作展示,不单独计费。
3. `last_token_usage` 偶尔缺失 → 用 `total_token_usage - 上一条 total` 增量推导(`saturating_sub`)。
4. 4 维全 0 的事件视为 replay marker / 心跳,跳过。
5. 没有 `message.id`,合成 `(sessionId, timestamp)` 作为 dedup key。

## 架构

### 目录结构变更

```
TokenWatch/
├── Providers/                       # 新增抽象层
│   ├── ProviderID.swift             # enum: claude / codex (将来扩 gemini)
│   ├── UsageProvider.swift          # protocol
│   ├── ProviderRegistry.swift       # 静态注册表
│   ├── Claude/
│   │   ├── ClaudeProvider.swift     # UsageProvider 实现 — 装配现有 Scanner+Parser
│   │   ├── ClaudeRecord.swift       # ← 从 Models/ 迁入
│   │   ├── ClaudeMessage.swift      # ← 从 Models/ 迁入
│   │   ├── ClaudeJSONLScanner.swift # ← 从 Services/JSONLScanner.swift 迁入并改名
│   │   └── ClaudeJSONLParser.swift  # ← 从 Services/JSONLParser.swift 迁入并改名
│   └── Codex/
│       ├── CodexProvider.swift
│       ├── CodexRecord.swift        # session_meta / turn_context / event_msg
│       ├── CodexRolloutScanner.swift
│       └── CodexRolloutParser.swift
├── Models/
│   ├── ParsedUsageEntry.swift       # +provider 字段
│   ├── TokenUsage.swift             # 不变
│   ├── UsageAggregation.swift       # 不变
│   └── ModelPricing.swift           # 不变
├── Pricing/
│   ├── PricingTable.swift           # +OpenAI/GPT-5 系列
│   ├── PricingEngine.swift          # 不变
│   └── LiteLLMPriceCatalog.swift    # 不变
├── Analytics/
│   └── UsageAggregator.swift        # 不变
├── Services/
│   └── SecurityScopedBookmarkManager.swift   # 改造为多 key
├── ViewModels/
│   └── TokenStatsViewModel.swift    # 改为按 provider 维护状态
├── ViewControllers/                 # 新增
│   ├── ProviderStatsViewController.swift  # 单 provider 视图(承担原 ViewController 职责)
│   └── (Main 视图改为 NSTabViewController)
└── ViewController.swift             # 重构为 NSTabViewController 容器
```

> 现有 Claude 相关代码迁入 `Providers/Claude/` 时只重命名,**不改逻辑**;现有 47 个 Claude 测试在迁移后保持全绿。

### 核心抽象

```swift
enum ProviderID: String, Sendable, CaseIterable, Hashable {
    case claude
    case codex
}

protocol UsageProvider: Sendable {
    var id: ProviderID { get }
    var displayName: String { get }
    var bookmarkKey: String { get }            // UserDefaults 持久化键
    var defaultDirectoryPath: String { get }    // "~/.claude" / "~/.codex"
    var openPanelMessage: String { get }
    var hasCacheWriteDimension: Bool { get }    // UI 用,Codex=false

    func loadEntries(from rootURL: URL) throws -> [ParsedUsageEntry]
}

enum ProviderRegistry {
    static let allProviders: [any UsageProvider] = [
        ClaudeProvider(),
        CodexProvider(),
    ]
    static func provider(for id: ProviderID) -> (any UsageProvider)?
}
```

`ParsedUsageEntry` 加 `provider: ProviderID`(不影响现有 dedupKey 算法,Codex 用合成 key)。

### Codex 解析流水线

```
~/.codex/sessions/YYYY/MM/DD/rollout-*.jsonl
        │
        ▼
CodexRolloutScanner.scanAll(in: codexRoot) -> [CodexFileInfo]
  ├─ 递归扫 sessions/ 与 archived_sessions/(sessions/ 优先,按相对路径去重)
  └─ url / sessionID(从文件名 UUID 推断,fallback 文件首行 session_meta.id)
        │
        ▼
CodexRolloutParser.parseFile(_ fileInfo) -> [ParsedUsageEntry]
  ├─ FileHandle 64KB 流式读取(复用 Claude 那套缓冲模式)
  ├─ 状态机:
  │    var currentModel: String? = nil
  │    var sessionCwd: String? = nil
  │    var previousTotals = (in:0, cached:0, out:0, reasoning:0)
  ├─ session_meta 行 → 更新 sessionCwd / sessionID
  ├─ turn_context 行 → 更新 currentModel
  └─ event_msg(token_count) 行:
       1. delta = info.last_token_usage
                ?? saturatingSub(info.total_token_usage, previousTotals)
       2. previousTotals = info.total_token_usage(永远更新,即便跳过本条)
       3. 若 delta 4 维全 0 → 跳过
       4. 若 currentModel == nil → 跳过(无法计价)
       5. pure_input = max(0, delta.input - delta.cached_input)
       6. emit ParsedUsageEntry(
              provider: .codex,
              messageId: "\(sessionID):\(timestamp.iso8601)",
              requestId: nil,
              sessionID, timestamp, model: currentModel!, cwd: sessionCwd,
              usage: TokenUsage(
                  inputTokens: pure_input,
                  cacheReadInputTokens: delta.cached_input,
                  outputTokens: delta.output,        // 已含 reasoning,共享 PricingEngine
                  cacheCreationInputTokens: 0,
                  cacheCreation: .zero,
                  speed: ""))
        │
        ▼
parseAllFiles → 按 dedupKey 取 magnitude 最大那条(沿用现有逻辑)
        │
        ▼
PricingEngine + UsageAggregator(零修改,共享)
        │
        ▼
TokenStatsViewModel.states[.codex] = ProviderState(stats: ...)
```

### ViewModel 改造

```swift
@MainActor
final class TokenStatsViewModel: Sendable {
    struct ProviderState: Sendable {
        var stats: AggregatedStats?
        var isLoading = false
        var errorMessage: String?
        var needsAuthorization = true
    }

    private(set) var states: [ProviderID: ProviderState] = [:]
    var onStateChange: (@MainActor (ProviderID) -> Void)?

    func loadStats(for: ProviderID) async
    func requestAuthorization(for: ProviderID) async
    func loadAllStats() async                  // 启动时并发触发各 provider
}
```

### Bookmark 多 key 改造

```swift
@MainActor
final class SecurityScopedBookmarkManager: Sendable {
    func hasBookmark(forKey: String) -> Bool
    func restoreBookmarkAndAccess(forKey: String) -> URL?
    func stopAccessing(forKey: String)
    func promptUserToSelectDirectory(forProvider: any UsageProvider) async -> URL?
}
```

内部用 `[String: (cachedURL: URL?, isAccessing: Bool)]` 区分。Claude 旧 key `"ClaudeDirectoryBookmark"` 保留兼容。

### Sandbox 配置

`TokenWatch.entitlements` 已是 `com.apple.security.files.user-selected.read-only`,Codex 目录走同一个权限,**无需改 entitlements**。用户首次进入 Codex Tab 时弹 NSOpenPanel 选择 `~/.codex`。

### UI(Tab 独立展示)

`Main.storyboard` 的根 ViewController 替换为 `NSTabViewController`,代码方式装配:

```swift
ViewController(NSTabViewController)
├── TabViewItem("Claude Code") → ProviderStatsViewController(.claude)
└── TabViewItem("Codex")        → ProviderStatsViewController(.codex)
```

`ProviderStatsViewController` 由原 `ViewController` 重构而来,接收一个 `ProviderID` 参数,只渲染该 provider 的 state。Codex 的本日块把 `Cache:` 行替换为 `Cached: <cached_input_tokens>`(因为 Codex 没有 cache write 概念)— 通过 `UsageProvider.hasCacheWriteDimension` 控制。

### 拓展性验证(假设接 Gemini)

新增 Gemini 只需:
1. `Providers/Gemini/` 实现 `GeminiProvider` + Scanner + Parser + Record。
2. `ProviderID` 加 case,`ProviderRegistry.allProviders` 加一行。
3. `PricingTable` 加 Gemini 系列条目。
4. UI 自动多出 Tab(`ViewController` 遍历 `ProviderRegistry.allProviders` 生成)。

不需要改 Aggregator / PricingEngine / Bookmark Manager / 现有 provider 代码。

## 数据模型

### Codex JSONL → Decodable 结构

```swift
struct CodexRecord: Decodable {
    let timestamp: Date?
    let type: String           // session_meta / turn_context / event_msg / response_item ...
    let payload: CodexPayload?
}

enum CodexPayload {
    case sessionMeta(SessionMeta)
    case turnContext(TurnContext)
    case eventMsg(EventMsg)
    case unknown                // 其他 type 一律忽略
}

struct SessionMeta: Decodable { let id: String; let cwd: String?; let modelProvider: String? }
struct TurnContext: Decodable { let model: String? }
struct EventMsg: Decodable {
    let type: String           // 只关心 "token_count"
    let info: TokenCountInfo?
}
struct TokenCountInfo: Decodable {
    let lastTokenUsage:  CodexTokenCounts?
    let totalTokenUsage: CodexTokenCounts?
}
struct CodexTokenCounts: Decodable {
    let inputTokens: Int
    let cachedInputTokens: Int
    let outputTokens: Int
    let reasoningOutputTokens: Int
    let totalTokens: Int
}
```

`CodexPayload` 的解码器读 `type` 字段后再选具体子结构 — 同一份 JSON 字段不能直接命中多个 case,需要自定义 init(from:)。

### 计价 — `PricingTable` 新增 OpenAI 段

参考 ccusage `put_builtin_pricing` 的 GPT-5 系列(`/rust/crates/ccusage/src/pricing.rs`):

| 模型 | input | cached_input(=cache_read) | output | 备注 |
|------|-------|---------------------------|--------|------|
| gpt-5 | $1.25 | $0.125 | $10.00 | reasoning 含在 output |
| gpt-5.1 | $1.25 | $0.125 | $10.00 | |
| gpt-5.1-codex | $1.25 | $0.125 | $10.00 | |
| gpt-5.2 | $1.25 | $0.125 | $10.00 | |
| gpt-5.2-codex | $1.25 | $0.125 | $10.00 | |
| gpt-5.3-codex | $1.25 | $0.125 | $10.00 | |
| gpt-5.4 | $1.25 | $0.125 | $10.00 | |
| gpt-5.4-mini | $0.25 | $0.025 | $2.00 | |
| gpt-5.4-nano | $0.05 | $0.005 | $0.40 | |
| gpt-5.5 | $1.25 | $0.125 | $10.00 | |

> 价位以实现时 ccusage `pricing.rs::put_builtin_pricing` 为准,文档表格中数值用于参考。
> 没有 `cacheWritePrice` 维度时,字段填 `0` — `PricingEngine.tieredCost` 在 `tokens > 0` 时才计费,Codex 永远不会有 cache write tokens,所以填 0 不会误算。

## 错误处理

| 场景 | 行为 |
|------|------|
| Provider 未授权 | 该 Tab 显示「授权访问 ~/.codex」按钮,其他 Tab 不受影响 |
| Codex 目录不存在(从未用过) | 状态显示「未检测到 Codex 数据」+ 隐藏刷新,不算错误 |
| 单行 JSON 解析失败 | 静默跳过 + `logger.debug`,不阻断后续行 |
| 文件读取失败 | 该文件计为 0 entries,`logger.warning`,不阻断其他文件 |
| `last_token_usage` 与 `total_token_usage` 都缺失 | 跳过该事件 |
| `currentModel == nil`(turn_context 缺失) | 跳过 token_count 事件,无法归属模型 |
| `total_token_usage` 倒退(rollover) | `saturating_sub` 退化为 0(同 ccusage) |
| Bookmark stale | 沿用现有 stale 重建逻辑,按 key 隔离 |
| 模型不在定价表 | cost = 0 + `logger.warning`(沿用现有 PricingEngine) |

## 测试计划

### 新增单元测试(Swift Testing)

`TokenWatchTests/Providers/Codex/`

- **CodexRolloutParserTests**(预计 8-10 个 `@Test`)
  - `last_token_usage 优先`
  - `last_token_usage 缺失时从 total - prevTotal 推导 delta`
  - `4 维全 0 的 token_count 事件被跳过`
  - `cached_input_tokens 从 input_tokens 中扣减,不 double-count`
  - `reasoning_output_tokens 不被单独累加`
  - `total_token_usage 倒退 → saturating_sub 退化为 0`
  - `turn_context 切模型后,后续 token_count 用新 model`
  - `currentModel 缺失时跳过 token_count`
  - `session_meta 缺失时 cwd 为 nil 不崩`

- **CodexRolloutScannerTests**(2-3 个)
  - `递归扫 YYYY/MM/DD/rollout-*.jsonl`
  - `archived_sessions/ 与 sessions/ 同相对路径时,sessions/ 优先`

- **ProviderRegistryTests**(2 个)
  - `allProviders 含 .claude / .codex`
  - `每个 provider 的 bookmarkKey 唯一`

### 测试 fixture

`TokenWatchTests/Fixtures/codex_sample.jsonl` — 手工裁剪的 mini rollout(10-15 行),覆盖:
session_meta → turn_context(gpt-5) → token_count(replay marker 全 0) → token_count(实际增量) → turn_context(gpt-5.5,模型切换)→ token_count → response_item(无关项,验证忽略)。

### 现有测试

- 现有 47 个测试随 Claude 文件迁入 `Providers/Claude/` 后保持全绿,**不修改逻辑**。
- `JSONLParserTests` 改名为 `ClaudeJSONLParserTests`,内容不变。

### 集成验证

- 手动:运行 app → Codex Tab → 授权 `~/.codex` → 用量数与 ccusage `ccusage codex daily` 对比误差应 < 1%(允许定价表与上游 LiteLLM 微小差异)。

## 提交策略(开发顺序)

按下列顺序拆分 commit,每步独立通过测试:

1. `refactor(providers): 将 Claude 相关代码迁入 Providers/Claude/` — 纯改文件位置,功能等价,所有 Claude 测试绿
2. `feat(providers): 引入 UsageProvider 协议与 ProviderRegistry` — 抽象层立起来,Claude 走新接口
3. `feat(bookmark): SecurityScopedBookmarkManager 多 key 化` — 测试现有 Claude 路径无回归
4. `feat(codex): 数据模型 CodexRecord` + 单元测试
5. `feat(codex): CodexRolloutScanner + CodexRolloutParser` + 单元测试
6. `feat(pricing): PricingTable 新增 OpenAI/GPT-5 系列定价`
7. `feat(viewmodel): TokenStatsViewModel 改为 per-provider 状态`
8. `feat(ui): 主视图改 NSTabViewController + ProviderStatsViewController`
9. `docs(readme): 更新 README 的多 provider 说明`

## 已知限制 / 后续

- **CODEX_HOME 环境变量**:本期不读取,默认走 `~/.codex`。后续可在 `CodexProvider` 内读 `ProcessInfo.processInfo.environment["CODEX_HOME"]`。
- **Codex thread_spawn replay 检测**:本期不实现 ccusage 那套「首 16KB 扫 thread_spawn → 同秒事件视为 replay」。我们的合成 dedupKey `(sessionId, timestamp)` 已能消除多次扫描重复,sub-agent 跨文件镜像的概率较低,有问题时再加。
- **byProject 维度**:Codex 的 cwd 来自 session_meta,可能整个 session 只有一个;UI 上 byProject 切片仍有效,但单 session = 单 project。
