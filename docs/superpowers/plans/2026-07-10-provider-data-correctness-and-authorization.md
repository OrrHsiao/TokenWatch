# Provider 数据正确性与授权 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 修复 DST 小时桶、usage presence 解码、Claude/Codex/OpenCode 边界数据、瞬时文件失败与 bookmark 假成功，并为下一阶段增量 JSONL 解析建立可复用的文件读取接口。

**Architecture:** 本计划必须在“计价 parity”阶段完成且其定向测试通过后执行，因为 `TokenUsage`、Claude/Codex parser 与计价 fixture 存在直接交叉。实现以小型纯类型隔离墙上小时描述和 Claude 去重，以共享 `JSONLFileReading`/`JSONLByteStream` 隔离文件元数据与字节读取，并让 Claude/Codex cache 始终保存尚未全局去重的 last-good candidates；bookmark 创建与存储则通过两个窄依赖注入到现有 manager。

**Tech Stack:** Swift 6、Foundation、AppKit、OSLog、SQLite3、Swift Testing、Xcode 26.5/macOS 15。

## Global Constraints

- 前置依赖：先完成设计文档阶段 1“计价 parity”，并确保固定 `ccusage v20.0.16 / e32cc482 --offline` 金额 fixture 全部通过；本计划不得回退其 Auto、模型查找、tier、fast 或 fallback 语义。
- LiteLLM 基线固定为 `49ca04d8c3ddea336237ce6f3082dbc26d19e944`，models.dev 使用 ccusage `v20.0.16` 内嵌 snapshot；本计划不新增运行时网络请求。
- Provider parity 限于 TokenWatch 已支持的 Claude JSONL、Codex `rollout-*.jsonl` 和 OpenCode 来源；不扩张到 ccusage 的多 root/XDG/隐藏目录发现或 Codex saved/headless exec，但对已支持文件中的有效 billing rows 必须保持最终金额一致。
- macOS deployment target 保持 `15.0`；主 target 保持 Swift `6.0`；不新增第三方依赖、数据库、TOML parser 或图表依赖。
- Release 无签名继续视为已确认设计，不修改 `.github/workflows/release.yml`。
- 所有行为先由失败测试复现，再写最小实现；每个 task 通过定向测试和独立 review 后才能进入下一 task。
- `TokenUsage.cacheCreation` 以 JSON 字段 presence 为准：对象存在即 authoritative，即使两个子字段都是零；仅缺失或 null 时回退扁平 `cache_creation_input_tokens`。
- Claude 单遍去重每条先查结构化 `(messageId, requestId)` exact key，miss 后才由记录级 `isSidechain` 触发同 message replay lookup；文件级 `isSubagent` 不能替代它。
- Claude replacement magnitude 逐字使用 ccusage 的 input、output、cache read 与 `cache_creation_token_count()`；cache creation 对象存在时使用 breakdown 之和，否则使用 flat 字段，不加入 reasoning。magnitude 平局后比较默认 Auto resolved cost，最后才比较 speed。
- Claude daily 解析同时支持 direct 与 AgentProgress 包装 usage；optional ID/model/session/request 的缺失与显式空串必须按 ccusage `v20.0.16 daily.rs` 分开处理，合法 usage 不得因缺 ID 被丢弃。
- Codex 优先非空 `last_token_usage`，不因 repeated total 自定义抑制；cached 必须 clamp 到 raw input，最终跨文件去重 key 不包含 session ID。
- Claude/Codex per-file cache 保存 raw candidates，不保存最终全局去重数组；每次返回前重新执行全局去重。
- scanner 已返回但随后 stat/open/seek/read 失败时才允许复用 last-good；scanner 未返回的文件按真实删除 prune；不引入 tombstone 或 grace period。
- 全量或增量新 cache 必须先在局部完整构建，成功后原子替换；失败不得覆盖上一次成功状态。
- 核心公共方法补充作用、参数和返回值注释；复杂去重、DST、presence、原子 cache 与 bookmark 失败分支说明设计原因并记录简洁日志。
- macOS 测试统一使用 `-destination 'platform=macOS' -derivedDataPath .build/DerivedData`；app-hosted tests 需要在沙盒外运行或申请访问 `testmanagerd` 的提升权限。
- test/build-for-testing 命令统一使用 `CODE_SIGN_STYLE=Manual DEVELOPMENT_TEAM= CODE_SIGN_IDENTITY=-` 的临时 ad-hoc 签名；纯 build/analyze 使用 `CODE_SIGNING_ALLOWED=NO`。
- Commit message 使用中文，格式为 `<type>(<scope>): <summary>`，一个 commit 只承载一个 task 的单一职责。

---

## 文件结构与职责

### 新增生产文件

- `TokenWatch/Models/LocalHourBucketDescriptor.swift`：以本地年月日和 `0..<24` 直接描述 24 个墙上小时，并提供聚合/UI 共用的 key 与 label。
- `TokenWatch/Providers/Claude/ClaudeUsageDeduplicator.swift`：实现 Claude daily exact-first / sidechain-fallback 单遍索引，并通过可注入 Auto cost resolver 保持 pinned replacement 顺序。
- `TokenWatch/Providers/JSONLFileReader.swift`：提供共享文件 identity/size/mtime、seek/read/close 接口及生产 FileHandle adapter；下一阶段增量解析直接复用。
- `TokenWatch/Services/BookmarkPersistence.swift`：提供 bookmark data creator、Bool store 与 UserDefaults 写后回读实现。

### 修改生产文件

- `TokenWatch/Analytics/UsageAggregator.swift:67,133-149`：小时聚合 key 改用共享 descriptor。
- `TokenWatch/ViewControllers/MonthlyTokenChartBuilder.swift:50-182,318-395`：`.today` 使用 24 个 descriptor，不再从午夜增加绝对小时。
- `TokenWatch/ViewControllers/DashboardRangeSnapshot.swift:65-120,186-248`：`.day` 使用 24 个 descriptor，避免重复 key 和次日混入。
- `TokenWatch/Models/TokenUsage.swift:5-131`：宽容解码两个子对象，并保留 `cacheCreation` presence。
- `TokenWatch/Models/ParsedUsageEntry.swift:12-49`：增加记录级 `isSidechain` 与带默认值的显式初始化器。
- `TokenWatch/Providers/Claude/ClaudeRecord.swift` / `ClaudeMessage.swift`：宽容归一 direct 与 AgentProgress usage，保留 optional 字段的 presence。
- `TokenWatch/Providers/Claude/ClaudeJSONLParser.swift:14-242`：执行 daily 过滤、传播 sidechain、调用单遍 deduplicator、接入共享 reader、复用 last-good candidates。
- `TokenWatch/Providers/Codex/CodexRolloutParser.swift:14-250`：保留 last-first reducer、clamp cached、执行 ccusage-compatible 跨文件去重与 replay 跳过，接入共享 reader、复用 last-good candidates。
- `TokenWatch/Providers/OpenCode/OpenCodeMessageParser.swift:52-74`：扁平 cache write usage 显式传 nil。
- `TokenWatch/Providers/OpenCode/OpenCodeSQLiteScanner.swift:64-78`：用 `json_valid` 保护 `json_extract`。
- `TokenWatch/Services/SecurityScopedBookmarkManager.swift:1-196`：注入 creator/store，只有创建并验证保存成功才从 panel 返回 URL。
- `TokenWatch/ViewModels/TokenStatsViewModel.swift:275-308`：fingerprint 纳入 `isSidechain`。

### 新增测试与测试支持

- `TokenWatchTests/Models/LocalHourBucketDescriptorTests.swift`
- `TokenWatchTests/ViewControllers/DashboardRangeSnapshotTests.swift`
- `TokenWatchTests/Providers/Claude/ClaudeUsageDeduplicatorTests.swift`
- `TokenWatchTests/Providers/JSONLFileReaderTests.swift`
- `TokenWatchTests/Services/BookmarkPersistenceTests.swift`
- `TokenWatchTests/TestSupport/ParsedUsageEntryDeepSnapshot.swift`
- `TokenWatchTests/TestSupport/RecordingJSONLFileReader.swift`

### 修改现有测试

- `TokenWatchTests/Analytics/UsageAggregatorTests.swift`
- `TokenWatchTests/Models/TokenUsageDecodingTests.swift`
- `TokenWatchTests/Pricing/PricingEngineTests.swift`
- `TokenWatchTests/Pricing/CCUsagePricingParityTests.swift`
- `TokenWatchTests/Providers/Claude/ClaudeJSONLParserTests.swift`
- `TokenWatchTests/Providers/Codex/CodexRolloutParserTests.swift`
- `TokenWatchTests/Providers/OpenCode/OpenCodeMessageParserTests.swift`
- `TokenWatchTests/Providers/OpenCode/OpenCodeSQLiteScannerTests.swift`
- `TokenWatchTests/Services/SecurityScopedBookmarkManagerTests.swift`
- `TokenWatchTests/ViewControllers/MonthlyTokenChartBuilderTests.swift`
- `TokenWatchTests/ViewModels/TokenStatsViewModelObserverTests.swift`
- `TokenWatchTests/TokenWatchTests.swift`

`TokenWatch.xcodeproj/project.pbxproj` 使用 `PBXFileSystemSynchronizedRootGroup`，以上新增 Swift 文件会自动进入对应 target，不编辑工程文件。

### 下一阶段共享状态

本计划只落地 `JSONLFileReading`、文件 metadata 和 last-good 行为；增量计划在其上新增下列状态，不修改本计划的 reader 签名：

计价计划必须先产出并由本计划直接消费以下 model-source 接口：

```swift
enum CodexModelSource: Sendable, Equatable {
    case explicit
    case fallback
}

struct CodexModelState: Sendable, Equatable {
    let rawModel: String
    let source: CodexModelSource
}
```

```swift
struct IncrementalJSONLFileState<Candidate: Sendable, Checkpoint: Sendable>: Sendable {
    let metadata: JSONLFileMetadata
    let committedOffset: UInt64
    let stableCandidates: [Candidate]
    let provisionalTail: Data
    let provisionalCandidates: [Candidate]
    let checkpointAtCommittedOffset: Checkpoint
}
```

Codex 增量 checkpoint 必须复用计价阶段产生的 explicit/fallback model state，并纳入本计划改成可选的 totals：

```swift
struct CodexParserCheckpoint: Sendable {
    var currentModel: CodexModelState?
    var sessionID: String
    var cwd: String?
    var previousTotals: CodexTokenCounts?
}
```

provisional tail 只能从 `checkpointAtCommittedOffset` 的副本解析；它产生的 model、session、cwd 和 `previousTotals` 不能提前写回 committed checkpoint。

---

### Task 1: 保留 TokenUsage presence 并宽容解码子对象

**Files:**
- Modify: `TokenWatch/Models/TokenUsage.swift:5-131`
- Modify: `TokenWatch/Providers/Codex/CodexRolloutParser.swift:110-125`
- Modify: `TokenWatch/Providers/OpenCode/OpenCodeMessageParser.swift:52-67`
- Modify: `TokenWatchTests/Models/TokenUsageDecodingTests.swift:11-157`
- Modify: `TokenWatchTests/Pricing/PricingEngineTests.swift:73-101,399-427`
- Modify: `TokenWatchTests/Pricing/CCUsagePricingParityTests.swift`
- Modify: `TokenWatchTests/Analytics/UsageAggregatorTests.swift:394-419`
- Modify: `TokenWatchTests/Providers/Codex/CodexRolloutParserTests.swift:33-54`
- Modify: `TokenWatchTests/Providers/OpenCode/OpenCodeMessageParserTests.swift:64-82`

**Interfaces:**
- Consumes: 计价阶段完成后的 `PricingEngine.calculateCost(usage:pricing:)` 与固定 ccusage fixture。
- Produces: `TokenUsage.cacheCreation: CacheCreation?`；`ServerToolUse.init(webSearchRequests:webFetchRequests:)`；`CacheCreation.init(ephemeral1hInputTokens:ephemeral5mInputTokens:)`；presence-aware `cacheCreate5mTokens`、`cacheCreate1hTokens`、`totalCacheCreationTokens`。

- [ ] **Step 1: 写出 presence 和 partial-object 的失败测试**

在 `TokenWatchTests/Models/TokenUsageDecodingTests.swift` 增加以下测试，并把既有 `decodeFullUsage`/`decodeWithoutOptionalFields` 的直接点访问改为 optional chain：

```swift
@Test("缺失 cache_creation 时保留 nil 并回退扁平字段")
func missingCacheCreationFallsBackToFlatTokens() throws {
    let json = """
    {
        "input_tokens": 1,
        "output_tokens": 2,
        "cache_creation_input_tokens": 500
    }
    """

    let usage = try JSONDecoder().decode(TokenUsage.self, from: Data(json.utf8))

    #expect(usage.cacheCreation == nil)
    #expect(usage.cacheCreate5mTokens == 500)
    #expect(usage.cacheCreate1hTokens == 0)
    #expect(usage.totalCacheCreationTokens == 500)
}

@Test("cache_creation 对象存在时即使全零也不回退扁平字段")
func presentEmptyCacheCreationSuppressesFlatFallback() throws {
    let json = """
    {
        "input_tokens": 1,
        "output_tokens": 2,
        "cache_creation_input_tokens": 500,
        "cache_creation": {}
    }
    """

    let usage = try JSONDecoder().decode(TokenUsage.self, from: Data(json.utf8))

    #expect(usage.cacheCreation != nil)
    #expect(usage.cacheCreation?.ephemeral1hInputTokens == 0)
    #expect(usage.cacheCreation?.ephemeral5mInputTokens == 0)
    #expect(usage.totalCacheCreationTokens == 0)
}

@Test("server_tool_use 和 cache_creation 的单个缺失子字段解码为零")
func partialNestedUsageObjectsDefaultMissingMembersToZero() throws {
    let json = """
    {
        "input_tokens": 1,
        "output_tokens": 2,
        "server_tool_use": {"web_search_requests": 3},
        "cache_creation": {"ephemeral_1h_input_tokens": 4}
    }
    """

    let usage = try JSONDecoder().decode(TokenUsage.self, from: Data(json.utf8))

    #expect(usage.serverToolUse.webSearchRequests == 3)
    #expect(usage.serverToolUse.webFetchRequests == 0)
    #expect(usage.cacheCreation?.ephemeral1hInputTokens == 4)
    #expect(usage.cacheCreation?.ephemeral5mInputTokens == 0)
}
```

同时在 provider 测试加入明确的扁平映射断言：

```swift
#expect(e.usage.cacheCreation == nil)
```

- [ ] **Step 2: 运行测试并确认 RED**

Run:

```bash
xcodebuild -project TokenWatch.xcodeproj -scheme TokenWatch -destination 'platform=macOS' \
  -only-testing:TokenWatchTests/TokenUsageDecodingTests \
  -only-testing:TokenWatchTests/OpenCodeMessageParserTests \
  -only-testing:TokenWatchTests/CodexRolloutParserTests/lastTokenUsagePreferred \
  -skip-testing:TokenWatchUITests -derivedDataPath .build/DerivedData CODE_SIGN_STYLE=Manual DEVELOPMENT_TEAM= CODE_SIGN_IDENTITY=- test
```

Expected: FAIL；当前 `TokenUsage.cacheCreation` 非 optional，缺失时被创建为零对象，partial `ServerToolUse`/`CacheCreation` 因 synthesized decoder 缺键而抛错，OpenCode/Codex 构造结果也不是 nil。

- [ ] **Step 3: 实现宽容子对象与 presence-aware 派生属性**

将 `TokenWatch/Models/TokenUsage.swift` 的相关定义改为：

