# opencode Provider 接入设计

**日期**: 2026-06-15
**作者**: TokenWatch
**状态**: 设计已确认,待实现

## 背景与目标

TokenWatch 当前已支持 Claude / Codex 两个 provider,本次新增 **opencode** 第三个 provider。

opencode (https://opencode.ai, v1.17.5) 与现有两家差异:

- 数据存储为 **SQLite**(`~/.local/share/opencode/opencode.db`),不是 JSONL
- 一个会话可以横跨多个**上游 provider**(`anthropic` / `openai` / `huoshan-zijie` / 自家 `opencode` 等)
- 暴露独立的 **`reasoning` token** 字段(GPT-5/o3 系列特有,Codex 把 reasoning 算进 output)
- 自带 **per-message cost** 字段,可作为 LiteLLM catalog 查不到的小众模型的 fallback

设计参考 ccusage(`adapter/` per-provider 自治模式)与 TokenTracker(`messageId` 单独作 dedup
主键不强制 requestId)。

## 设计原则

1. **复用既有抽象**:`UsageProvider` 协议、`Scanner + Parser` 二件套、`PricingEngine`、
   `UsageAggregator` 不做架构性重构,只做向后兼容的字段扩展。
2. **YAGNI**:Claude / Codex 已有数据格式不动,新维度仅在 opencode 通道流通;
   `byModel` key 也仅在 opencode 上加 `providerID/modelID` 前缀。
3. **不引入第三方依赖**:SQLite 通过系统 `import SQLite3` 直接调用 C API,符合
   "不引入新第三方库"的项目约束。

## 数据模型扩展

### TokenUsage:新增 `reasoningTokens`

`TokenWatch/Models/TokenUsage.swift`:

```swift
struct TokenUsage: Decodable, Sendable {
    let inputTokens: Int
    let cacheCreationInputTokens: Int
    let cacheReadInputTokens: Int
    let outputTokens: Int
    let reasoningTokens: Int        // 新增
    let serverToolUse: ServerToolUse
    let serviceTier: String
    let cacheCreation: CacheCreation
    let inferenceGeo: String
    let iterations: [String]
    let speed: String
}
```

- `init(from decoder:)` 中:`reasoningTokens = try container.decodeIfPresent(Int.self,
  forKey: .reasoningTokens) ?? 0`
- Claude JSONL 没有该字段 → 默认 0,行为与现状一致
- Codex 的 `output_tokens` 已含 reasoning,不重复填,reasoningTokens 留 0
- opencode 由 parser 显式填充

便捷初始化器(用于测试)新增 `reasoningTokens: Int = 0` 默认参数,所有现有测试调用点零改动。

### ParsedUsageEntry:新增两个可选元数据字段

`TokenWatch/Models/ParsedUsageEntry.swift`:

```swift
struct ParsedUsageEntry: Sendable, Hashable {
    // ... 现有字段
    let upstreamProviderID: String?    // 仅 opencode 填,如 "huoshan-zijie";Claude/Codex 填 nil
    let upstreamCost: Double?          // opencode 自带 cost,作 PricingEngine miss 时的 fallback;Claude/Codex 填 nil
}
```

`dedupKey` / `hash(into:)` / `==` 均不变 —— opencode 的 `messageId` 全局唯一,新字段不参与
去重。

### UsageSummary:新增 `reasoningTokens`

`TokenWatch/Models/UsageAggregation.swift`:

```swift
struct UsageSummary: Sendable {
    let inputTokens: Int
    let outputTokens: Int
    let cacheReadTokens: Int
    let cacheCreationTokens: Int
    let reasoningTokens: Int        // 新增
    let totalTokens: Int            // = input + output + cacheRead + cacheCreation + reasoning
    let cost: Double
    let entryCount: Int
    let modelBreakdown: [String: UsageSummary]
}
```

`totalTokens` 把 reasoning 算进去,与"真实计费 token"语义一致。Codex 的 reasoning 已在 output
中,这里 reasoning=0 不会重复。`UsageSummary.zero` 同步加 `reasoningTokens: 0`。

### UsageProvider 协议:新增 `hasReasoningDimension`

`TokenWatch/Providers/UsageProvider.swift`:

```swift
protocol UsageProvider: Sendable {
    // ... 现有
    var hasCacheWriteDimension: Bool { get }
    var hasReasoningDimension: Bool { get }    // 新增
    // ...
}
```

值约定:
- Claude:`hasReasoningDimension = false`(无 reasoning 字段)
- Codex: `hasReasoningDimension = false`(reasoning 已并入 output,不单列)
- opencode:`hasReasoningDimension = true`

UI 据此决定要不要展示 reasoning 行(本次代码改动不含 UI)。

### ProviderID:新增 case

`TokenWatch/Providers/ProviderID.swift`:

```swift
enum ProviderID: String, Sendable, CaseIterable, Hashable, Codable {
    case claude
    case codex
    case opencode    // 新增
}
```

## opencode SQLite 读取层

### 文件布局

```
TokenWatch/Providers/OpenCode/
├── OpenCodeProvider.swift          # 装配 Scanner + Parser,实现 UsageProvider
├── OpenCodeSQLiteScanner.swift     # 打开 opencode.db,迭代 message 行
├── OpenCodeMessageParser.swift     # 把 SQLite 行 + JSON blob → ParsedUsageEntry
└── OpenCodeMessageData.swift       # message.data 的 Decodable 模型(含 tokens 子树)
```

### Bookmark / 目录授权

```swift
struct OpenCodeProvider: UsageProvider {
    let id: ProviderID = .opencode
    let displayName = "opencode"
    let bookmarkKey = "OpenCodeDirectoryBookmark"
    let defaultDirectoryPath = NSString("~/.local/share/opencode").expandingTildeInPath
    let openPanelMessage = "请选择 ~/.local/share/opencode 目录以授权 TokenWatch 读取 opencode 用量数据"
    let hasCacheWriteDimension = false       // 数据层映射保留,UI 暂不展示
    let hasReasoningDimension = true

    private let scanner = OpenCodeSQLiteScanner()
    private let parser = OpenCodeMessageParser()

    func loadEntries(from rootURL: URL) throws -> [ParsedUsageEntry] {
        let rows = try scanner.scanAll(in: rootURL)
        return try parser.parseAll(rows)
    }
}
```

### SQLite 打开:`immutable=1` URI 只读

`OpenCodeSQLiteScanner` 使用 `import SQLite3`,通过 URI 模式只读打开:

```swift
let dbURL = rootURL.appendingPathComponent("opencode.db")
let uri = "file:\(dbURL.path)?immutable=1"
let flags: Int32 = SQLITE_OPEN_READONLY | SQLITE_OPEN_URI
sqlite3_open_v2(uri, &db, flags, nil)
```

`immutable=1` 的关键作用:
- 告诉 SQLite **不要尝试创建/修改 WAL/SHM 文件** → 完全只读快照,与 App Sandbox readonly 兼容
- 避开 WAL 锁竞争 → opencode 进程在跑时也能并行读
- 代价:WAL 中未 checkpoint 的最新数据看不到 → 对统计场景完全可接受

### 查询语句

只查需要的列,不拉额外字段;`json_extract` 由 SQLite 自带:

```sql
SELECT m.id,
       m.session_id,
       m.time_created,
       m.data,
       s.directory
FROM message AS m
JOIN session AS s ON m.session_id = s.id
WHERE json_extract(m.data, '$.role') = 'assistant'
ORDER BY m.time_created;
```

Scanner 输出一个 `OpenCodeMessageRow` 数组(轻量 struct,不含解码后的 JSON),由 Parser 进一步处理。

```swift
struct OpenCodeMessageRow: Sendable {
    let id: String
    let sessionID: String
    let timeCreatedMs: Int64
    let dataJSON: String         // 原始 JSON 字符串,parser 再 decode
    let directory: String        // session.directory 作为 cwd 兜底
}
```

### 错误处理

- db 文件不存在 → 抛 `OpenCodeScannerError.databaseNotFound`,包含期望路径
- `sqlite3_open_v2` 失败 → 抛 `OpenCodeScannerError.openFailed(code: Int32, message: String)`
- prepare/step 失败 → 抛 `OpenCodeScannerError.queryFailed(...)`
- `defer { sqlite3_close(db) }` 保证句柄释放
- 单行 JSON 解码失败 → 在 Parser 中以 `logger.warning` 记录后跳过,不阻断整批

## opencode 字段映射

| opencode 来源 | → ParsedUsageEntry / TokenUsage |
|---|---|
| `message.id` | `messageId` 主键(全局唯一,`requestId = nil`,沿用现有 dedupKey 逻辑) |
| `message.session_id` | `sessionID` |
| `message.time_created`(ms epoch) | `timestamp = Date(timeIntervalSince1970: TimeInterval(ms) / 1000)` |
| `data.modelID` + `data.providerID` | `model = "\(providerID)/\(modelID)"`(如 `"huoshan-zijie/GLM-5.1"`) |
| `data.providerID` | `upstreamProviderID`(单独保留,便于未来按上游聚合) |
| `data.path.cwd`(缺则 `session.directory`) | `cwd` |
| `data.tokens.input` | `TokenUsage.inputTokens` |
| `data.tokens.output` | `TokenUsage.outputTokens` |
| `data.tokens.reasoning` | `TokenUsage.reasoningTokens` |
| `data.tokens.cache.read` | `TokenUsage.cacheReadInputTokens` |
| `data.tokens.cache.write` | `TokenUsage.cacheCreationInputTokens`(扁平字段,`ephemeral_5m/1h` 留 0;派生属性 `totalCacheCreationTokens` 会 fall through 到扁平字段,与现有约定一致) |
| `data.cost` | `upstreamCost`(USD,0 视为缺省) |
| —— | `requestId = nil`,`agentId = nil`,`isSubagent = false`,`provider = .opencode`,`serverToolUse / cacheCreation = zero`,`serviceTier / inferenceGeo / speed = ""`,`iterations = []` |

### 跳过条件

Parser 跳过以下行(不抛错,可选 `logger.debug`):

- `role != "assistant"`(query 已过滤,但 Parser 再 double-check 一次)
- `data.tokens` 缺失(草稿态 / 未 finalize)
- `tokens.input`、`tokens.output`、`tokens.reasoning`、`tokens.cache.read`、
  `tokens.cache.write` 五项**全为 0**(纯 placeholder / 失败的请求)

### dedupKey 行为

opencode 的 `messageId` 由 SQLite primary key 保证全局唯一,`requestId` 设为 nil,
`dedupKey` 直接落到现有 `requestId == nil` 分支返回 `messageId` 字符串,与 Codex 的合成 key 在
字面上不会冲突(opencode 是 `msg_xxx` 形式,Codex 是 `<sessionId>:<ISO8601>` 形式),且 dedup
仅在各 provider 自己的 `parseAllFiles` 内部完成,不跨 provider 共享 Set。

## Cost Fallback 接入聚合器

`TokenWatch/Analytics/UsageAggregator.swift::aggregateEntries(_:)` 中 cost 累加段:

**改动前:**

```swift
let (cost, _) = pricingEngine.calculateCost(usage: entry.usage, model: entry.model)
mCost += cost
```

**改动后:**

```swift
let (engineCost, pricing) = pricingEngine.calculateCost(usage: entry.usage, model: entry.model)
let cost: Double
if pricing == nil, let upstream = entry.upstreamCost, upstream > 0 {
    // PricingEngine 表里没该模型(常见于 opencode 上游小众模型)
    // → 退而使用源数据自带 cost,避免直接计 0
    cost = upstream
} else {
    cost = engineCost
}
mCost += cost
```

行为矩阵:

| 场景 | engineCost | upstreamCost | 实际取值 |
|---|---|---|---|
| Claude / Codex | 命中 | nil | engineCost |
| opencode + 主流上游(anthropic/openai) | 命中 | 0 或 >0 | engineCost |
| opencode + 小众上游(huoshan-zijie 等) | miss(0) | >0 | upstreamCost |
| opencode + 上游也算不出 | miss(0) | nil 或 0 | 0(无法可救) |

## ProviderRegistry 注册

`TokenWatch/Providers/ProviderRegistry.swift`:

```swift
static let allProviders: [any UsageProvider] = [
    ClaudeProvider(),
    CodexProvider(),
    OpenCodeProvider()    // 新增,顺序即 UI Tab 顺序
]
```

## 测试覆盖

### 新增测试文件

- `TokenWatchTests/Providers/OpenCode/OpenCodeMessageParserTests.swift`
  - 单条 assistant 消息字段映射(messageId / model 拼接 / cwd / timestamp / 5 个 token 字段
    / upstream metadata)
  - 跳过非 assistant、缺 tokens、全 0 token 三种 case
  - cost fallback 路径(模拟 PricingEngine miss + upstreamCost > 0)
  - reasoning tokens 进入 `UsageSummary.totalTokens`

- `TokenWatchTests/Providers/OpenCode/OpenCodeSQLiteScannerTests.swift`
  - 在临时目录用 `sqlite3` C API 创建一个 mini db(包含 message + session 表 + 几条 row),
    Scanner 能正确读出
  - 不存在的 db 路径 → 抛 `databaseNotFound`
  - 损坏的 db / 非 db 文件 → 抛 `openFailed`
  - immutable=1 模式下 db 仍处在被另一进程写入(模拟无法做到 100% 并发 —— 改为只验证 readonly
    flag 路径不会触发 file create,通过断言 `sqlite3_db_readonly` == 1)

### 既有测试增量

- `TokenUsageDecodingTests`:加一个 case 验证带 `reasoning_tokens` 字段的 JSON 能解码(借此
  覆盖 Claude 协议未来若加该字段的兼容性)
- `UsageAggregatorTests`:
  - `reasoningAggregation` —— 同 day / model 的多条 entry 含 reasoning,验证
    `byDay[k]?.reasoningTokens` 与 `byModel[m]?.reasoningTokens` 求和正确,且
    `totalTokens` 包含 reasoning
  - `upstreamCostFallback` —— 构造一条 entry,model 名 PricingEngine 查不到、`upstreamCost`
    有值 → cost 走 fallback;另一条 model 命中 → cost 走 engine。两条不互相污染。
- `ProviderRegistryTests`:验证 `.opencode` 的 provider 实例可被查到,且 `defaultDirectoryPath`
  指向 `~/.local/share/opencode` 展开后的绝对路径

### 不在本次范围

- UI 视图(opencode Tab、reasoning 行渲染、按上游聚合视图)
- WAL checkpoint 触发时数据陈旧的处理策略(immutable=1 已是当前选择)
- opencode 内 `tokens.cache.write` 暴露到 UI(`hasCacheWriteDimension=false`,数据层映射
  保留,UI 改动延后)

## 影响面

| 文件 | 改动类型 | 备注 |
|---|---|---|
| `TokenWatch/Models/TokenUsage.swift` | 修改 | +1 字段 + decode 兼容 + 便捷 init 默认参数 |
| `TokenWatch/Models/ParsedUsageEntry.swift` | 修改 | +2 字段(可选) |
| `TokenWatch/Models/UsageAggregation.swift` | 修改 | UsageSummary +1 字段 + zero |
| `TokenWatch/Providers/UsageProvider.swift` | 修改 | 协议 +1 属性 |
| `TokenWatch/Providers/ProviderID.swift` | 修改 | +1 case |
| `TokenWatch/Providers/ProviderRegistry.swift` | 修改 | +1 注册 |
| `TokenWatch/Providers/Claude/ClaudeProvider.swift` | 修改 | 加 `hasReasoningDimension = false` |
| `TokenWatch/Providers/Claude/ClaudeJSONLParser.swift` | 修改 | 显式填 `upstreamProviderID = nil`、`upstreamCost = nil`、reasoningTokens = 0 透传 |
| `TokenWatch/Providers/Codex/CodexProvider.swift` | 修改 | 加 `hasReasoningDimension = false` |
| `TokenWatch/Providers/Codex/CodexRolloutParser.swift` | 修改 | 显式填 `upstreamProviderID = nil`、`upstreamCost = nil` |
| `TokenWatch/Analytics/UsageAggregator.swift` | 修改 | aggregateEntries 内 cost fallback + reasoning 求和 |
| `TokenWatch/Providers/OpenCode/OpenCodeProvider.swift` | 新增 | 装配 |
| `TokenWatch/Providers/OpenCode/OpenCodeSQLiteScanner.swift` | 新增 | SQLite 读取 |
| `TokenWatch/Providers/OpenCode/OpenCodeMessageParser.swift` | 新增 | 字段映射 |
| `TokenWatch/Providers/OpenCode/OpenCodeMessageData.swift` | 新增 | JSON 模型 |
| `TokenWatchTests/Providers/OpenCode/OpenCodeMessageParserTests.swift` | 新增 | 单元测试 |
| `TokenWatchTests/Providers/OpenCode/OpenCodeSQLiteScannerTests.swift` | 新增 | 单元测试 |
| `TokenWatchTests/Models/TokenUsageDecodingTests.swift` | 修改 | reasoning_tokens 兼容性 |
| `TokenWatchTests/Analytics/UsageAggregatorTests.swift` | 修改 | reasoning + upstreamCost fallback |
| `TokenWatchTests/Providers/ProviderRegistryTests.swift` | 修改 | opencode 注册校验 |

合计 4 个新增源文件 + 2 个新增测试文件 + 多个文件小幅扩展。

## 提交规范

按 CLAUDE.md 约定:

- `feat(provider): 新增 opencode 数据源支持(SQLite + reasoning + 上游 cost fallback)`

由于改动跨多个层(模型扩展、协议扩展、新 provider、聚合器适配),实施时**可按层拆成 2~3 个
commit**(如:数据模型扩展 → opencode provider 新增 → registry 接入),具体由实施 plan 决定。