```swift
struct TokenUsage: Decodable, Sendable {
    let inputTokens: Int
    let cacheCreationInputTokens: Int
    let cacheReadInputTokens: Int
    let outputTokens: Int
    let reasoningTokens: Int
    let serverToolUse: ServerToolUse
    let serviceTier: String
    let cacheCreation: CacheCreation?
    let inferenceGeo: String
    let iterations: [String]
    let speed: String

    enum CodingKeys: String, CodingKey {
        case inputTokens = "input_tokens"
        case cacheCreationInputTokens = "cache_creation_input_tokens"
        case cacheReadInputTokens = "cache_read_input_tokens"
        case outputTokens = "output_tokens"
        case reasoningTokens = "reasoning_tokens"
        case serverToolUse = "server_tool_use"
        case serviceTier = "service_tier"
        case cacheCreation = "cache_creation"
        case inferenceGeo = "inference_geo"
        case iterations
        case speed
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        inputTokens = try container.decode(Int.self, forKey: .inputTokens)
        cacheCreationInputTokens = try container.decodeIfPresent(Int.self, forKey: .cacheCreationInputTokens) ?? 0
        cacheReadInputTokens = try container.decodeIfPresent(Int.self, forKey: .cacheReadInputTokens) ?? 0
        outputTokens = try container.decode(Int.self, forKey: .outputTokens)
        reasoningTokens = try container.decodeIfPresent(Int.self, forKey: .reasoningTokens) ?? 0
        serverToolUse = try container.decodeIfPresent(ServerToolUse.self, forKey: .serverToolUse)
            ?? ServerToolUse(webSearchRequests: 0, webFetchRequests: 0)
        serviceTier = try container.decodeIfPresent(String.self, forKey: .serviceTier) ?? ""
        cacheCreation = try container.decodeIfPresent(CacheCreation.self, forKey: .cacheCreation)
        inferenceGeo = try container.decodeIfPresent(String.self, forKey: .inferenceGeo) ?? ""
        iterations = []
        speed = try container.decodeIfPresent(String.self, forKey: .speed) ?? ""
    }

    init(
        inputTokens: Int,
        cacheCreationInputTokens: Int,
        cacheReadInputTokens: Int,
        outputTokens: Int,
        reasoningTokens: Int = 0,
        serverToolUse: ServerToolUse,
        serviceTier: String,
        cacheCreation: CacheCreation?,
        inferenceGeo: String,
        iterations: [String],
        speed: String
    ) {
        self.inputTokens = inputTokens
        self.cacheCreationInputTokens = cacheCreationInputTokens
        self.cacheReadInputTokens = cacheReadInputTokens
        self.outputTokens = outputTokens
        self.reasoningTokens = reasoningTokens
        self.serverToolUse = serverToolUse
        self.serviceTier = serviceTier
        self.cacheCreation = cacheCreation
        self.inferenceGeo = inferenceGeo
        self.iterations = iterations
        self.speed = speed
    }
}

struct ServerToolUse: Decodable, Sendable {
    let webSearchRequests: Int
    let webFetchRequests: Int

    enum CodingKeys: String, CodingKey {
        case webSearchRequests = "web_search_requests"
        case webFetchRequests = "web_fetch_requests"
    }

    init(webSearchRequests: Int, webFetchRequests: Int) {
        self.webSearchRequests = webSearchRequests
        self.webFetchRequests = webFetchRequests
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        webSearchRequests = try container.decodeIfPresent(Int.self, forKey: .webSearchRequests) ?? 0
        webFetchRequests = try container.decodeIfPresent(Int.self, forKey: .webFetchRequests) ?? 0
    }
}

struct CacheCreation: Decodable, Sendable {
    let ephemeral1hInputTokens: Int
    let ephemeral5mInputTokens: Int

    enum CodingKeys: String, CodingKey {
        case ephemeral1hInputTokens = "ephemeral_1h_input_tokens"
        case ephemeral5mInputTokens = "ephemeral_5m_input_tokens"
    }

    init(ephemeral1hInputTokens: Int, ephemeral5mInputTokens: Int) {
        self.ephemeral1hInputTokens = ephemeral1hInputTokens
        self.ephemeral5mInputTokens = ephemeral5mInputTokens
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        ephemeral1hInputTokens = try container.decodeIfPresent(Int.self, forKey: .ephemeral1hInputTokens) ?? 0
        ephemeral5mInputTokens = try container.decodeIfPresent(Int.self, forKey: .ephemeral5mInputTokens) ?? 0
    }
}

extension TokenUsage {
    var cacheCreate5mTokens: Int {
        guard let cacheCreation else { return cacheCreationInputTokens }
        return cacheCreation.ephemeral5mInputTokens
    }

    var cacheCreate1hTokens: Int {
        cacheCreation?.ephemeral1hInputTokens ?? 0
    }

    var totalCacheCreationTokens: Int {
        cacheCreate5mTokens + cacheCreate1hTokens
    }
}
```

- [ ] **Step 4: 把扁平 provider 与扁平测试夹具明确改为 nil**

在 Codex/OpenCode production initializer 中使用：

```swift
cacheCreation: nil,
```

在 `PricingEngineTests.cacheWriteCostFlat`、`PricingEngineTests.tieredCacheCategories` 和 `UsageAggregatorTests.makeEntry` 的扁平 cache fixture 中也使用：

```swift
cacheCreation: nil,
```

保留所有真正表达 Claude 5m/1h breakdown 的非 nil `CacheCreation(ephemeral1hInputTokens:ephemeral5mInputTokens:)` fixture。

在 `CCUsagePricingParityTests.entry(from:)` 中让固定金额适配器与真实 provider 形状一致；只有 Claude fixture 构造 breakdown，Codex/OpenCode 明确传 `nil`：

```swift
cacheCreation: testCase.provider == .claude
    ? CacheCreation(
        ephemeral1hInputTokens: testCase.usage.cacheCreate1hTokens ?? 0,
        ephemeral5mInputTokens: testCase.usage.cacheCreate5mTokens ?? 0
    )
    : nil,
```

- [ ] **Step 5: 运行定向测试和计价回归并确认 GREEN**

Run:

```bash
xcodebuild -project TokenWatch.xcodeproj -scheme TokenWatch -destination 'platform=macOS' \
  -only-testing:TokenWatchTests/TokenUsageDecodingTests \
  -only-testing:TokenWatchTests/OpenCodeMessageParserTests \
  -only-testing:TokenWatchTests/CodexRolloutParserTests \
  -only-testing:TokenWatchTests/UsageAggregatorTests \
  -only-testing:TokenWatchTests/PricingEngineTests \
  -only-testing:TokenWatchTests/CCUsagePricingParityTests \
  -skip-testing:TokenWatchUITests -derivedDataPath .build/DerivedData CODE_SIGN_STYLE=Manual DEVELOPMENT_TEAM= CODE_SIGN_IDENTITY=- test
```

Expected: PASS；缺失 breakdown 走 flat，存在空对象不回退，两个 provider 的扁平 usage 为 nil，计价阶段固定 fixture 无回归。

- [ ] **Step 6: 提交 Task 1**

```bash
git add TokenWatch/Models/TokenUsage.swift \
  TokenWatch/Providers/Codex/CodexRolloutParser.swift \
  TokenWatch/Providers/OpenCode/OpenCodeMessageParser.swift \
  TokenWatchTests/Models/TokenUsageDecodingTests.swift \
  TokenWatchTests/Pricing/PricingEngineTests.swift \
  TokenWatchTests/Pricing/CCUsagePricingParityTests.swift \
  TokenWatchTests/Analytics/UsageAggregatorTests.swift \
  TokenWatchTests/Providers/Codex/CodexRolloutParserTests.swift \
  TokenWatchTests/Providers/OpenCode/OpenCodeMessageParserTests.swift
git commit -m "fix(usage): 保留缓存细分字段存在性"
```

---

### Task 2: 用墙上小时描述符修复 DST 日的 24 桶

**Files:**
- Create: `TokenWatch/Models/LocalHourBucketDescriptor.swift`
- Modify: `TokenWatch/Analytics/UsageAggregator.swift:67,133-149`
- Modify: `TokenWatch/ViewControllers/MonthlyTokenChartBuilder.swift:50-182,318-395`
- Modify: `TokenWatch/ViewControllers/DashboardRangeSnapshot.swift:65-120,186-248`
- Create: `TokenWatchTests/Models/LocalHourBucketDescriptorTests.swift`
- Create: `TokenWatchTests/ViewControllers/DashboardRangeSnapshotTests.swift`
- Modify: `TokenWatchTests/ViewControllers/MonthlyTokenChartBuilderTests.swift:69-87,239-283`
- Modify: `TokenWatchTests/TokenWatchTests.swift:1227-1288`

**Interfaces:**
- Consumes: `AggregatedStats.byHour` 的 `yyyy-MM-ddTHH` key 契约。
- Produces: `LocalHourBucketDescriptor.buckets(forDayContaining:calendar:) -> [LocalHourBucketDescriptor]`、`LocalHourBucketDescriptor.key(for:calendar:) -> String`、`label(language:) -> String`。

- [ ] **Step 1: 写出春季、秋季和两个 UI consumer 的失败测试**

创建 `TokenWatchTests/Models/LocalHourBucketDescriptorTests.swift`：

```swift
import Foundation
import Testing
@testable import TokenWatch

@Suite("LocalHourBucketDescriptor")
struct LocalHourBucketDescriptorTests {
    @Test("春季跳时日仍生成 00 到 23 的二十四个唯一墙上小时")
    func springForwardDayHasTwentyFourWallClockBuckets() throws {
        let calendar = losAngelesCalendar()
        let day = try #require(calendar.date(from: DateComponents(
            year: 2026, month: 3, day: 8, hour: 12
        )))

        let buckets = LocalHourBucketDescriptor.buckets(forDayContaining: day, calendar: calendar)

        #expect(buckets.count == 24)
        #expect(Set(buckets.map(\.key)).count == 24)
        #expect(buckets.map(\.key) == (0..<24).map {
            String(format: "2026-03-08T%02d", $0)
        })
    }

    @Test("秋季回拨日两个真实 01 点映射到同一个墙上 key")
    func repeatedRealHoursShareOneWallClockKey() throws {
        let calendar = losAngelesCalendar()
        let midnight = try #require(calendar.date(from: DateComponents(
            year: 2026, month: 11, day: 1, hour: 0
        )))
        let firstOne = try #require(calendar.date(byAdding: .hour, value: 1, to: midnight))
        let secondOne = firstOne.addingTimeInterval(3_600)
        let buckets = LocalHourBucketDescriptor.buckets(forDayContaining: midnight, calendar: calendar)

        #expect(LocalHourBucketDescriptor.key(for: firstOne, calendar: calendar) == "2026-11-01T01")
        #expect(LocalHourBucketDescriptor.key(for: secondOne, calendar: calendar) == "2026-11-01T01")
        #expect(buckets.count == 24)
        #expect(Set(buckets.map(\.key)).count == 24)
        #expect(buckets.last?.key == "2026-11-01T23")
    }

    private func losAngelesCalendar() -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/Los_Angeles")!
        return calendar
    }
}
```

在 `MonthlyTokenChartBuilderTests.swift` 增加春季 integration：

```swift
@Test("春季跳时日本日图仍展示 24 桶且不存在的 02 点为零")
func todaySpringForwardUsesWallClockBuckets() throws {
    let calendar = losAngelesCalendar()
    let now = try #require(calendar.date(from: DateComponents(
        year: 2026, month: 3, day: 8, hour: 14
    )))
    let stats = makeStats(
        byHour: [
            "2026-03-08T01": makeSummary(total: 10),
            "2026-03-08T03": makeSummary(total: 30),
            "2026-03-09T00": makeSummary(total: 999),
        ],
        byDay: [:],
        byMonth: [:]
    )

    let snapshot = MonthlyTokenChartBuilder.build(
        states: [.claude: .init(
            stats: stats,
            isLoading: false,
            errorMessage: nil,
            needsAuthorization: false
        )],
        period: .today,
        now: now,
        calendar: calendar
    )

    #expect(snapshot.monthBuckets.count == 24)
    #expect(snapshot.bucket("2026-03-08T02")?.totalTokens == 0)
    #expect(snapshot.bucket("2026-03-08T03")?.totalTokens == 30)
    #expect(snapshot.bucket("2026-03-09T00") == nil)
    #expect(snapshot.totalTokens == 40)
}

private func losAngelesCalendar() -> Calendar {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "America/Los_Angeles")!
    return calendar
}
```

创建 `DashboardRangeSnapshotTests.swift`：

```swift
import Foundation
import Testing
@testable import TokenWatch

@Suite("DashboardRangeSnapshot")
struct DashboardRangeSnapshotTests {
    @Test("秋季回拨日 dashboard 仍生成唯一的 00 到 23")
    func fallBackDayUsesTwentyFourUniqueWallClockBuckets() throws {
        let calendar = losAngelesCalendar()
        let now = try #require(calendar.date(from: DateComponents(
            year: 2026, month: 11, day: 1, hour: 12
        )))
        let stats = AggregatedStats(
            overall: .zero,
            byHour: ["2026-11-01T01": summary(total: 40)],
            byDay: [:],
            byWeek: [:],
            byMonth: [:],
            bySession: [:],
            byModel: [:],
            byProject: [:],
            dataSourceCount: 1
        )

        let snapshot = DashboardRangeSnapshot.build(
            states: [.claude: .init(
                stats: stats,
                isLoading: false,
                errorMessage: nil,
                needsAuthorization: false
            )],
            range: .day,
            now: now,
            calendar: calendar,
            language: .zhHans
        )

        #expect(snapshot.trendBuckets.count == 24)
        #expect(Set(snapshot.trendBuckets.map(\.key)).count == 24)
        #expect(snapshot.trendBuckets.first?.key == "2026-11-01T00")
        #expect(snapshot.trendBuckets.last?.key == "2026-11-01T23")
        #expect(snapshot.trendBuckets.filter { $0.key == "2026-11-01T01" }.count == 1)
        #expect(snapshot.trendBuckets.first(where: { $0.key == "2026-11-01T01" })?.totalTokens == 40)
        #expect(snapshot.totalTokens == 40)
    }

    private func losAngelesCalendar() -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/Los_Angeles")!
        return calendar
    }

    private func summary(total: Int) -> UsageSummary {
        UsageSummary(
            inputTokens: total,
            outputTokens: 0,
            cacheReadTokens: 0,
            cacheCreationTokens: 0,
            reasoningTokens: 0,
            totalTokens: total,
            cost: 0,
            entryCount: 1,
            modelBreakdown: [:]
        )
    }
}
```

- [ ] **Step 2: 运行测试并确认 RED**

Run:

```bash
xcodebuild -project TokenWatch.xcodeproj -scheme TokenWatch -destination 'platform=macOS' \
  -only-testing:TokenWatchTests/LocalHourBucketDescriptorTests \
  -only-testing:TokenWatchTests/MonthlyTokenChartBuilderTests/todaySpringForwardUsesWallClockBuckets \
  -only-testing:TokenWatchTests/DashboardRangeSnapshotTests \
  -skip-testing:TokenWatchUITests -derivedDataPath .build/DerivedData CODE_SIGN_STYLE=Manual DEVELOPMENT_TEAM= CODE_SIGN_IDENTITY=- test
```

Expected: FAIL；descriptor 尚不存在。若先只运行当前 builder，春季会把次日 `T00` 混入，秋季 `Dictionary(uniqueKeysWithValues:)` 会遇到重复 `T01`。

- [ ] **Step 3: 实现共享墙上小时描述符**

创建 `TokenWatch/Models/LocalHourBucketDescriptor.swift`：

```swift
import Foundation

/// 本地自然日中的一个墙上小时；不持有绝对 Date，避免 DST 跳时或回拨改变桶数量。
struct LocalHourBucketDescriptor: Sendable, Equatable, Identifiable {
    let hour: Int
    let key: String

    var id: String { key }

    /// 直接以本地年月日和 0..<24 生成固定 24 个墙上小时。
    static func buckets(
        forDayContaining date: Date,
        calendar: Calendar
    ) -> [LocalHourBucketDescriptor] {
        let components = calendar.dateComponents([.year, .month, .day], from: date)
        guard let year = components.year,
              let month = components.month,
              let day = components.day else {
            return []
        }

        return (0..<24).map { hour in
            LocalHourBucketDescriptor(
                hour: hour,
                key: String(format: "%04d-%02d-%02dT%02d", year, month, day, hour)
            )
        }
    }

    /// 把真实时间映射为与墙上小时列表相同格式的本地 key。
    static func key(for date: Date?, calendar: Calendar) -> String {
        guard let date else { return "unknown" }
        let components = calendar.dateComponents([.year, .month, .day, .hour], from: date)
        guard let year = components.year,
              let month = components.month,
              let day = components.day,
              let hour = components.hour else {
            return "unknown"
        }
        return String(format: "%04d-%02d-%02dT%02d", year, month, day, hour)
    }

    /// 返回当前 App 语言下的小时标签。
    func label(language: AppLanguage) -> String {
        switch language {
        case .zhHans, .zhHant:
            return "\(hour)时"
        case .ja:
            return "\(hour)時"
        case .ko:
            return "\(hour)시"
        case .en, .es, .de, .fr, .ptBR, .it, .nl, .pl:
            return "\(hour)"
        }
    }
}
```

在 `UsageAggregator.aggregate` 中使用：

```swift
byHour.add(
    key: LocalHourBucketDescriptor.key(for: entry.timestamp, calendar: calendar),
    entry: entry,
    cost: cost
)
```

删除原私有 `hourKey(from:calendar:)`，避免出现第二份格式实现。

- [ ] **Step 4: 把 Monthly 和 Dashboard 的日视图改成 descriptor 驱动**

在 `MonthlyTokenChartBuilder.build` 中以以下分支生成 key、label 和 current key，非 `.today` 仍沿用现有月/日 Date 算法：

```swift
let currentBucketStart = period.currentBucketStart(now: now, calendar: calendar)
let windowStart = period.windowStart(
    currentBucketStart: currentBucketStart,
    now: now,
    calendar: calendar
)

let bucketStarts: [Date]
let hourBuckets: [LocalHourBucketDescriptor]
if period == .today {
    bucketStarts = []
    hourBuckets = LocalHourBucketDescriptor.buckets(
        forDayContaining: now,
        calendar: calendar
    )
} else {
    bucketStarts = (0..<period.bucketCount).compactMap { offset in
        calendar.date(byAdding: period.calendarComponent, value: offset, to: windowStart)
    }
    hourBuckets = []
}

let bucketKeys = period == .today
    ? hourBuckets.map(\.key)
    : bucketStarts.map { period.bucketKey(for: $0, calendar: calendar) }
let labelByKey = period == .today
    ? Dictionary(uniqueKeysWithValues: hourBuckets.map { ($0.key, $0.label(language: language)) })
    : Dictionary(uniqueKeysWithValues: bucketStarts.map {
        let key = period.bucketKey(for: $0, calendar: calendar)
        return (key, period.bucketLabel(for: $0, calendar: calendar, language: language))
    })
let currentKey = LocalHourBucketDescriptor.key(for: now, calendar: calendar)
```

把最终 `buckets` 改为按 key 构建：

```swift
let buckets = bucketKeys.map { key in
    let totalTokens = totals[key, default: 0]
    let totalCost = costs[key, default: 0]
    let normalizedHeight = maxMonthlyTokens > 0
        ? Double(totalTokens) / Double(maxMonthlyTokens)
        : 0
    let normalizedCostHeight = maxMonthlyCost > 0
        ? totalCost / maxMonthlyCost
        : 0
    return MonthlyTokenBucket(
        id: key,
        monthKey: key,
        monthLabel: labelByKey[key, default: key],
        totalTokens: totalTokens,
        totalCost: totalCost,
        normalizedHeight: normalizedHeight,
        normalizedCostHeight: normalizedCostHeight,
        isCurrentMonth: period == .today
            ? key == currentKey
            : key == period.bucketKey(for: currentBucketStart, calendar: calendar),
        modelSegments: buildModelSegments(
            modelTotalsByBucket[key, default: [:]],
            costs: modelCostsByBucket[key, default: [:]],
            monthTotalTokens: totalTokens,
            legendEntries: modelSegmentLegendEntries
        )
    )
}
```

在 `DashboardRangeSnapshot.swift` 增加文件内 descriptor：

```swift
fileprivate struct DashboardRangeBucketDescriptor {
    let key: String
    let label: String
    let isCurrent: Bool
}
```

并让 `DashboardRange` 生成：

```swift
fileprivate func buckets(
    now: Date,
    calendar: Calendar,
    language: AppLanguage
) -> [DashboardRangeBucketDescriptor] {
    if self == .day {
        let currentKey = LocalHourBucketDescriptor.key(for: now, calendar: calendar)
        return LocalHourBucketDescriptor
            .buckets(forDayContaining: now, calendar: calendar)
            .map { bucket in
                DashboardRangeBucketDescriptor(
                    key: bucket.key,
                    label: bucket.label(language: language),
                    isCurrent: bucket.key == currentKey
                )
            }
    }

    return bucketStarts(now: now, calendar: calendar).map { date in
        let key = bucketKey(for: date, calendar: calendar)
        return DashboardRangeBucketDescriptor(
            key: key,
            label: bucketLabel(for: date, calendar: calendar, language: language),
            isCurrent: key == bucketKey(for: now, calendar: calendar)
        )
    }
}
```

`buildWindow` 只消费 `range.buckets(now:calendar:language:)` 的 `key`、`label`、`isCurrent`；不再对 `.day` 调用 `date(byAdding:value:to:)` 增加绝对小时。

- [ ] **Step 5: 运行 DST 定向测试并确认 GREEN**

Run:

```bash
xcodebuild -project TokenWatch.xcodeproj -scheme TokenWatch -destination 'platform=macOS' \
  -only-testing:TokenWatchTests/LocalHourBucketDescriptorTests \
  -only-testing:TokenWatchTests/MonthlyTokenChartBuilderTests \
  -only-testing:TokenWatchTests/DashboardRangeSnapshotTests \
  -only-testing:TokenWatchTests/UsageAggregatorTests \
  -only-testing:TokenWatchTests/TokenWatchTests/dashboardTrendBucketsFollowSelectedRangeGranularity \
  -skip-testing:TokenWatchUITests -derivedDataPath .build/DerivedData CODE_SIGN_STYLE=Manual DEVELOPMENT_TEAM= CODE_SIGN_IDENTITY=- test
```

Expected: PASS；春秋两天都得到 `00...23` 的 24 个唯一 key，春季 `02` 为零，秋季两个真实 `01` 共用一个 key，次日 `00` 不进入本日。

- [ ] **Step 6: 提交 Task 2**

```bash
git add TokenWatch/Models/LocalHourBucketDescriptor.swift \
  TokenWatch/Analytics/UsageAggregator.swift \
  TokenWatch/ViewControllers/MonthlyTokenChartBuilder.swift \
  TokenWatch/ViewControllers/DashboardRangeSnapshot.swift \
  TokenWatchTests/Models/LocalHourBucketDescriptorTests.swift \
  TokenWatchTests/ViewControllers/DashboardRangeSnapshotTests.swift \
  TokenWatchTests/ViewControllers/MonthlyTokenChartBuilderTests.swift \
  TokenWatchTests/TokenWatchTests.swift
git commit -m "fix(chart): 修复 DST 本地小时桶"
```

---

### Task 3: 归一 Claude daily 行并复刻单遍 sidechain 去重

**Files:**
- Modify: `TokenWatch/Models/ParsedUsageEntry.swift:12-49`
- Modify: `TokenWatch/Providers/Claude/ClaudeRecord.swift`
- Modify: `TokenWatch/Providers/Claude/ClaudeMessage.swift`
- Modify: `TokenWatch/Providers/Claude/ClaudeJSONLScanner.swift`
- Create: `TokenWatch/Providers/Claude/ClaudeUsageDeduplicator.swift`
- Modify: `TokenWatch/Providers/Claude/ClaudeJSONLParser.swift:69-195`
- Modify: `TokenWatch/ViewModels/TokenStatsViewModel.swift:275-308`
- Create: `TokenWatchTests/TestSupport/ParsedUsageEntryDeepSnapshot.swift`
- Create: `TokenWatchTests/Providers/Claude/ClaudeUsageDeduplicatorTests.swift`
- Modify: `TokenWatchTests/Providers/Claude/ClaudeJSONLParserTests.swift:13-305`
- Modify: `TokenWatchTests/Providers/Claude/ClaudeJSONLScannerTests.swift`
- Modify: `TokenWatchTests/ViewModels/TokenStatsViewModelObserverTests.swift:209-353`

**Interfaces:**
- Consumes: Task 1 的 optional `TokenUsage.cacheCreation`、计价阶段的 `UsageCostResolver` 和 `ClaudeRecord.costUSD`。
- Produces: direct/AgentProgress 共用的专用 billing DTO 与 `ClaudeNormalizedUsageRecord`；`ParsedUsageEntry.isSidechain` 及 `hasSourceMessageID`；`ClaudeUsageDeduplicator.deduplicate(_:costResolver:) -> [ParsedUsageEntry]`；包含两个字段的 `UsageEntriesFingerprint` 与 test-only deep snapshot。exact key 必须是分字段 Hashable 值，不消费 `ParsedUsageEntry.dedupKey` 的字符串拼接。

- [ ] **Step 1: 建立 deep snapshot 并写出完整 replacement 矩阵的失败测试**

创建 `TokenWatchTests/TestSupport/ParsedUsageEntryDeepSnapshot.swift`：

```swift
import Foundation
@testable import TokenWatch

struct ParsedUsageEntryDeepSnapshot: Equatable {
    let recordUUID: String
    let messageId: String
    let requestId: String?
    let sessionID: String
    let timestamp: Date?
    let model: String
    let cwd: String?
    let agentId: String?
    let inputTokens: Int
    let flatCacheCreationTokens: Int
    let cacheReadTokens: Int
    let outputTokens: Int
    let reasoningTokens: Int
    let cacheCreation1hTokens: Int?
    let cacheCreation5mTokens: Int?
    let webSearchRequests: Int
    let webFetchRequests: Int
    let serviceTier: String
    let inferenceGeo: String
    let iterations: [String]
    let speed: String
    let isSubagent: Bool
    let isSidechain: Bool
    let hasSourceMessageID: Bool
    let provider: ProviderID
    let upstreamProviderID: String?
    let upstreamCost: Double?

    init(_ entry: ParsedUsageEntry) {
        recordUUID = entry.recordUUID
        messageId = entry.messageId
        requestId = entry.requestId
        sessionID = entry.sessionID
        timestamp = entry.timestamp
        model = entry.model
        cwd = entry.cwd
        agentId = entry.agentId
        inputTokens = entry.usage.inputTokens
        flatCacheCreationTokens = entry.usage.cacheCreationInputTokens
        cacheReadTokens = entry.usage.cacheReadInputTokens
        outputTokens = entry.usage.outputTokens
        reasoningTokens = entry.usage.reasoningTokens
        cacheCreation1hTokens = entry.usage.cacheCreation?.ephemeral1hInputTokens
        cacheCreation5mTokens = entry.usage.cacheCreation?.ephemeral5mInputTokens
        webSearchRequests = entry.usage.serverToolUse.webSearchRequests
        webFetchRequests = entry.usage.serverToolUse.webFetchRequests
        serviceTier = entry.usage.serviceTier
        inferenceGeo = entry.usage.inferenceGeo
        iterations = entry.usage.iterations
        speed = entry.usage.speed
        isSubagent = entry.isSubagent
        isSidechain = entry.isSidechain
        hasSourceMessageID = entry.hasSourceMessageID
        provider = entry.provider
        upstreamProviderID = entry.upstreamProviderID
        upstreamCost = entry.upstreamCost
    }

    static func sorted(_ entries: [ParsedUsageEntry]) -> [ParsedUsageEntryDeepSnapshot] {
        entries.map(ParsedUsageEntryDeepSnapshot.init).sorted { lhs, rhs in
            lhs.stableKey < rhs.stableKey
        }
    }

    private var stableKey: String {
        [
            provider.rawValue,
            sessionID,
            messageId,
            requestId ?? "",
            recordUUID,
        ].joined(separator: "|")
    }
}
```

创建 `TokenWatchTests/Providers/Claude/ClaudeUsageDeduplicatorTests.swift`：

```swift
import Foundation
import Testing
@testable import TokenWatch

@Suite("ClaudeUsageDeduplicator")
struct ClaudeUsageDeduplicatorTests {
    @Test("两个非 sidechain 且 requestId 不同的父记录都保留")
    func keepsDistinctParentRequests() {
        let first = entry(record: "parent-a", request: "req-a", input: 10)
        let second = entry(record: "parent-b", request: "req-b", input: 20)

        let result = ClaudeUsageDeduplicator.deduplicate([first, second])

        #expect(ParsedUsageEntryDeepSnapshot.sorted(result) ==
            ParsedUsageEntryDeepSnapshot.sorted([first, second]))
    }

    @Test("同 messageId 的 sidechain replay 与父记录合并且父记录优先")
    func parentWinsAcrossSidechainReplay() {
        let sidechain = entry(
            record: "side",
            request: "req-side",
            input: 9_000,
            isSidechain: true
        )
        let parent = entry(record: "parent", request: "req-parent", input: 10)

        let forward = ClaudeUsageDeduplicator.deduplicate([sidechain, parent])
        let reverse = ClaudeUsageDeduplicator.deduplicate([parent, sidechain])

        #expect(ParsedUsageEntryDeepSnapshot.sorted(forward) ==
            ParsedUsageEntryDeepSnapshot.sorted([parent]))
        #expect(ParsedUsageEntryDeepSnapshot.sorted(reverse) ==
            ParsedUsageEntryDeepSnapshot.sorted([parent]))
    }

    @Test("同类 duplicate 依次比较 magnitude、Auto cost 和 speed")
    func sameClassUsesMagnitudeThenCostThenSpeedPresence() {
        let small = entry(record: "small", request: "same", input: 10)
        let large = entry(record: "large", request: "same", input: 20)
        let lowerCost = entry(
            record: "lower-cost",
            request: "cost-tie",
            input: 25,
            upstreamCost: 0.1
        )
        let higherCost = entry(
            record: "higher-cost",
            request: "cost-tie",
            input: 25,
            upstreamCost: 0.2
        )
        let standard = entry(record: "standard", request: "tie", input: 30)
        let fast = entry(record: "fast", request: "tie", input: 30, speed: "fast")

        let result = ClaudeUsageDeduplicator.deduplicate([
            small, large, lowerCost, higherCost, standard, fast,
        ])

        #expect(Set(result.map(\.recordUUID)) == Set(["large", "higher-cost", "fast"]))
    }

    @Test("exact duplicate 中 parent 优先于更大的 sidechain")
    func exactDuplicateStillUsesParentPriority() {
        let sidechain = entry(
            record: "side",
            request: "same",
            input: 1_000,
            isSidechain: true
        )
        let parent = entry(record: "parent", request: "same", input: 1)

        let result = ClaudeUsageDeduplicator.deduplicate([sidechain, parent])

        #expect(result.map(\.recordUUID) == ["parent"])
    }

    @Test("exact key 按字段比较，不被分隔符拼接碰撞")
    func exactKeyIsStructured() {
        let first = entry(
            record: "first",
            message: "a:b",
            request: "c",
            input: 10
        )
        let second = entry(
            record: "second",
            message: "a",
            request: "b:c",
            input: 20
        )

        #expect(ClaudeUsageDeduplicator.deduplicate([first, second]).count == 2)
    }

    @Test("daily 单遍索引保留 pinned replacement 边界")
    func sidechainReplacementDoesNotBackfillNewExactIndex() {
        let sidechain = entry(
            record: "side",
            request: "r1",
            input: 100,
            isSidechain: true
        )
        let parent = entry(record: "parent", request: "r2", input: 10)
        let repeatedParent = entry(record: "parent-repeat", request: "r2", input: 5)

        let result = ClaudeUsageDeduplicator.deduplicate([
            sidechain, parent, repeatedParent,
        ])

        #expect(result.map(\.recordUUID) == ["parent", "parent-repeat"])
    }

    private func entry(
        record: String,
        message: String = "shared-message",
        request: String,
        input: Int,
        isSidechain: Bool = false,
        speed: String = "",
        upstreamCost: Double? = nil
    ) -> ParsedUsageEntry {
        ParsedUsageEntry(
            recordUUID: record,
            messageId: message,
            requestId: request,
            sessionID: "session",
            timestamp: Date(timeIntervalSince1970: 1_800_000_000),
            model: "claude-sonnet-4-5",
            cwd: "/project",
            agentId: nil,
            usage: TokenUsage(
                inputTokens: input,
                cacheCreationInputTokens: 0,
                cacheReadInputTokens: 0,
                outputTokens: 5,
                serverToolUse: ServerToolUse(webSearchRequests: 0, webFetchRequests: 0),
                serviceTier: "standard",
                cacheCreation: nil,
                inferenceGeo: "",
                iterations: [],
                speed: speed
            ),
            isSubagent: false,
            isSidechain: isSidechain,
            provider: .claude,
            upstreamProviderID: nil,
            upstreamCost: upstreamCost
        )
    }
}
```

- [ ] **Step 2: 写出 record 传播、isSubagent 隔离和 fingerprint 的失败测试**

在 `ClaudeJSONLParserTests.swift` 增加：

```swift
@Test("文件级 subagent 不能替代记录级 sidechain")
func subagentFileWithoutSidechainKeepsDistinctRequest() throws {
    let dir = FileManager.default.temporaryDirectory
        .appendingPathComponent("ClaudeSidechain-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: dir) }
    let parentURL = dir.appendingPathComponent("parent.jsonl")
    let subagentURL = dir.appendingPathComponent("agent.jsonl")
    let parentLine = #"{"type":"assistant","uuid":"parent","sessionId":"s","timestamp":"2026-06-13T11:55:26.715Z","requestId":"req-parent","isSidechain":false,"message":{"id":"shared","role":"assistant","model":"claude-sonnet-4-5","usage":{"input_tokens":10,"output_tokens":5}}}"#
    let subagentLine = #"{"type":"assistant","uuid":"subagent","sessionId":"s","timestamp":"2026-06-13T11:55:27.715Z","requestId":"req-subagent","isSidechain":false,"message":{"id":"shared","role":"assistant","model":"claude-sonnet-4-5","usage":{"input_tokens":20,"output_tokens":5}}}"#
    try (parentLine + "\n").write(to: parentURL, atomically: true, encoding: .utf8)
    try (subagentLine + "\n").write(to: subagentURL, atomically: true, encoding: .utf8)
    let files = [
        ClaudeJSONLFileInfo(
            url: parentURL,
            sessionID: "s",
            projectPath: "/project",
            isSubagent: false,
            agentId: nil
        ),
        ClaudeJSONLFileInfo(
            url: subagentURL,
            sessionID: "s",
            projectPath: "/project",
            isSubagent: true,
            agentId: "agent"
        ),
    ]

    let entries = try ClaudeJSONLParser().parseAllFiles(files, claudeDataRoot: dir)

    #expect(entries.count == 2)
    #expect(entries.allSatisfy { !$0.isSidechain })
    #expect(entries.contains { $0.isSubagent })
}

@Test("记录级 sidechain replay 被父记录替换")
func recordSidechainReplayIsReplacedByParent() throws {
    let dir = FileManager.default.temporaryDirectory
        .appendingPathComponent("ClaudeReplay-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: dir) }
    let parentURL = dir.appendingPathComponent("parent.jsonl")
    let sidechainURL = dir.appendingPathComponent("sidechain.jsonl")
    let parentLine = #"{"type":"assistant","uuid":"parent","sessionId":"s","timestamp":"2026-06-13T11:55:26.715Z","requestId":"req-parent","isSidechain":false,"message":{"id":"shared","role":"assistant","model":"claude-sonnet-4-5","usage":{"input_tokens":10,"output_tokens":5}}}"#
    let sidechainLine = #"{"type":"assistant","uuid":"sidechain","sessionId":"s","timestamp":"2026-06-13T11:55:28.715Z","requestId":"req-sidechain","isSidechain":true,"message":{"id":"shared","role":"assistant","model":"claude-sonnet-4-5","usage":{"input_tokens":999,"output_tokens":5}}}"#
    try (parentLine + "\n").write(to: parentURL, atomically: true, encoding: .utf8)
    try (sidechainLine + "\n").write(to: sidechainURL, atomically: true, encoding: .utf8)
    let files = [
        ClaudeJSONLFileInfo(
            url: sidechainURL,
            sessionID: "s",
            projectPath: "/project",
            isSubagent: true,
            agentId: "agent"
        ),
        ClaudeJSONLFileInfo(
            url: parentURL,
            sessionID: "s",
            projectPath: "/project",
            isSubagent: false,
            agentId: nil
        ),
    ]

    let entries = try ClaudeJSONLParser().parseAllFiles(files, claudeDataRoot: dir)

    #expect(entries.count == 1)
    #expect(entries.first?.recordUUID == "parent")
    #expect(entries.first?.isSidechain == false)
}

@Test("direct 与 AgentProgress usage 按 daily.rs 归一化")
func directAndAgentProgressUsageAreBothCounted() throws {
    let direct = #"{"timestamp":"2026-06-13T12:00:00Z","costUSD":0.125,"message":{"usage":{"input_tokens":10,"output_tokens":2}}}"#
    let agentProgress = #"{"data":{"message":{"timestamp":"2026-06-13T12:00:01Z","requestId":"req-agent","isSidechain":true,"costUSD":0.25,"message":{"id":"agent-message","model":"claude-sonnet-4-5","usage":{"input_tokens":20,"output_tokens":3}}}}}"#
    let (file, root, cleanup) = try makeClaudeJSONL([direct, agentProgress])
    defer { cleanup() }

    let entries = try ClaudeJSONLParser().parseJSONLFile(file, claudeDataRoot: root)
        .sorted { ($0.timestamp ?? .distantPast) < ($1.timestamp ?? .distantPast) }

    #expect(entries.count == 2)
    #expect(entries[0].messageId.hasPrefix("missing-message:"))
    #expect(entries[0].model == "")
    #expect(entries[0].upstreamCost == 0.125)
    #expect(entries[1].messageId == "agent-message")
    #expect(entries[1].requestId == "req-agent")
    #expect(entries[1].isSidechain)
    #expect(entries[1].upstreamCost == 0.25)
}

@Test("optional 缺失可接受，显式空值与非 semver version 被过滤")
func dailyPresenceValidationMatchesCCUsage() throws {
    let missingOptional = #"{"timestamp":"2026-06-13T12:00:00Z","message":{"usage":{"input_tokens":1,"output_tokens":1}}}"#
    let emptyRequest = #"{"timestamp":"2026-06-13T12:00:01Z","requestId":"","message":{"id":"m1","model":"claude-sonnet-4-5","usage":{"input_tokens":2,"output_tokens":1}}}"#
    let emptyModel = #"{"timestamp":"2026-06-13T12:00:02Z","message":{"id":"m2","model":"","usage":{"input_tokens":3,"output_tokens":1}}}"#
    let badVersion = #"{"timestamp":"2026-06-13T12:00:03Z","version":"dev-build","message":{"id":"m3","model":"claude-sonnet-4-5","usage":{"input_tokens":4,"output_tokens":1}}}"#
    let (file, root, cleanup) = try makeClaudeJSONL([
        missingOptional, emptyRequest, emptyModel, badVersion,
    ])
    defer { cleanup() }

    let entries = try ClaudeJSONLParser().parseJSONLFile(file, claudeDataRoot: root)

    #expect(entries.count == 1)
    #expect(entries.first?.usage.inputTokens == 1)
}

@Test("daily raw prefilter 精确复制 usage marker 与 compact null guard")
func dailyRawPrefilterMatchesCCUsage() throws {
    let compact = #"{"timestamp":"2026-06-13T12:00:00Z","message":{"id":"kept","model":"claude-sonnet-4-5","usage":{"input_tokens":1,"output_tokens":1}}}"#
    let spacedMarker = #"{"timestamp":"2026-06-13T12:00:01Z","costUSD":1,"message":{"id":"spaced","model":"claude-sonnet-4-5","usage": {"input_tokens":2,"output_tokens":1}}}"#
    let guardedNull = #"{"timestamp":"2026-06-13T12:00:02Z","costUSD":null,"message":{"id":"null","model":"claude-sonnet-4-5","usage":{"input_tokens":3,"output_tokens":1}}}"#
    let (file, root, cleanup) = try makeClaudeJSONL([
        compact, spacedMarker, guardedNull,
    ])
    defer { cleanup() }

    let entries = try ClaudeJSONLParser().parseJSONLFile(file, claudeDataRoot: root)

    #expect(entries.map(\.messageId) == ["kept"])
}

@Test("daily billing DTO 严格限制 token、speed 和 timestamp，忽略无关字段")
func dailyBillingShapeIsStrictButNarrow() throws {
    let unrelatedGarbage = #"{"timestamp":"2026-06-13T12:00:00.000Z","message":{"id":"kept","model":"claude-sonnet-4-5","role":{"bad":true},"content":42,"usage":{"input_tokens":1,"output_tokens":1,"speed":"fast"}}}"#
    let negative = #"{"timestamp":"2026-06-13T12:00:01.000Z","message":{"id":"negative","model":"claude-sonnet-4-5","usage":{"input_tokens":-1,"output_tokens":1}}}"#
    let badSpeed = #"{"timestamp":"2026-06-13T12:00:02.000Z","message":{"id":"speed","model":"claude-sonnet-4-5","usage":{"input_tokens":1,"output_tokens":1,"speed":"turbo"}}}"#
    let excessFraction = #"{"timestamp":"2026-06-13T12:00:03.123456Z","message":{"id":"time","model":"claude-sonnet-4-5","usage":{"input_tokens":1,"output_tokens":1}}}"#
    let (file, root, cleanup) = try makeClaudeJSONL([
        unrelatedGarbage, negative, badSpeed, excessFraction,
    ])
    defer { cleanup() }

    let entries = try ClaudeJSONLParser().parseJSONLFile(file, claudeDataRoot: root)

    #expect(entries.map(\.messageId) == ["kept"])
}
```

同时替换既有“缺 model / 缺 message.id 即跳过”断言：缺失字段必须保留 usage，只有字段存在且为空字符串时跳过。`makeClaudeJSONL(_:)` 在本 test file 内创建唯一临时目录、JSONL 与 `ClaudeJSONLFileInfo`，并返回 cleanup；不依赖用户真实 `~/.claude`。

在 `ClaudeJSONLScannerTests.swift` 创建两层目录与乱序文件，断言 `scanAll` 结果严格按 `url.standardizedFileURL.path` 字典序排列；该顺序是 daily 单遍 replacement 的可观察输入，不得依赖 `FileManager` 枚举顺序。

在 `TokenStatsViewModelObserverTests.swift` 把 test helper 增加 `isSidechain: Bool = false`，并加入：

```swift
@Test func usageFingerprintIncludesSidechain() {
    let usage = makeUsage(cacheCreation5m: 0, cacheCreation1h: 0)
    let parent = makeEntry(id: .claude, usage: usage, isSidechain: false)
    let sidechain = makeEntry(id: .claude, usage: usage, isSidechain: true)

    #expect(UsageEntriesFingerprint.make(from: [parent]) !=
        UsageEntriesFingerprint.make(from: [sidechain]))
}

private func makeEntry(
    id: ProviderID,
    usage: TokenUsage,
    isSidechain: Bool = false
) -> ParsedUsageEntry {
    ParsedUsageEntry(
        recordUUID: "record-1",
        messageId: "message-1",
        requestId: nil,
        sessionID: "session-1",
        timestamp: Date(timeIntervalSince1970: 1_800_000_000),
        model: "claude-sonnet-4-5",
        cwd: "/test",
        agentId: nil,
        usage: usage,
        isSubagent: false,
        isSidechain: isSidechain,
        provider: id,
        upstreamProviderID: nil,
        upstreamCost: nil
    )
}
```

- [ ] **Step 3: 运行测试并确认 RED**

Run:

```bash
xcodebuild -project TokenWatch.xcodeproj -scheme TokenWatch -destination 'platform=macOS' \
  -only-testing:TokenWatchTests/ClaudeUsageDeduplicatorTests \
  -only-testing:TokenWatchTests/ClaudeJSONLParserTests \
  -only-testing:TokenWatchTests/ClaudeJSONLScannerTests \
  -only-testing:TokenWatchTests/TokenStatsViewModelObserverTests/usageFingerprintIncludesSidechain \
  -skip-testing:TokenWatchUITests -derivedDataPath .build/DerivedData CODE_SIGN_STYLE=Manual DEVELOPMENT_TEAM= CODE_SIGN_IDENTITY=- test
```

Expected: FAIL；`ParsedUsageEntry.isSidechain` 和 `ClaudeUsageDeduplicator` 尚不存在，当前 parser 也不会传播 record sidechain。

- [ ] **Step 4: 增加 ParsedUsageEntry 字段与稳定初始化器**

在 `ParsedUsageEntry.swift` 的 `isSubagent` 后加入字段，并用显式初始化器保留所有既有 call site：

```swift
let isSubagent: Bool
let isSidechain: Bool
let hasSourceMessageID: Bool

init(
    recordUUID: String,
    messageId: String,
    requestId: String?,
    sessionID: String,
    timestamp: Date?,
    model: String,
    cwd: String?,
    agentId: String?,
    usage: TokenUsage,
    isSubagent: Bool,
    isSidechain: Bool = false,
    hasSourceMessageID: Bool = true,
    provider: ProviderID,
    upstreamProviderID: String?,
    upstreamCost: Double?
) {
    self.recordUUID = recordUUID
    self.messageId = messageId
    self.requestId = requestId
    self.sessionID = sessionID
    self.timestamp = timestamp
    self.model = model
    self.cwd = cwd
    self.agentId = agentId
    self.usage = usage
    self.isSubagent = isSubagent
    self.isSidechain = isSidechain
    self.hasSourceMessageID = hasSourceMessageID
    self.provider = provider
    self.upstreamProviderID = upstreamProviderID
    self.upstreamCost = upstreamCost
}
```

保持 `Hashable`/`Equatable` 继续只使用 `dedupKey`；业务深比较只使用 test-only snapshot。

在 `ClaudeRecord.swift` 中增加专用 `ClaudeBillingUsage`、`ClaudeUsageLine` 与下列归一化值；不直接复用包含 role/content/server-tool 等非计价字段的 `ClaudeMessage`。解码时先尝试 direct envelope，再尝试 `data.message` AgentProgress envelope，两者都必须有 timestamp 与 usage：

```swift
struct ClaudeNormalizedUsageRecord: Sendable {
    let recordUUID: String?
    let sessionID: String?
    let timestamp: Date
    let version: String?
    let messageID: String?
    let model: String?
    let usage: ClaudeBillingUsage
    let requestID: String?
    let isSidechain: Bool
    let cwd: String?
    let costUSD: Double?
}
```

`ClaudeBillingUsage` 只解码 ccusage `TokenUsageRaw` 参与 daily 成本/去重的字段；token 必须是非负整数，`speed` 只接受缺失/`standard`/`fast`，cache breakdown child 缺失默认 0 但显式 null 使整行解码失败。timestamp 用专用 parser 只接受无小数或正好 3 位毫秒，以 `Z` 或 `±HH:MM` 结尾。billing DTO 不解码 role/content/reasoning text/server-tool 等无关字段，因此它们的坏类型不能否决 usage。转换为统一 `TokenUsage` 时再执行 Task 1 的 cache-creation presence 映射。

每行解码前先对 raw bytes 执行 pinned prefilter：必须包含精确 bytes `"usage":{`，并跳过含 compact `:null` 的受限字段：`id/cwd/model/speed/costUSD/version/sessionId/requestId/isApiErrorMessage/cache_read_input_tokens/cache_creation_input_tokens`。不对 JSON 先重新格式化，因为空白差异就是 pinned daily adapter 的可观察行选择契约。

direct 保留顶层 `uuid/sessionId/version/cwd`；AgentProgress 的这些字段为 nil，但从 `data.message` 保留 timestamp/requestId/isSidechain/costUSD/message。归一化后先调用 `isValidDailyUsageRecord`：`version` 存在时要求 semver 前缀，`sessionID/requestID/messageID/model` 只有“存在且为空串”时无效。缺失值的映射为：

```swift
let recordUUID = record.recordUUID ?? "missing-record:\(fileKey):\(lineStartOffset)"
let messageID = record.messageID ?? "missing-message:\(fileKey):\(lineStartOffset)"
let sessionID = record.sessionID ?? fileInfo.sessionID
let model = record.model ?? ""
```

`fileKey` 使用 standardized path，`lineStartOffset` 是该行绝对字节 offset。缺 message id 时 entry 设置 `hasSourceMessageID = false`；synthetic `messageId` 只满足 UI/快照结构，deduplicator 必须直接 append 且不建任何 exact/message index，因此真实 ID 即使恰好等于 synthetic 字符串也不会碰撞。

- [ ] **Step 5: 实现 daily exact-first 单遍去重器并接入 parser**

创建 `TokenWatch/Providers/Claude/ClaudeUsageDeduplicator.swift`：

```swift
import Foundation

/// 复刻 ccusage v20.0.16 daily.rs 的 exact-first / sidechain-fallback 单遍索引。
enum ClaudeUsageDeduplicator {
    private struct ExactKey: Hashable {
        let messageID: String
        let requestID: String?
    }

    static func deduplicate(
        _ candidates: [ParsedUsageEntry],
        costResolver: UsageCostResolver = UsageCostResolver()
    ) -> [ParsedUsageEntry] {
        var winners: [ParsedUsageEntry] = []
        var exactIndexes: [ExactKey: [Int]] = [:]
        var messageIndexes: [String: [Int]] = [:]

        for candidate in candidates {
            guard candidate.hasSourceMessageID else {
                winners.append(candidate)
                continue
            }
            let exactKey = ExactKey(
                messageID: candidate.messageId,
                requestID: candidate.requestId
            )
            let exactIndex = exactIndexes[exactKey]?.first { index in
                winners[index].messageId == candidate.messageId
                    && winners[index].requestId == candidate.requestId
            }
            let candidateIsSidechain = candidate.isSidechain
            let replayIndex = exactIndex == nil
                ? messageIndexes[candidate.messageId]?.first { index in
                    let existing = winners[index]
                    return existing.messageId == candidate.messageId
                        && (candidateIsSidechain || existing.isSidechain)
                }
                : nil

            if let index = exactIndex ?? replayIndex {
                if shouldReplace(
                    winners[index],
                    with: candidate,
                    costResolver: costResolver
                ) {
                    winners[index] = candidate
                }
                // pinned daily.rs 在 replacement 分支不为新 key 刷新 index。
                continue
            }

            let index = winners.count
            winners.append(candidate)
            exactIndexes[exactKey, default: []].append(index)
            messageIndexes[candidate.messageId, default: []].append(index)
        }
        return winners
    }

    private static func shouldReplace(
        _ existing: ParsedUsageEntry,
        with candidate: ParsedUsageEntry,
        costResolver: UsageCostResolver
    ) -> Bool {
        if existing.isSidechain != candidate.isSidechain {
            return existing.isSidechain && !candidate.isSidechain
        }

        let existingMagnitude = magnitude(existing.usage)
        let candidateMagnitude = magnitude(candidate.usage)
        if existingMagnitude != candidateMagnitude {
            return candidateMagnitude > existingMagnitude
        }

        let existingCost = costResolver.resolvedCost(for: existing)
        let candidateCost = costResolver.resolvedCost(for: candidate)
        if existingCost != candidateCost {
            return candidateCost > existingCost
        }

        return existing.usage.speed.isEmpty && !candidate.usage.speed.isEmpty
    }

    private static func magnitude(_ usage: TokenUsage) -> Int {
        usage.inputTokens
            + usage.outputTokens
            + usage.cacheReadInputTokens
            + usage.totalCacheCreationTokens
    }
}
```

Claude parser 用 `ClaudeUsageLine.normalized` 构造 entry，传入真实 line offset 后加入：

```swift
isSubagent: fileInfo.isSubagent,
isSidechain: normalized.isSidechain,
hasSourceMessageID: normalized.messageID != nil,
provider: .claude,
upstreamCost: normalized.costUSD,
```

把批量候选数组命名为 `allCandidates`，删除当前 `bestByKey`/`usageMagnitude` 私有实现，批量返回改为：

```swift
let uniqueEntries = ClaudeUsageDeduplicator.deduplicate(allCandidates)
```

per-file `CachedFile.entries` 重命名为 `candidates`，明确它仍保存尚未执行上述全局去重的数组。

- [ ] **Step 6: 把 fingerprint 纳入 sidechain 并运行 GREEN**

在 `UsageEntriesFingerprint.make` 加入：

```swift
hasher.combine(entry.isSubagent)
hasher.combine(entry.isSidechain)
hasher.combine(entry.hasSourceMessageID)
hasher.combine(entry.provider)
```

Run:

```bash
xcodebuild -project TokenWatch.xcodeproj -scheme TokenWatch -destination 'platform=macOS' \
  -only-testing:TokenWatchTests/ClaudeUsageDeduplicatorTests \
  -only-testing:TokenWatchTests/ClaudeJSONLParserTests \
  -only-testing:TokenWatchTests/TokenStatsViewModelObserverTests \
  -skip-testing:TokenWatchUITests -derivedDataPath .build/DerivedData CODE_SIGN_STYLE=Manual DEVELOPMENT_TEAM= CODE_SIGN_IDENTITY=- test
```

Expected: PASS；direct/AgentProgress、raw marker/null guard、专用 billing DTO、timestamp 和 full-path 顺序与 daily.rs 一致；缺 source ID 真正绕过去重；parent 优先、同类 magnitude/Auto cost/speed 排序、结构化 exact key 不碰撞、pinned replacement 边界不被两阶段算法折叠，fingerprint 感知业务字段。

- [ ] **Step 7: 提交 Task 3**

```bash
git add TokenWatch/Models/ParsedUsageEntry.swift \
  TokenWatch/Providers/Claude/ClaudeRecord.swift \
  TokenWatch/Providers/Claude/ClaudeMessage.swift \
  TokenWatch/Providers/Claude/ClaudeJSONLScanner.swift \
  TokenWatch/Providers/Claude/ClaudeUsageDeduplicator.swift \
  TokenWatch/Providers/Claude/ClaudeJSONLParser.swift \
  TokenWatch/ViewModels/TokenStatsViewModel.swift \
  TokenWatchTests/TestSupport/ParsedUsageEntryDeepSnapshot.swift \
  TokenWatchTests/Providers/Claude/ClaudeUsageDeduplicatorTests.swift \
  TokenWatchTests/Providers/Claude/ClaudeJSONLParserTests.swift \
  TokenWatchTests/Providers/Claude/ClaudeJSONLScannerTests.swift \
  TokenWatchTests/ViewModels/TokenStatsViewModelObserverTests.swift
git commit -m "fix(claude): 对齐 daily 行形状与 sidechain 去重"
```

---

### Task 4: 对齐 Codex last-first、replay 与 loader 去重

**Files:**
- Modify: `TokenWatch/Providers/Codex/CodexRecord.swift`
- Modify: `TokenWatch/Providers/Codex/CodexRolloutParser.swift:45-138`
- Modify: `TokenWatchTests/Providers/Codex/CodexRecordTests.swift`
- Modify: `TokenWatchTests/Providers/Codex/CodexRolloutParserTests.swift:33-159`

**Interfaces:**
- Consumes: 计价阶段完成后的 `CodexModelState`、`CodexPricingSpeed` 与 cached clamp 规则。
- Produces: `CodexNormalizedTimestamp`、`CodexUsageCandidate { entry, dedupKey }`，其 dedup key 保留 normalized timestamp string、resolved model、raw input、clamped cached、output、reasoning 与 source total；parser 内的 `previousTotals: CodexTokenCounts?` 供增量阶段原样写入 checkpoint。

- [ ] **Step 1: 写出 last-first、cached clamp、replay 和跨文件去重回归**

在 `CodexRolloutParserTests.swift` 增加：

```swift
@Test("相同 total 仍优先发出非零 last_token_usage")
func repeatedTotalStillEmitsNonzeroLastUsage() throws {
    let repeatedEvent = #"{"timestamp":"2026-05-04T08:36:59.868Z","type":"event_msg","payload":{"type":"token_count","info":{"total_token_usage":{"input_tokens":1000,"cached_input_tokens":300,"output_tokens":200,"reasoning_output_tokens":50,"total_tokens":1200},"last_token_usage":{"input_tokens":1000,"cached_input_tokens":300,"output_tokens":200,"reasoning_output_tokens":50,"total_tokens":1200}}}}"#
    let (file, cleanup) = try makeJsonlFile([
        sessionMeta,
        turnContextGpt5,
        normalEvent,
        repeatedEvent,
    ])
    defer { cleanup() }

    let entries = try CodexRolloutParser().parseFile(file)

    #expect(entries.count == 2)
    #expect(entries.allSatisfy { $0.usage.inputTokens == 700 })
    #expect(entries.allSatisfy { $0.usage.cacheReadInputTokens == 300 })
}

@Test("total 缺失时每条 last_token_usage 仍按既有 fallback 发出")
func missingTotalKeepsLastUsageFallback() throws {
    let first = #"{"timestamp":"2026-05-04T08:35:59.868Z","type":"event_msg","payload":{"type":"token_count","info":{"last_token_usage":{"input_tokens":100,"cached_input_tokens":20,"output_tokens":10,"reasoning_output_tokens":2,"total_tokens":110}}}}"#
    let second = #"{"timestamp":"2026-05-04T08:36:59.868Z","type":"event_msg","payload":{"type":"token_count","info":{"last_token_usage":{"input_tokens":200,"cached_input_tokens":40,"output_tokens":20,"reasoning_output_tokens":4,"total_tokens":220}}}}"#
    let (file, cleanup) = try makeJsonlFile([
        sessionMeta,
        turnContextGpt5,
        first,
        second,
    ])
    defer { cleanup() }

    let entries = try CodexRolloutParser().parseFile(file)

    #expect(entries.count == 2)
    #expect(entries.map { $0.usage.inputTokens }.sorted() == [80, 160])
}

@Test("cached 超过 raw input 时被 clamp")
func cachedInputIsClampedToRawInput() throws {
    let malformed = #"{"timestamp":"2026-05-04T08:36:01.000Z","type":"event_msg","payload":{"type":"token_count","info":{"last_token_usage":{"input_tokens":100,"cached_input_tokens":150,"output_tokens":20,"reasoning_output_tokens":4,"total_tokens":120}}}}"#
    let (file, cleanup) = try makeJsonlFile([sessionMeta, turnContextGpt5, malformed])
    defer { cleanup() }

    let entry = try #require(CodexRolloutParser().parseFile(file).first)

    #expect(entry.usage.inputTokens == 0)
    #expect(entry.usage.cacheReadInputTokens == 100)
    #expect(entry.usage.reasoningTokens == 4)
}

@Test("thread replay 同秒前缀跳过但保留 total baseline")
func replayPrefixIsSkippedWithTotalsAdvanced() throws {
    let replayMeta = #"{"timestamp":"2026-05-04T08:35:40Z","type":"session_meta","payload":{"id":"child","cwd":"/tmp/project","thread_spawn":{"parent":"root"}}}"#
    let first = #"{"timestamp":"2026-05-04T08:35:59.100Z","type":"event_msg","payload":{"type":"token_count","info":{"total_token_usage":{"input_tokens":100,"cached_input_tokens":10,"output_tokens":10,"reasoning_output_tokens":1,"total_tokens":110},"last_token_usage":{"input_tokens":100,"cached_input_tokens":10,"output_tokens":10,"reasoning_output_tokens":1,"total_tokens":110}}}}"#
    let second = #"{"timestamp":"2026-05-04T08:35:59.900Z","type":"event_msg","payload":{"type":"token_count","info":{"total_token_usage":{"input_tokens":200,"cached_input_tokens":20,"output_tokens":20,"reasoning_output_tokens":2,"total_tokens":220},"last_token_usage":{"input_tokens":100,"cached_input_tokens":10,"output_tokens":10,"reasoning_output_tokens":1,"total_tokens":110}}}}"#
    let next = #"{"timestamp":"2026-05-04T08:36:00.100Z","type":"event_msg","payload":{"type":"token_count","info":{"total_token_usage":{"input_tokens":250,"cached_input_tokens":25,"output_tokens":25,"reasoning_output_tokens":3,"total_tokens":275}}}}"#
    let (file, cleanup) = try makeJsonlFile([
        replayMeta, turnContextGpt5, first, second, next,
    ])
    defer { cleanup() }

    let entries = try CodexRolloutParser().parseFile(file)

    #expect(entries.count == 1)
    #expect(entries.first?.usage.inputTokens == 45)
    #expect(entries.first?.usage.cacheReadInputTokens == 5)
    #expect(entries.first?.usage.outputTokens == 5)
}

@Test("跨 session 复制历史按 upstream event key first-wins 去重")
func copiedHistoryDeduplicatesAcrossSessions() throws {
    let metaA = sessionMeta.replacingOccurrences(of: "019df220-aaaa-bbbb-cccc-ddddeeeeffff", with: "session-a")
    let metaB = sessionMeta.replacingOccurrences(of: "019df220-aaaa-bbbb-cccc-ddddeeeeffff", with: "session-b")
    let (fileA, cleanupA) = try makeJsonlFile([metaA, turnContextGpt5, normalEvent], sessionID: "session-a")
    let (fileB, cleanupB) = try makeJsonlFile([metaB, turnContextGpt5, normalEvent], sessionID: "session-b")
    defer { cleanupA(); cleanupB() }

    let entries = try CodexRolloutParser().parseAllFiles([fileA, fileB])

    #expect(entries.count == 1)
    #expect(entries.first?.sessionID == "session-a")
}
```

再加一个反例：两条 event 即使 timestamp/session 相同，只要 model 或任一 raw count（包括 `total_tokens`）不同就必须都保留，防止回退为当前 session+timestamp/magnitude 逻辑。

在 `CodexRecordTests.swift` 再加表驱动 fixture：

- timestamp 字符串、Unix 秒与 Unix 毫秒数字都规范化为同一 `timestampKey`；session token_count 缺失/空/无效 timestamp 在 parser 层跳过。
- usage 数值同时覆盖 `input_tokens/prompt_tokens/input`、`cached_input_tokens/cache_read_input_tokens/cached_tokens`、`output_tokens/completion_tokens/output`、`reasoning_output_tokens/reasoning_tokens`；字符串整数 trim 后接受，负数/浮点/bool/坏字符串当作缺失。
- `total_tokens` 缺失时为 input + output + reasoning；显式 0 仅在三者也全 0 时保留，否则同样回退求和。
- payload `model = "  "` 且 info `model_name = " gpt-5.5 "` 时必须解析为 `gpt-5.5`；零 usage event 即使带 model 也不得更新当前 model。

- [ ] **Step 2: 运行 Codex parity 测试并确认 RED**

Run:

```bash
xcodebuild -project TokenWatch.xcodeproj -scheme TokenWatch -destination 'platform=macOS' \
  -only-testing:TokenWatchTests/CodexRolloutParserTests/repeatedTotalStillEmitsNonzeroLastUsage \
  -only-testing:TokenWatchTests/CodexRolloutParserTests/cachedInputIsClampedToRawInput \
  -only-testing:TokenWatchTests/CodexRolloutParserTests/replayPrefixIsSkippedWithTotalsAdvanced \
  -only-testing:TokenWatchTests/CodexRolloutParserTests/copiedHistoryDeduplicatesAcrossSessions \
  -skip-testing:TokenWatchUITests -derivedDataPath .build/DerivedData CODE_SIGN_STYLE=Manual DEVELOPMENT_TEAM= CODE_SIGN_IDENTITY=- test
```

Expected: RED 来自 cached 未 clamp、replay 未分类或跨 session 未去重；`repeatedTotalStillEmitsNonzeroLastUsage` 应在移除旧计划的自定义抑制后锁定为 PASS。

- [ ] **Step 3: 保留 raw candidate 并复制 upstream 顺序**

将 parser 初始状态改为：

```swift
var previousTotals: CodexTokenCounts?
```

新增内部 raw wrapper，per-file cache 保存它而不是只保存已丢失 source total 的 `[ParsedUsageEntry]`：

```swift
struct CodexNormalizedTimestamp: Sendable, Equatable {
    let key: String
    let date: Date
}

struct CodexEventDedupKey: Hashable, Sendable {
    let timestampKey: String
    let model: String
    let rawInput: Int
    let cachedInput: Int
    let output: Int
    let reasoning: Int
    let total: Int
}

struct CodexUsageCandidate: Sendable {
    let entry: ParsedUsageEntry
    let dedupKey: CodexEventDedupKey
}

struct CodexNormalizedTokenCounts: Sendable, Equatable {
    let rawInput: Int
    let pureInput: Int
    let cachedInput: Int
    let output: Int
    let reasoning: Int
    let total: Int
}

extension CodexTokenCounts {
    var normalizedForBilling: CodexNormalizedTokenCounts {
        let rawInput = max(0, inputTokens)
        let cachedInput = min(max(0, cachedInputTokens), rawInput)
        return CodexNormalizedTokenCounts(
            rawInput: rawInput,
            pureInput: rawInput - cachedInput,
            cachedInput: cachedInput,
            output: max(0, outputTokens),
            reasoning: max(0, reasoningOutputTokens),
            total: max(0, totalTokens)
        )
    }
}
```

token_count 处理顺序固定为：选 last 或 total delta → 更新 totals → 跳过四维全零 → 解析 model → clamp cached → 构造 candidate。不加 repeated-total guard：

```swift
let delta: CodexTokenCounts
if let last = info.lastTokenUsage {
    delta = last
} else if let total = info.totalTokenUsage {
    delta = total.subtracting(previousTotals ?? .zero)
} else {
    return
}
if let total = info.totalTokenUsage {
    previousTotals = total
}
guard !delta.isAllZero else { return }

let model = CodexModelResolver.resolve(
    parsedModel: event.preferredModel ?? info.preferredModel,
    eventDate: record.timestamp,
    current: &currentModel
)
let normalized = delta.normalizedForBilling
```

在 `CodexTurnContext`、event payload 与 `CodexTokenCountInfo` 上实现 `preferredModel`，每一层按 `model → model_name → metadata.model` 取 trim 后的第一个非空值；event payload miss 才读 info，不得让空 payload model 遮蔽 info 真值。

`CodexRecord` 将 timestamp 解码为保留 normalized RFC3339-millis 文本与 `Date` 的小值类型：字符串按现有 RFC3339 规则规范，数字 `< 10^12` 按 Unix 秒、否则按毫秒，并 saturate 到可表示范围。session token_count 的 nil/空/无效 timestamp 跳过，不合成 UUID 或 offset；`timestampKey` 直接用 normalized 文本。

`CodexRecord` 将原 `let timestamp: Date?` 替换为 `let normalizedTimestamp: CodexNormalizedTimestamp?`，并提供兼容计算属性 `var timestamp: Date? { normalizedTimestamp?.date }`；`CodingKeys.timestamp` 保持不变。

`CodexTokenCounts` 用专用 lossy unsigned decoder 复制上述 alias 优先级与 total normalization；不能使用 `decodeIfPresent(Int.self)` 令一个坏字段否决整个 usage object。Swift 转统一 `Int` 时将大于 `Int.max` 的 u64 夹到 `Int.max`，不溢出。`TokenUsage` 写入 pure input、clamped cached、output 和 reasoning，cache creation 为 nil。

replay 预检严格使用以下规则：只在文件前 16 KiB 包含 `thread_spawn` 或 `forked_from_id` 时查看前两条有 usage 的 session token_count；两者规范 timestamp 前 19 字节相同才生成 `replaySecond`。该秒内的前缀 event 不 emit，但每条 total 仍更新 baseline；首个异秒 event 关闭 skip。Task 6 将这两次预检也路由到可注入 reader。

```swift
enum CodexReplayClassification: Sendable, Equatable {
    case notReplay
    case pending
    case replay(second: String)

    var replaySecond: String? {
        guard case .replay(let second) = self else { return nil }
        return second
    }
}
```

marker 不存在或前两条 usage 已证明异秒时返回 `.notReplay`；marker 存在但少于两条有效 usage 时返回 `.pending`；同秒时返回 `.replay(second:)`。全量 parser 用该分类初始化 skip state；增量阶段必须保留 `.pending` 以处理后续追加的第二条 usage。

`parseFile` 是 `parseCandidates(...).map(\.entry)` 的公开兼容层。`parseAllFiles` 汇总 `CodexUsageCandidate`，用 `Set<CodexEventDedupKey>` 按输入顺序 first-wins，最后才 map entry；不再使用 session-based `dedupKey` 或 magnitude replacement。

- [ ] **Step 4: 运行 Codex parser 全套并确认 GREEN**

Run:

```bash
xcodebuild -project TokenWatch.xcodeproj -scheme TokenWatch -destination 'platform=macOS' \
  -only-testing:TokenWatchTests/CodexRolloutParserTests \
  -only-testing:TokenWatchTests/CodexRecordTests \
  -skip-testing:TokenWatchUITests -derivedDataPath .build/DerivedData CODE_SIGN_STYLE=Manual DEVELOPMENT_TEAM= CODE_SIGN_IDENTITY=- test
```

Expected: PASS；last-first、total fallback、cached clamp、零 usage 守卫、model 候选、replay baseline 与跨 session first-wins key 全部与 pinned Codex adapter 一致。

- [ ] **Step 5: 提交 Task 4**

```bash
git add TokenWatch/Providers/Codex/CodexRolloutParser.swift \
  TokenWatch/Providers/Codex/CodexRecord.swift \
  TokenWatchTests/Providers/Codex/CodexRecordTests.swift \
  TokenWatchTests/Providers/Codex/CodexRolloutParserTests.swift
git commit -m "fix(codex): 对齐 rollout replay 与跨文件去重"
```

---

### Task 5: 用 json_valid 隔离 OpenCode 损坏 JSON

**Files:**
- Modify: `TokenWatch/Providers/OpenCode/OpenCodeSQLiteScanner.swift:64-78`
- Modify: `TokenWatchTests/Providers/OpenCode/OpenCodeSQLiteScannerTests.swift:20-47`

**Interfaces:**
- Consumes: 现有 `OpenCodeSQLiteScanner.assistantMessageQuery` 和 mini SQLite fixture。
- Produces: SQL 层保证 malformed `message.data` 不进入 `json_extract`，其余合法 assistant rows 继续按 `time_created` 返回。

- [ ] **Step 1: 在 mini DB 加入一条 malformed JSON 的失败测试**

在 `OpenCodeSQLiteScannerTests.swift` 增加：

```swift
@Test("损坏 JSON 被跳过且其他 assistant 行继续返回")
func malformedJSONDoesNotAbortAssistantQuery() throws {
    let dir = try makeTempDir()
    defer { try? FileManager.default.removeItem(at: dir) }

    try buildMiniDB(
        at: dir.appendingPathComponent("opencode.db"),
        sessions: [("ses", "/project")],
        messages: [
            (
                "valid-before",
                "ses",
                100,
                #"{"role":"assistant","tokens":{"input":1,"output":1,"reasoning":0,"cache":{"read":0,"write":0}}}"#
            ),
            ("broken", "ses", 200, "{not-json"),
            (
                "valid-after",
                "ses",
                300,
                #"{"role":"assistant","tokens":{"input":2,"output":2,"reasoning":0,"cache":{"read":0,"write":0}}}"#
            ),
            ("user", "ses", 400, #"{"role":"user"}"#),
        ]
    )

    let rows = try scanner.scanAll(in: dir)

    #expect(rows.map(\.id) == ["valid-before", "valid-after"])
}
```

- [ ] **Step 2: 运行测试并确认 RED**

Run:

```bash
xcodebuild -project TokenWatch.xcodeproj -scheme TokenWatch -destination 'platform=macOS' \
  -only-testing:TokenWatchTests/OpenCodeSQLiteScannerTests/malformedJSONDoesNotAbortAssistantQuery \
  -skip-testing:TokenWatchUITests -derivedDataPath .build/DerivedData CODE_SIGN_STYLE=Manual DEVELOPMENT_TEAM= CODE_SIGN_IDENTITY=- test
```

Expected: FAIL；当前 query 在 `json_extract` 遇到 malformed JSON 时抛出 `OpenCodeScannerError.queryFailed`。

- [ ] **Step 3: 在 SQL 中先用 json_valid 保护 role 提取**

把 `assistantMessageQuery` 改为：

```swift
static let assistantMessageQuery = """
SELECT m.id,
       m.session_id,
       m.time_created,
       m.data,
       s.directory
FROM message AS m
JOIN session AS s ON m.session_id = s.id
WHERE CASE
        WHEN json_valid(m.data)
        THEN json_extract(m.data, '$.role') = 'assistant'
        ELSE 0
      END
ORDER BY m.time_created;
"""
```

- [ ] **Step 4: 运行 scanner 与 parser 测试并确认 GREEN**

Run:

```bash
xcodebuild -project TokenWatch.xcodeproj -scheme TokenWatch -destination 'platform=macOS' \
  -only-testing:TokenWatchTests/OpenCodeSQLiteScannerTests \
  -only-testing:TokenWatchTests/OpenCodeMessageParserTests \
  -skip-testing:TokenWatchUITests -derivedDataPath .build/DerivedData CODE_SIGN_STYLE=Manual DEVELOPMENT_TEAM= CODE_SIGN_IDENTITY=- test
```

Expected: PASS；malformed row 在 SQL 层跳过，合法 rows 仍排序返回，parser 自身的 invalid JSON 容错保持通过。

- [ ] **Step 5: 提交 Task 5**

```bash
git add TokenWatch/Providers/OpenCode/OpenCodeSQLiteScanner.swift \
  TokenWatchTests/Providers/OpenCode/OpenCodeSQLiteScannerTests.swift
git commit -m "fix(opencode): 跳过损坏的消息 JSON"
```

---

### Task 6: 落地共享 JSONL reader 与 last-good cache

**Files:**
- Create: `TokenWatch/Providers/JSONLFileReader.swift`
- Modify: `TokenWatch/Providers/Claude/ClaudeJSONLParser.swift:14-242`
- Modify: `TokenWatch/Providers/Codex/CodexRolloutParser.swift:14-250`
- Create: `TokenWatchTests/TestSupport/RecordingJSONLFileReader.swift`
- Create: `TokenWatchTests/Providers/JSONLFileReaderTests.swift`
- Modify: `TokenWatchTests/Providers/Claude/ClaudeJSONLParserTests.swift:193-305`
- Modify: `TokenWatchTests/Providers/Codex/CodexRolloutParserTests.swift:149-184`

**Interfaces:**
- Consumes: Task 3 的 Claude raw candidates 与 `ClaudeUsageDeduplicator.deduplicate(_:)`，Task 4 的 `CodexUsageCandidate`、replay classifier 与 optional `previousTotals` reducer。
- Produces: `JSONLFileIdentity`、`JSONLFileMetadata`、`JSONLByteStream`、`JSONLFileReading`、`SystemJSONLFileReader`；Claude/Codex `init(fileReader:)`；发现文件失败时返回 per-file last-good candidates。下一阶段增量解析必须原样复用这些 reader 签名。

- [ ] **Step 1: 写出生产 reader round-trip 和可控失败 test seam**

创建 `TokenWatchTests/TestSupport/RecordingJSONLFileReader.swift`；它通过同一 `openSnapshot` 提供 descriptor metadata 与 stream，既支持 metadata/open/seek/read 故障注入，也记录下一阶段增量 I/O 契约需要的 metadata、open 次数、seek offset 和实际读取字节数：

```swift
import Foundation
@testable import TokenWatch

enum RecordingJSONLReaderError: Error {
    case injectedMetadataFailure
    case injectedOpenFailure
    case injectedSeekFailure
    case injectedReadFailure
}

final class RecordingJSONLFileReader: JSONLFileReading, @unchecked Sendable {
    enum Failure: Sendable, Equatable {
        case none
        case metadata
        case open
        case seek
        case read
    }

    private let base: any JSONLFileReading
    private let lock = NSLock()
    private var storedFailure: Failure = .none
    private var storedOpenCount = 0
    private var storedTotalBytesRead = 0
    private var storedSeekOffsets: [UInt64] = []
    private var storedLatestMetadata: JSONLFileMetadata?

    init(base: any JSONLFileReading = SystemJSONLFileReader()) {
        self.base = base
    }

    var failure: Failure {
        get {
            lock.lock()
            defer { lock.unlock() }
            return storedFailure
        }
        set {
            lock.lock()
            storedFailure = newValue
            lock.unlock()
        }
    }

    var openCount: Int { withLock { storedOpenCount } }
    var totalBytesRead: Int { withLock { storedTotalBytesRead } }
    var seekOffsets: [UInt64] { withLock { storedSeekOffsets } }
    var latestMetadata: JSONLFileMetadata? { withLock { storedLatestMetadata } }

    func resetMetrics() {
        withLock {
            storedOpenCount = 0
            storedTotalBytesRead = 0
            storedSeekOffsets = []
            storedLatestMetadata = nil
        }
    }

    func openSnapshot(for url: URL) throws -> JSONLFileSnapshot {
        let failure = self.failure
        if failure == .metadata {
            throw RecordingJSONLReaderError.injectedMetadataFailure
        }
        if failure == .open {
            throw RecordingJSONLReaderError.injectedOpenFailure
        }
        let snapshot = try base.openSnapshot(for: url)
        withLock {
            storedOpenCount += 1
            storedLatestMetadata = snapshot.metadata
        }
        let stream = RecordingJSONLByteStream(
            base: snapshot.stream,
            failure: failure,
            recordSeek: { [weak self] offset in
                guard let self else { return }
                self.withLock { self.storedSeekOffsets.append(offset) }
            },
            recordRead: { [weak self] count in
                guard let self else { return }
                self.withLock { self.storedTotalBytesRead += count }
            }
        )
        return JSONLFileSnapshot(metadata: snapshot.metadata, stream: stream)
    }

    @discardableResult
    private func withLock<T>(_ body: () -> T) -> T {
        lock.lock()
        defer { lock.unlock() }
        return body()
    }
}

private final class RecordingJSONLByteStream: JSONLByteStream, @unchecked Sendable {
    private let base: any JSONLByteStream
    private let failure: RecordingJSONLFileReader.Failure
    private let recordSeek: (UInt64) -> Void
    private let recordRead: (Int) -> Void

    init(
        base: any JSONLByteStream,
        failure: RecordingJSONLFileReader.Failure,
        recordSeek: @escaping (UInt64) -> Void,
        recordRead: @escaping (Int) -> Void
    ) {
        self.base = base
        self.failure = failure
        self.recordSeek = recordSeek
        self.recordRead = recordRead
    }

    func seek(toOffset offset: UInt64) throws {
        if failure == .seek {
            throw RecordingJSONLReaderError.injectedSeekFailure
        }
        try base.seek(toOffset: offset)
        recordSeek(offset)
    }

    func read(upToCount count: Int) throws -> Data {
        if failure == .read {
            throw RecordingJSONLReaderError.injectedReadFailure
        }
        let data = try base.read(upToCount: count)
        recordRead(data.count)
        return data
    }

    func close() {
        base.close()
    }
}
```

创建 `TokenWatchTests/Providers/JSONLFileReaderTests.swift`：

```swift
import Foundation
import Testing
@testable import TokenWatch

@Suite("JSONLFileReader")
struct JSONLFileReaderTests {
    @Test("生产 reader 返回身份大小修改时间并支持 seek read")
    func systemReaderReportsMetadataAndReadsFromOffset() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("JSONLFileReaderTests-\(UUID().uuidString).jsonl")
        try Data("abcdef".utf8).write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }

        let reader = SystemJSONLFileReader()
        let snapshot = try reader.openSnapshot(for: url)
        defer { snapshot.stream.close() }
        try snapshot.stream.seek(toOffset: 2)
        let data = try snapshot.stream.read(upToCount: 3)

        #expect(snapshot.metadata.identity != nil)
        #expect(snapshot.metadata.size == 6)
        #expect(snapshot.metadata.modificationDate != .distantPast)
        #expect(String(decoding: data, as: UTF8.self) == "cde")
    }

    @Test("atomic replace 后 snapshot metadata 与已打开 stream 指向同一文件")
    func snapshotClosesMetadataOpenTOCTOU() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("JSONLSnapshot-\(UUID().uuidString).jsonl")
        try Data("old".utf8).write(to: url, options: .atomic)
        defer { try? FileManager.default.removeItem(at: url) }
        let reader = SystemJSONLFileReader()
        let old = try reader.openSnapshot(for: url)
        defer { old.stream.close() }

        try Data("replacement".utf8).write(to: url, options: .atomic)
        let fresh = try reader.openSnapshot(for: url)
        defer { fresh.stream.close() }
        let oldData = try old.stream.read(upToCount: 64)
        let freshData = try fresh.stream.read(upToCount: 64)

        #expect(String(decoding: oldData, as: UTF8.self) == "old")
        #expect(String(decoding: freshData, as: UTF8.self) == "replacement")
        #expect(old.metadata.identity != fresh.metadata.identity)
    }
}
```

- [ ] **Step 2: 写出 Claude/Codex last-good、首次失败与真实删除测试**

在 `ClaudeJSONLParserTests.swift` 增加：

```swift
@Test("已成功文件的 stat open seek read 失败均复用 last-good，scanner 删除后 prune")
func transientReaderFailuresReuseLastGoodUntilScannerOmitsFile() throws {
    let dir = FileManager.default.temporaryDirectory
        .appendingPathComponent("ClaudeLastGood-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: dir) }

    let url = dir.appendingPathComponent("session.jsonl")
    let first = Self.assistantLine(messageId: "first", inputTokens: 10)
    let second = Self.assistantLine(messageId: "second", inputTokens: 20)
    try (first + "\n").write(to: url, atomically: true, encoding: .utf8)
    let info = ClaudeJSONLFileInfo(
        url: url,
        sessionID: "session",
        projectPath: "/project",
        isSubagent: false,
        agentId: nil
    )
    let reader = RecordingJSONLFileReader()
    let parser = ClaudeJSONLParser(fileReader: reader)

    let initial = try parser.parseAllFiles([info], claudeDataRoot: dir)
    #expect(initial.map(\.messageId) == ["first"])

    try (first + "\n" + second + "\n").write(
        to: url,
        atomically: true,
        encoding: .utf8
    )
    for failure in [
        RecordingJSONLFileReader.Failure.metadata,
        .open,
        .seek,
        .read,
    ] {
        reader.failure = failure
        let fallback = try parser.parseAllFiles([info], claudeDataRoot: dir)
        #expect(fallback.map(\.messageId) == ["first"], Comment("failure=\(failure)"))
        #expect(parser.debugCachedFileCount == 1)
    }

    reader.failure = .none
    let deleted = try parser.parseAllFiles([], claudeDataRoot: dir)
    #expect(deleted.isEmpty)
    #expect(parser.debugCachedFileCount == 0)
}

@Test("从未成功的文件 metadata 失败时继续跳过")
func firstMetadataFailureHasNoLastGoodResult() throws {
    let dir = FileManager.default.temporaryDirectory
    let url = dir.appendingPathComponent("never-read-\(UUID().uuidString).jsonl")
    let info = ClaudeJSONLFileInfo(
        url: url,
        sessionID: "missing",
        projectPath: "/project",
        isSubagent: false,
        agentId: nil
    )
    let reader = RecordingJSONLFileReader()
    reader.failure = .metadata
    let parser = ClaudeJSONLParser(fileReader: reader)

    let entries = try parser.parseAllFiles([info], claudeDataRoot: dir)

    #expect(entries.isEmpty)
    #expect(parser.debugCachedFileCount == 0)
}
```

在 `CodexRolloutParserTests.swift` 增加：

```swift
@Test("已成功 rollout 随后 seek 失败时复用 last-good 并按 scanner prune")
func seekFailureReusesLastGoodUntilScannerOmitsRollout() throws {
    let (file, cleanup) = try makeJsonlFile([sessionMeta, turnContextGpt5, normalEvent])
    defer { cleanup() }
    let reader = RecordingJSONLFileReader()
    let parser = CodexRolloutParser(fileReader: reader)
    let initial = try parser.parseAllFiles([file])
    #expect(initial.count == 1)

    let secondEvent = #"{"timestamp":"2026-05-04T08:36:30.000Z","type":"event_msg","payload":{"type":"token_count","info":{"last_token_usage":{"input_tokens":2000,"cached_input_tokens":500,"output_tokens":300,"reasoning_output_tokens":100,"total_tokens":2300}}}}"#
    try ([sessionMeta, turnContextGpt5, normalEvent, secondEvent]
        .joined(separator: "\n") + "\n")
        .write(to: file.url, atomically: true, encoding: .utf8)
    reader.failure = .seek

    let fallback = try parser.parseAllFiles([file])
    #expect(fallback.count == 1)
    #expect(parser.debugCachedFileCount == 1)

    reader.failure = .none
    let deleted = try parser.parseAllFiles([])
    #expect(deleted.isEmpty)
    #expect(parser.debugCachedFileCount == 0)
}

@Test("从未成功的 missing rollout 保持跳过")
func missingRolloutWithoutLastGoodReturnsEmpty() throws {
    let url = FileManager.default.temporaryDirectory
        .appendingPathComponent("missing-\(UUID().uuidString).jsonl")
    let file = CodexRolloutFileInfo(
        url: url,
        sessionID: "missing",
        isArchived: false
    )
    let parser = CodexRolloutParser()

    let entries = try parser.parseAllFiles([file])

    #expect(entries.isEmpty)
    #expect(parser.debugCachedFileCount == 0)
}

@Test("Codex last-good 不得跨 pricing speed 复用")
func lastGoodIsScopedToPricingSpeed() throws {
    let (file, cleanup) = try makeJsonlFile([sessionMeta, turnContextGpt5, normalEvent])
    defer { cleanup() }
    let reader = RecordingJSONLFileReader()
    let parser = CodexRolloutParser(fileReader: reader)
    #expect(try parser.parseAllFiles([file], pricingSpeed: .standard).count == 1)
    reader.failure = .read

    let fast = try parser.parseAllFiles([file], pricingSpeed: .fast)

    #expect(fast.isEmpty)
}
```

- [ ] **Step 3: 运行测试并确认 RED**

Run:

```bash
xcodebuild -project TokenWatch.xcodeproj -scheme TokenWatch -destination 'platform=macOS' \
  -only-testing:TokenWatchTests/JSONLFileReaderTests \
  -only-testing:TokenWatchTests/ClaudeJSONLParserTests/transientReaderFailuresReuseLastGoodUntilScannerOmitsFile \
  -only-testing:TokenWatchTests/ClaudeJSONLParserTests/firstMetadataFailureHasNoLastGoodResult \
  -only-testing:TokenWatchTests/CodexRolloutParserTests \
  -skip-testing:TokenWatchUITests -derivedDataPath .build/DerivedData CODE_SIGN_STYLE=Manual DEVELOPMENT_TEAM= CODE_SIGN_IDENTITY=- test
```

Expected: FAIL；共享 reader 和 injectable initializer 尚不存在。当前已发现文件读取失败会整文件丢失，导致聚合候选骤减。

- [ ] **Step 4: 实现共享 metadata 与 byte stream adapter**

创建 `TokenWatch/Providers/JSONLFileReader.swift`：

```swift
import Foundation
import Darwin

/// 文件系统身份；device + inode 可区分同路径替换。
struct JSONLFileIdentity: Equatable, Sendable {
    let deviceID: UInt64
    let fileID: UInt64
}

/// 从已打开 descriptor fstat 得到的增量判断输入。
struct JSONLFileMetadata: Equatable, Sendable {
    let identity: JSONLFileIdentity?
    let size: UInt64
    let modificationDate: Date
}

/// 可 seek 的 JSONL 字节流；测试可以在每个边界确定性失败。
protocol JSONLByteStream: AnyObject, Sendable {
    func seek(toOffset offset: UInt64) throws
    func read(upToCount count: Int) throws -> Data
    func close()
}

/// metadata 必须来自 stream 同一个已打开 descriptor，避免 stat/open TOCTOU。
struct JSONLFileSnapshot: Sendable {
    let metadata: JSONLFileMetadata
    let stream: any JSONLByteStream
}

/// Claude/Codex 共享的 descriptor snapshot 入口。
protocol JSONLFileReading: Sendable {
    func openSnapshot(for url: URL) throws -> JSONLFileSnapshot
}

struct SystemJSONLFileReader: JSONLFileReading {
    func openSnapshot(for url: URL) throws -> JSONLFileSnapshot {
        let handle = try FileHandle(forReadingFrom: url)
        do {
            var info = stat()
            guard fstat(handle.fileDescriptor, &info) == 0 else {
                throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
            }
            let nanos = Double(info.st_mtimespec.tv_nsec) / 1_000_000_000
            let metadata = JSONLFileMetadata(
                identity: JSONLFileIdentity(
                    deviceID: UInt64(info.st_dev),
                    fileID: UInt64(info.st_ino)
                ),
                size: UInt64(max(0, info.st_size)),
                modificationDate: Date(
                    timeIntervalSince1970: Double(info.st_mtimespec.tv_sec) + nanos
                )
            )
            return JSONLFileSnapshot(
                metadata: metadata,
                stream: FileHandleJSONLByteStream(handle: handle)
            )
        } catch {
            try? handle.close()
            throw error
        }
    }
}

private final class FileHandleJSONLByteStream: JSONLByteStream, @unchecked Sendable {
    private let handle: FileHandle

    init(handle: FileHandle) {
        self.handle = handle
    }

    func seek(toOffset offset: UInt64) throws {
        try handle.seek(toOffset: offset)
    }

    func read(upToCount count: Int) throws -> Data {
        try handle.read(upToCount: count) ?? Data()
    }

    func close() {
        try? handle.close()
    }
}
```

metadata identity 为 nil 时 parser 不得命中 unchanged cache；下一阶段也必须把它视为“无法验证”，执行全量重建。

- [ ] **Step 5: 让两个 parser 经 reader 流式读取并只在成功后替换 cache**

在两个 parser 中加入相同依赖：

```swift
private let fileReader: any JSONLFileReading

init(fileReader: any JSONLFileReading = SystemJSONLFileReader()) {
    self.fileReader = fileReader
}
```

把各自私有 `FileSignature` 删除。Claude cache 保存未去重 entry candidates：

```swift
private struct CachedFile {
    let metadata: JSONLFileMetadata
    let candidates: [ParsedUsageEntry]
}
```

Codex cache 保存 Task 4 的 raw wrapper 和 speed：

```swift
private struct CachedFile {
    let metadata: JSONLFileMetadata
    let pricingSpeed: CodexPricingSpeed
    let candidates: [CodexUsageCandidate]
}
```

单文件读取不得再次 open；`parseCached...` 打开 snapshot 后，把同一 stream 传给内部解析循环：

```swift
let snapshot = try fileReader.openSnapshot(for: fileInfo.url)
defer { snapshot.stream.close() }
try snapshot.stream.seek(toOffset: 0)
```

64KB 循环改为：

```swift
var bufferStartOffset: UInt64 = 0
while true {
    let chunk = try snapshot.stream.read(upToCount: chunkSize)
    if chunk.isEmpty { break }
    buffer.append(chunk)

    var searchStart = buffer.startIndex
    while let newlineIndex = buffer[searchStart..<buffer.endIndex].firstIndex(of: newline) {
        let sourceOffset = bufferStartOffset + UInt64(searchStart - buffer.startIndex)
        processLine(Data(buffer[searchStart..<newlineIndex]), sourceOffset)
        searchStart = buffer.index(after: newlineIndex)
    }
    if searchStart > buffer.startIndex {
        bufferStartOffset += UInt64(searchStart - buffer.startIndex)
        buffer.removeSubrange(buffer.startIndex..<searchStart)
    }
}
if !buffer.isEmpty {
    processLine(buffer, bufferStartOffset)
}
```

Claude 的 `processLine/parseCandidate` 必须使用该绝对 `sourceOffset` 生成 missing-ID identity；Codex 用它作为本地 record UUID 的稳定辅助值，但 session timestamp 缺失时仍按 Task 4 跳过 billing event。

cache hit 与成功替换使用：

```swift
private func parseCachedJSONLFile(
    _ fileInfo: ClaudeJSONLFileInfo,
    claudeDataRoot: URL,
    cacheKey: String
) throws -> [ParsedUsageEntry] {
    let snapshot = try fileReader.openSnapshot(for: fileInfo.url)
    defer { snapshot.stream.close() }
    if let cached = cachedCandidates(for: cacheKey, matching: snapshot.metadata) {
        return cached
    }

    let candidates = try parseJSONLStream(
        snapshot.stream,
        fileInfo: fileInfo,
        claudeDataRoot: claudeDataRoot
    )
    withCacheLock {
        cachedFiles[cacheKey] = CachedFile(
            metadata: snapshot.metadata,
            candidates: candidates
        )
    }
    return candidates
}

private func parseCachedFile(
    _ fileInfo: CodexRolloutFileInfo,
    cacheKey: String,
    pricingSpeed: CodexPricingSpeed
) throws -> [CodexUsageCandidate] {
    let snapshot = try fileReader.openSnapshot(for: fileInfo.url)
    defer { snapshot.stream.close() }
    if let cached = cachedCandidates(
        for: cacheKey,
        matching: snapshot.metadata,
        pricingSpeed: pricingSpeed
    ) {
        return cached
    }

    let candidates = try parseCandidates(
        snapshot.stream,
        metadata: snapshot.metadata,
        fileInfo: fileInfo,
        pricingSpeed: pricingSpeed
    )
    withCacheLock {
        cachedFiles[cacheKey] = CachedFile(
            metadata: snapshot.metadata,
            pricingSpeed: pricingSpeed,
            candidates: candidates
        )
    }
    return candidates
}

private func cachedCandidates(
    for cacheKey: String,
    matching metadata: JSONLFileMetadata,
    pricingSpeed: CodexPricingSpeed
) -> [CodexUsageCandidate]? {
    withCacheLock {
        guard metadata.identity != nil,
              let cached = cachedFiles[cacheKey],
              cached.metadata == metadata,
              cached.pricingSpeed == pricingSpeed else {
            return nil
        }
        cacheHitCount += 1
        return cached.candidates
    }
}

private func lastGoodCandidates(
    for cacheKey: String,
    pricingSpeed: CodexPricingSpeed
) -> [CodexUsageCandidate]? {
    withCacheLock {
        guard let cached = cachedFiles[cacheKey],
              cached.pricingSpeed == pricingSpeed else { return nil }
        return cached.candidates
    }
}
```

Claude 保留无 speed 参数的 `[ParsedUsageEntry]` 版 `cachedCandidates/lastGoodCandidates`；Codex 使用上面的 raw wrapper + speed 版。两个文件各自拥有同名私有方法，不创建公共 cache 容器。公开 `parseJSONLFile/parseFile` 同样通过 snapshot 路径实现，不保留第二套 FileHandle 逻辑。

- [ ] **Step 6: 在 per-file catch 中复用 last-good，并保持 scanner prune**

Claude 的 `parseAllFiles` 循环改为：

```swift
var allCandidates: [ParsedUsageEntry] = []
var currentCacheKeys: Set<String> = []

for fileInfo in files {
let cacheKey = Self.cacheKey(for: fileInfo.url)
currentCacheKeys.insert(cacheKey)
do {
    let candidates = try parseCachedJSONLFile(
        fileInfo,
        claudeDataRoot: claudeDataRoot,
        cacheKey: cacheKey
    )
    allCandidates.append(contentsOf: candidates)
} catch {
    if let lastGood = lastGoodCandidates(for: cacheKey) {
        allCandidates.append(contentsOf: lastGood)
        logger.warning(
            "文件暂时不可读，复用上次成功结果: \(fileInfo.url.lastPathComponent) — \(error.localizedDescription)"
        )
    } else {
        logger.warning(
            "文件首次读取失败，跳过: \(fileInfo.url.lastPathComponent) — \(error.localizedDescription)"
        )
    }
}
}
```

Codex 的 `parseAllFiles(_:pricingSpeed:)` 循环改为：

```swift
var allCandidates: [CodexUsageCandidate] = []
var currentCacheKeys: Set<String> = []

for fileInfo in files {
let cacheKey = Self.cacheKey(for: fileInfo.url)
currentCacheKeys.insert(cacheKey)
do {
    let candidates = try parseCachedFile(
        fileInfo,
        cacheKey: cacheKey,
        pricingSpeed: pricingSpeed
    )
    allCandidates.append(contentsOf: candidates)
} catch {
    if let lastGood = lastGoodCandidates(
        for: cacheKey,
        pricingSpeed: pricingSpeed
    ) {
        allCandidates.append(contentsOf: lastGood)
        logger.warning(
            "文件暂时不可读，复用上次成功结果: \(fileInfo.url.lastPathComponent) — \(error.localizedDescription)"
        )
    } else {
        logger.warning(
            "文件首次读取失败，跳过: \(fileInfo.url.lastPathComponent) — \(error.localizedDescription)"
        )
    }
}
}
```

循环结束后继续执行：

```swift
pruneCache(keeping: currentCacheKeys)
```

Claude 随后调用 `ClaudeUsageDeduplicator.deduplicate(allCandidates)`；Codex 随后执行 Task 4 的 `CodexEventDedupKey` first-wins 去重。catch 不得把 last-good 写回，也不得用部分读取结果覆盖 cache。speed 切换后如果新 snapshot 读取失败，不得复用另一 speed 的 last-good，因为其 service tier 已过期。

- [ ] **Step 7: 运行 reader、last-good 和 cache 回归并确认 GREEN**

Run:

```bash
xcodebuild -project TokenWatch.xcodeproj -scheme TokenWatch -destination 'platform=macOS' \
  -only-testing:TokenWatchTests/JSONLFileReaderTests \
  -only-testing:TokenWatchTests/ClaudeJSONLParserTests \
  -only-testing:TokenWatchTests/CodexRolloutParserTests \
  -skip-testing:TokenWatchUITests -derivedDataPath .build/DerivedData CODE_SIGN_STYLE=Manual DEVELOPMENT_TEAM= CODE_SIGN_IDENTITY=- test
```

Expected: PASS；unchanged 文件仍命中 cache，stat/open/seek/read 任一失败都走同一个 last-good 分支，首次失败为空，scanner 删除立即 prune。

- [ ] **Step 8: 提交 Task 6**

```bash
git add TokenWatch/Providers/JSONLFileReader.swift \
  TokenWatch/Providers/Claude/ClaudeJSONLParser.swift \
  TokenWatch/Providers/Codex/CodexRolloutParser.swift \
  TokenWatchTests/TestSupport/RecordingJSONLFileReader.swift \
  TokenWatchTests/Providers/JSONLFileReaderTests.swift \
  TokenWatchTests/Providers/Claude/ClaudeJSONLParserTests.swift \
  TokenWatchTests/Providers/Codex/CodexRolloutParserTests.swift
git commit -m "fix(parser): 复用暂时不可读文件的上次结果"
```

---

### Task 7: 验证 bookmark 创建与保存结果后再授权

**Files:**
- Create: `TokenWatch/Services/BookmarkPersistence.swift`
- Modify: `TokenWatch/Services/SecurityScopedBookmarkManager.swift:1-196`
- Create: `TokenWatchTests/Services/BookmarkPersistenceTests.swift`
- Modify: `TokenWatchTests/Services/SecurityScopedBookmarkManagerTests.swift:1-31`
- Modify: `TokenWatchTests/ViewModels/TokenStatsViewModelObserverTests.swift:1-394`

**Interfaces:**
- Consumes: 现有 `BookmarkAccessManaging.promptUserToSelectDirectory(forProvider:) async -> URL?`；保持 nil 同时表示取消或授权未完成。
- Produces: `BookmarkDataCreating.createBookmarkData(for:) throws -> Data`；`BookmarkDataStoring.data(forKey:)`、`save(_:forKey:) -> Bool`、`removeData(forKey:)`；`SecurityScopedBookmarkManager.persistSelectedDirectory(_:forKey:) -> URL?`。

- [ ] **Step 1: 写出 creator 失败、store 失败、写后回读和 ViewModel 不刷新的测试**

创建 `TokenWatchTests/Services/BookmarkPersistenceTests.swift`：

```swift
import Foundation
import Testing
@testable import TokenWatch

@MainActor
@Suite("BookmarkPersistence")
struct BookmarkPersistenceTests {
    @Test("bookmark data 创建失败时授权完成结果为 nil")
    func creationFailureReturnsNil() {
        let manager = SecurityScopedBookmarkManager(
            bookmarkDataCreator: ThrowingBookmarkDataCreator(),
            bookmarkStore: InMemoryBookmarkStore()
        )

        let result = manager.persistSelectedDirectory(
            URL(fileURLWithPath: "/Users/example", isDirectory: true),
            forKey: "bookmark"
        )

        #expect(result == nil)
        #expect(!manager.hasBookmark(forKey: "bookmark"))
    }

    @Test("bookmark store 拒绝写入时授权完成结果为 nil")
    func saveFailureReturnsNil() {
        let manager = SecurityScopedBookmarkManager(
            bookmarkDataCreator: FixedBookmarkDataCreator(data: Data([1, 2, 3])),
            bookmarkStore: RejectingBookmarkStore()
        )

        let result = manager.persistSelectedDirectory(
            URL(fileURLWithPath: "/Users/example", isDirectory: true),
            forKey: "bookmark"
        )

        #expect(result == nil)
        #expect(!manager.hasBookmark(forKey: "bookmark"))
    }

    @Test("UserDefaults store 写后回读相同数据才返回成功")
    func userDefaultsStoreVerifiesRoundTrip() throws {
        let suite = "BookmarkPersistenceTests-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = UserDefaultsBookmarkStore(defaults: defaults)
        let data = Data([4, 5, 6])

        #expect(store.save(data, forKey: "bookmark"))
        #expect(store.data(forKey: "bookmark") == data)
    }
}

private enum BookmarkFixtureError: Error {
    case creationFailed
}

private struct ThrowingBookmarkDataCreator: BookmarkDataCreating {
    func createBookmarkData(for url: URL) throws -> Data {
        throw BookmarkFixtureError.creationFailed
    }
}

private struct FixedBookmarkDataCreator: BookmarkDataCreating {
    let data: Data

    func createBookmarkData(for url: URL) throws -> Data {
        data
    }
}

private final class InMemoryBookmarkStore: BookmarkDataStoring, @unchecked Sendable {
    private var values: [String: Data] = [:]

    func data(forKey key: String) -> Data? {
        values[key]
    }

    func save(_ data: Data, forKey key: String) -> Bool {
        values[key] = data
        return values[key] == data
    }

    func removeData(forKey key: String) {
        values[key] = nil
    }
}

private struct RejectingBookmarkStore: BookmarkDataStoring {
    func data(forKey key: String) -> Data? { nil }
    func save(_ data: Data, forKey key: String) -> Bool { false }
    func removeData(forKey key: String) {}
}
```

在 `TokenStatsViewModelObserverTests.swift` 让现有 stub 支持失败：

```swift
@MainActor
private final class StubBookmarkManager: BookmarkAccessManaging {
    private let rootURL: URL
    private let promptSucceeds: Bool

    init(rootURL: URL, promptSucceeds: Bool = true) {
        self.rootURL = rootURL
        self.promptSucceeds = promptSucceeds
    }

    func hasBookmark(forKey key: String) -> Bool { true }

    func promptUserToSelectDirectory(
        forProvider provider: any UsageProvider
    ) async -> URL? {
        promptSucceeds ? rootURL : nil
    }

    func restoreBookmarkAndAccess(forKey key: String) -> URL? { rootURL }
    func stopAccessing(forKey key: String) {}
}
```

并增加：

```swift
@Test func failedAuthorizationDoesNotMarkAuthorizedOrRefresh() async {
    let provider = StubUsageProvider(id: .claude)
    let bookmarkManager = StubBookmarkManager(
        rootURL: URL(fileURLWithPath: NSTemporaryDirectory()),
        promptSucceeds: false
    )
    let aggregator = CountingUsageAggregator()
    let vm = TokenStatsViewModel(
        providers: [provider],
        bookmarkManager: bookmarkManager,
        aggregator: aggregator
    )

    let didAuthorize = await vm.requestAuthorization(for: .claude)

    #expect(!didAuthorize)
    #expect(vm.states[.claude]?.needsAuthorization == true)
    #expect(aggregator.aggregateCallCount == 0)
}
```

- [ ] **Step 2: 运行测试并确认 RED**

Run:

```bash
xcodebuild -project TokenWatch.xcodeproj -scheme TokenWatch -destination 'platform=macOS' \
  -only-testing:TokenWatchTests/BookmarkPersistenceTests \
  -only-testing:TokenWatchTests/TokenStatsViewModelObserverTests/failedAuthorizationDoesNotMarkAuthorizedOrRefresh \
  -skip-testing:TokenWatchUITests -derivedDataPath .build/DerivedData CODE_SIGN_STYLE=Manual DEVELOPMENT_TEAM= CODE_SIGN_IDENTITY=- test
```

Expected: FAIL；creator/store 协议、injectable manager initializer 与 `persistSelectedDirectory` 尚不存在。当前 panel 在 bookmark 创建静默失败后仍返回所选 URL。

- [ ] **Step 3: 实现 creator 与 Bool bookmark store**

创建 `TokenWatch/Services/BookmarkPersistence.swift`：

```swift
import Foundation

protocol BookmarkDataCreating: Sendable {
    func createBookmarkData(for url: URL) throws -> Data
}

struct SecurityScopedBookmarkDataCreator: BookmarkDataCreating {
    func createBookmarkData(for url: URL) throws -> Data {
        try url.bookmarkData(
            options: .withSecurityScope,
            includingResourceValuesForKeys: nil,
            relativeTo: nil
        )
    }
}

protocol BookmarkDataStoring: Sendable {
    func data(forKey key: String) -> Data?
    func save(_ data: Data, forKey key: String) -> Bool
    func removeData(forKey key: String)
}

final class UserDefaultsBookmarkStore: BookmarkDataStoring, @unchecked Sendable {
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func data(forKey key: String) -> Data? {
        defaults.data(forKey: key)
    }

    func save(_ data: Data, forKey key: String) -> Bool {
        defaults.set(data, forKey: key)
        return defaults.data(forKey: key) == data
    }

    func removeData(forKey key: String) {
        defaults.removeObject(forKey: key)
    }
}
```

- [ ] **Step 4: 注入依赖并让 panel 只返回已持久化 URL**

在 `SecurityScopedBookmarkManager.swift` 增加 `import os.log`、属性和 initializer：

```swift
private let bookmarkDataCreator: any BookmarkDataCreating
private let bookmarkStore: any BookmarkDataStoring
private let logger = Logger(
    subsystem: "com.xiaoao.TokenWatch",
    category: "SecurityScopedBookmarkManager"
)

init(
    bookmarkDataCreator: any BookmarkDataCreating = SecurityScopedBookmarkDataCreator(),
    bookmarkStore: any BookmarkDataStoring = UserDefaultsBookmarkStore()
) {
    self.bookmarkDataCreator = bookmarkDataCreator
    self.bookmarkStore = bookmarkStore
}
```

查询与恢复路径统一经过 store：

```swift
func hasBookmark(forKey key: String) -> Bool {
    bookmarkStore.data(forKey: key) != nil
}

guard let bookmarkData = bookmarkStore.data(forKey: key) else {
    return nil
}
```

解析失败或 `startAccessingSecurityScopedResource()` 失败时调用：

```swift
bookmarkStore.removeData(forKey: key)
```

stale 重建改为：

```swift
if isStale {
    do {
        let fresh = try bookmarkDataCreator.createBookmarkData(for: url)
        if !bookmarkStore.save(fresh, forKey: key) {
            logger.error("过期 Bookmark 重存验证失败: \(key)")
        }
    } catch {
        logger.error("过期 Bookmark 重建失败: \(error.localizedDescription)")
    }
}
```

增加可测试完成方法：

```swift
/// 创建并验证保存所选目录的 bookmark；失败时不返回假授权 URL。
func persistSelectedDirectory(_ url: URL, forKey key: String) -> URL? {
    do {
        let data = try bookmarkDataCreator.createBookmarkData(for: url)
        guard bookmarkStore.save(data, forKey: key) else {
            logger.error("Bookmark 保存验证失败: \(key)")
            return nil
        }
        return url
    } catch {
        logger.error("Bookmark 创建失败: \(error.localizedDescription)")
        return nil
    }
}
```

panel completion 改为：

```swift
panel.begin { [weak self] response in
    guard response == .OK, let url = panel.url else {
        continuation.resume(returning: nil)
        return
    }
    continuation.resume(
        returning: self?.persistSelectedDirectory(url, forKey: key)
    )
}
```

删除旧的 `private func createAndSaveBookmark(for:key:)`。

- [ ] **Step 5: 锁定 ViewModel nil 分支且不改变首次取消契约**

保留 `TokenStatsViewModel.requestAuthorization` 的 nil 分支只返回 false：

```swift
let selectedDirectory = await bookmarkManager.promptUserToSelectDirectory(forProvider: provider)
guard selectedDirectory != nil else {
    logger.info("\(provider.displayName) 用户未完成授权")
    return false
}

markProvidersAuthorized(sharingBookmarkWith: provider)
logger.info("\(provider.displayName) 用户授权成功")
await loadAllStats()
return true
```

不修改 `AppLaunchAuthorizationCoordinator` 的既有“用户取消首次 panel 后加载未授权状态”行为；本 task 的“不触发刷新”约束在 ViewModel 授权方法内验证，即 nil 不进入成功分支的 `loadAllStats()`。

- [ ] **Step 6: 运行 bookmark、ViewModel 和启动协调测试并确认 GREEN**

Run:

```bash
xcodebuild -project TokenWatch.xcodeproj -scheme TokenWatch -destination 'platform=macOS' \
  -only-testing:TokenWatchTests/BookmarkPersistenceTests \
  -only-testing:TokenWatchTests/SecurityScopedBookmarkManagerTests \
  -only-testing:TokenWatchTests/TokenStatsViewModelObserverTests \
  -only-testing:TokenWatchTests/TokenWatchTests/firstLaunchWithoutBookmarkRequestsInitialAuthorization \
  -only-testing:TokenWatchTests/TokenWatchTests/canceledInitialAuthorizationFallsBackToStatsLoad \
  -skip-testing:TokenWatchUITests -derivedDataPath .build/DerivedData CODE_SIGN_STYLE=Manual DEVELOPMENT_TEAM= CODE_SIGN_IDENTITY=- test
```

Expected: PASS；创建/保存失败返回 nil、不标授权、不刷新，成功 store 完成写后回读；既有首次取消协调行为保持不变。

- [ ] **Step 7: 提交 Task 7**

```bash
git add TokenWatch/Services/BookmarkPersistence.swift \
  TokenWatch/Services/SecurityScopedBookmarkManager.swift \
  TokenWatchTests/Services/BookmarkPersistenceTests.swift \
  TokenWatchTests/Services/SecurityScopedBookmarkManagerTests.swift \
  TokenWatchTests/ViewModels/TokenStatsViewModelObserverTests.swift
git commit -m "fix(auth): 验证 Bookmark 创建与保存结果"
```

---

## 阶段完成验证

- [ ] 运行本计划涉及的所有 unit suites：

```bash
xcodebuild -project TokenWatch.xcodeproj -scheme TokenWatch -destination 'platform=macOS' \
  -only-testing:TokenWatchTests/TokenUsageDecodingTests \
  -only-testing:TokenWatchTests/UsageAggregatorTests \
  -only-testing:TokenWatchTests/PricingEngineTests \
  -only-testing:TokenWatchTests/LocalHourBucketDescriptorTests \
  -only-testing:TokenWatchTests/MonthlyTokenChartBuilderTests \
  -only-testing:TokenWatchTests/DashboardRangeSnapshotTests \
  -only-testing:TokenWatchTests/ClaudeUsageDeduplicatorTests \
  -only-testing:TokenWatchTests/ClaudeJSONLParserTests \
  -only-testing:TokenWatchTests/CodexRolloutParserTests \
  -only-testing:TokenWatchTests/OpenCodeMessageParserTests \
  -only-testing:TokenWatchTests/OpenCodeSQLiteScannerTests \
  -only-testing:TokenWatchTests/JSONLFileReaderTests \
  -only-testing:TokenWatchTests/BookmarkPersistenceTests \
  -only-testing:TokenWatchTests/SecurityScopedBookmarkManagerTests \
  -only-testing:TokenWatchTests/TokenStatsViewModelObserverTests \
  -skip-testing:TokenWatchUITests -derivedDataPath .build/DerivedData CODE_SIGN_STYLE=Manual DEVELOPMENT_TEAM= CODE_SIGN_IDENTITY=- test
```

Expected: PASS。

- [ ] 运行完整 unit target，确认没有被局部 suite 遮蔽的 fixture 或 initializer 回归：

```bash
xcodebuild -project TokenWatch.xcodeproj -scheme TokenWatch -destination 'platform=macOS' \
  -only-testing:TokenWatchTests -skip-testing:TokenWatchUITests \
  -derivedDataPath .build/DerivedData CODE_SIGN_STYLE=Manual DEVELOPMENT_TEAM= CODE_SIGN_IDENTITY=- test
```

Expected: PASS。

- [ ] 在无法连接 `testmanagerd` 的沙盒内至少编译所有 tests：

```bash
xcodebuild -project TokenWatch.xcodeproj -scheme TokenWatch -destination 'platform=macOS' \
  -skip-testing:TokenWatchUITests -derivedDataPath .build/DerivedData CODE_SIGN_STYLE=Manual DEVELOPMENT_TEAM= CODE_SIGN_IDENTITY=- build-for-testing
```

Expected: `** TEST BUILD SUCCEEDED **`。

- [ ] 构建 Debug、Release 与 universal binary，并运行静态分析：

```bash
xcodebuild -project TokenWatch.xcodeproj -scheme TokenWatch -configuration Debug \
  -derivedDataPath .build/DerivedData CODE_SIGNING_ALLOWED=NO build
xcodebuild -project TokenWatch.xcodeproj -scheme TokenWatch -configuration Release \
  -derivedDataPath .build/DerivedData CODE_SIGNING_ALLOWED=NO build
xcodebuild -project TokenWatch.xcodeproj -scheme TokenWatch -configuration Release \
  ARCHS='arm64 x86_64' ONLY_ACTIVE_ARCH=NO \
  -derivedDataPath .build/DerivedData-Universal CODE_SIGNING_ALLOWED=NO build
xcodebuild -project TokenWatch.xcodeproj -scheme TokenWatch -configuration Debug \
  -destination 'platform=macOS' -derivedDataPath .build/DerivedData CODE_SIGNING_ALLOWED=NO analyze
```

Expected: 四条命令成功；Release 无签名不作为失败。

- [ ] 任务级 review 核对以下不变量后再开始增量解析计划：

```text
1. Claude/Codex cache 中保存的是 raw candidates，不是全局去重结果。
2. Claude 全局去重每次对所有文件候选重新执行，isSidechain 已进入 fingerprint/deep snapshot。
3. JSONLFileMetadata 同时携带 identity、size、mtime；reader 暴露 seek/read，增量阶段不另建文件 IO 协议。
4. Codex previousTotals 为 optional，并由增量 checkpoint 在 committed offset 保存。
5. last-good 只覆盖 scanner 已发现但随后读取失败的文件；空 scanner 列表立即 prune。
6. bookmark creator/store 任一失败都返回 nil，ViewModel 不进入成功刷新分支。
```

完成以上验证后，下一阶段使用 `superpowers:writing-plans` 单独编写 Claude/Codex 增量 JSONL 解析计划，并以本文件的 reader、raw candidate、deep snapshot 与 Codex checkpoint 接口为输入。
