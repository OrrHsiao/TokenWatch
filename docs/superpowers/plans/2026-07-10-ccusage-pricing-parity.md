# ccusage 离线计价对齐 Implementation Plan

> **2026-07-11 superseding amendment:** 本文记录的 v20.0.16 实施历史仍保留；当前兼容与计价契约已升级为 `ccusage v20.0.17 / 88cdfa4fb201c92b163a34d0bbb097b68d3185cf`。v20.0.16→v20.0.17 定价资源与规则无变化；新增行为、非重复 token total 与验收以 [ccusage v20.0.17 对齐设计](../specs/2026-07-11-ccusage-v20.0.17-alignment-design.md) 和 [实施计划](2026-07-11-ccusage-v20.0.17-alignment.md) 为准。

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 让 TokenWatch 对同一条 Claude、Codex 或 OpenCode 用量记录，在 ccusage `v20.0.16 --offline` 默认 Auto 成本模式下得到相同 USD 结果。

**Architecture:** 将定价拆成三个稳定边界：`LiteLLMPriceCatalog` / `ModelsDevPriceCatalog` 只负责解码固定快照，`PricingTable` 负责 primary、builtin、alias 与 fallback 的确定性查价，`PricingEngine` 负责 standard 与 Codex 两套 token 计价语义。执行到本计划 Task 2 后必须先完成 Provider 数据正确性计划 Task 1，把 `TokenUsage.cacheCreation` 改成 optional；随后才能回到本计划 Task 3–6。provider parser 负责传播 authoritative upstream cost、将 OpenCode `tokens.total` 缺口并入可计费 output，以及恢复 Codex speed 和模型状态；最终由 `UsageCostResolver` 实现 Auto 的 upstream-first 选择。

**Tech Stack:** Swift 6、Foundation、Swift Testing、Xcode 26.5、macOS app-hosted unit tests、内嵌 JSON 资源；不增加运行时网络或第三方依赖。

## Global Constraints

- ccusage 基线固定为 `v20.0.16 / e32cc4820df1e13f4399560e03f3858869738dc8`，比较命令必须使用 `--offline`，cost mode 保持默认 Auto。
- LiteLLM 固定为 `49ca04d8c3ddea336237ce6f3082dbc26d19e944`；原始 `model_prices_and_context_window.json` SHA-256 为 `ae4532ba0c5da03ed694f37fffa050a65e0e250b816dcdb475bee0b7b7b1aa97`。
- models.dev fallback 固定为 ccusage `v20.0.16` 的 `rust/crates/ccusage/src/models-dev-pricing.json`；SHA-256 为 `5d61cc3148100cd670d3289033b5e2fb05c4244cbe32f92888ef7bd2df1abf67`。
- fast override 来源固定为同版本 `fast-multiplier-overrides.json`，SHA-256 为 `647b3ae8e44349455f32ce9f4633910b5151b08cda1707601a97701927490762`。
- `codex-auto-review` 日期表来源固定为同版本 `codex-auto-review-fallbacks.json`，SHA-256 为 `344d2438312beed608c19e616031d1b194f3c6efdfcbd0925f39f4df9008c037`。
- App 继续离线内嵌定价；生产路径不得新增 HTTP 请求、在线刷新或随运行时间变化的数据源。
- Auto 必须把存在的 `upstreamCost` 视为 authoritative，包括 Claude 显式 `0`；OpenCode 继续只传播 `cost > 0`。
- ccusage 先载入 LiteLLM，再以 builtin 整条覆盖同 key 条目，因此 exact builtin 冲突时包括 fast multiplier 在内都以 builtin 为准；非冲突 provider-prefixed LiteLLM 条目才保留显式 provider fast，fast override 只补缺失。
- OpenCode `tokens` 子字段缺失时宽容默认为 `0`；`missing = max(total - (input + output + cache.read + cache.write), 0)` 以 output rate 计费，统一模型将它并入 `outputTokens`。
- Codex `cached_input_tokens` 必须先夹到 `[0, input_tokens]`，再计算 `pure input = raw input - cached input`，不得保留超过 raw input 的 cache read。
- 不计 web search、web fetch 或 `inference_geo`；不改变 `TokenUsageRaw` 维度。
- 普通 LiteLLM/Claude 的 200K above 字段保持每 token 类别独立的边际阶梯；带 `longContextThreshold` 的 OpenAI/Codex 模型使用整请求切档。
- `.standard` 的 long-context 判断逐字使用 ccusage `TokenUsageRaw.input_tokens`；只有 `.codex` 因统一模型已拆成 pure/cached，才以两者之和重建原始 input。
- Codex long-context 判定必须在单条请求上使用 `pure input + cached input`，不得先跨请求聚合。
- LiteLLM 与 models.dev 缺失 cache write/read 时分别使用 input × 1.25 与 input × 0.1；Codex 对非显式 cache read 改用完整 input price。
- 跨计划唯一执行序列为：本计划 Task 1 → 本计划 Task 2 → Provider 数据正确性计划 Task 1 → 本计划 Task 3 → Task 4 → Task 5 → Task 6 → Provider 数据正确性计划 Task 2–7；不得把整个 Provider 计划推迟到本计划之后，也不得提前执行 Provider Task 2。
- Provider Task 1 的 production change 与定向测试未 GREEN 前，本计划任何步骤都不得写入 `cacheCreation: nil`；该语法第一次出现在本计划 Task 3，此时 `TokenUsage.cacheCreation` 必须已经是 `CacheCreation?`。
- 不引入通用 TOML、数据库、Rust 构建系统或第三方图表依赖；`.codex/config.toml` 只解析真正位于文档顶层、且出现在任何 TOML table header 之前的 `service_tier` 行，`[table]` / `[[array-of-tables]]` 内同名键一律忽略。
- 所有行为先写最小失败测试，再写实现；金额比较容差为 `1e-9`。
- 测试命令统一指定 `-destination 'platform=macOS'`、`-skip-testing:TokenWatchUITests` 和 `-derivedDataPath .build/DerivedData`。
- test/build-for-testing 命令统一使用 `CODE_SIGN_STYLE=Manual DEVELOPMENT_TEAM= CODE_SIGN_IDENTITY=-` 的临时 ad-hoc 签名；纯 build/analyze 使用 `CODE_SIGNING_ALLOWED=NO`。
- app-hosted unit tests 需要 `com.apple.testmanagerd.control`；沙盒限制时必须在沙盒外运行，`build-for-testing` 只验证编译。
- Xcode 16+ filesystem-synchronized groups 会自动纳入新增 Swift/JSON 文件；本阶段不编辑 `TokenWatch.xcodeproj/project.pbxproj`。

---

## File Structure

### Production files

- Modify `TokenWatch/Models/ModelPricing.swift`: 表达 cache-read 是否显式及 per-model long-context threshold。
- Modify `TokenWatch/Pricing/litellm_prices.json`: 替换成固定 LiteLLM revision 经 ccusage 前缀规则过滤后的 compact snapshot。
- Create `TokenWatch/Pricing/models-dev-pricing.json`: 保存 ccusage 固定 models.dev fallback snapshot。
- Modify `TokenWatch/Pricing/LiteLLMPriceCatalog.swift`: 解码 compact LiteLLM、保留 fast/cache 字段的“是否显式”元数据。
- Create `TokenWatch/Pricing/ModelsDevPriceCatalog.swift`: 解码独立 models.dev fallback。
- Modify `TokenWatch/Pricing/PricingTable.swift`: 组装 primary/builtin/fallback 并实现确定性 exact/fuzzy/alias 查找。
- Modify `TokenWatch/Pricing/PricingEngine.swift`: 实现 standard marginal tier 与 Codex whole-request tier/cache/fast 语义。
- Modify `TokenWatch/Analytics/UsageCostResolver.swift`: 实现 Auto upstream-first。
- Modify `TokenWatch/Models/ParsedUsageEntry.swift`: 更新 upstream cost 的公共语义注释。
- Modify `TokenWatch/Providers/Claude/ClaudeRecord.swift`: 解码顶层 `costUSD`。
- Modify `TokenWatch/Providers/Claude/ClaudeJSONLParser.swift`: 将 `costUSD` 原样传播到 `ParsedUsageEntry.upstreamCost`。
- Modify `TokenWatch/Providers/OpenCode/OpenCodeMessageData.swift`: 宽容解码 token 子字段，并按 ccusage `tokens.total` fallback 计算可计费 output。
- Modify `TokenWatch/Providers/OpenCode/OpenCodeMessageParser.swift`: 将 total 缺口并入 output，并保留 `cost > 0` 过滤。
- Create `TokenWatch/Providers/OpenCode/OpenCodePricingCandidateResolver.swift`: 逐字生成 ccusage OpenCode 裸 model、alias、规范化与 provider/model 候选。
- Create `TokenWatch/Providers/Codex/CodexServiceTierResolver.swift`: 无依赖跟踪 TOML section，只从 `config.toml` 文档顶层识别 `fast` / `priority`。
- Create `TokenWatch/Providers/Codex/CodexModelResolver.swift`: 保存 explicit/fallback 状态并解析 `codex-auto-review` 日期表。
- Modify `TokenWatch/Providers/Codex/CodexRecord.swift`: 解码 event/info 级真实 model。
- Modify `TokenWatch/Providers/Codex/CodexRolloutParser.swift`: 恢复模型状态、应用 fallback 与 pricing speed，并让 cache 对 speed 敏感。
- Modify `TokenWatch/Providers/Codex/CodexProvider.swift`: 读取 `.codex/config.toml` 并把 speed 传给 parser。

### Test files

- Create `TokenWatchTests/Pricing/PricingTableTests.swift`: catalog defaults、来源优先级、匹配、alias、overlay。
- Modify `TokenWatchTests/Pricing/PricingEngineTests.swift`: long-context、Codex cache 与 fast。
- Create `TokenWatchTests/Analytics/UsageCostResolverTests.swift`: Auto upstream matrix。
- Modify `TokenWatchTests/Analytics/UsageAggregatorTests.swift`: 更新旧的 local-first 断言。
- Modify `TokenWatchTests/Providers/Claude/ClaudeJSONLParserTests.swift`: `costUSD` 正数与零传播。
- Modify `TokenWatchTests/Providers/OpenCode/OpenCodeMessageParserTests.swift`: 保留 `cost == 0 → nil` 门禁，新增 total-only 与 partial-total fallback 回归。
- Create `TokenWatchTests/Providers/Codex/CodexServiceTierResolverTests.swift`: 精确 TOML 行语义。
- Create `TokenWatchTests/Providers/Codex/CodexModelResolverTests.swift`: 缺失模型、日期表与真实模型覆盖。
- Modify `TokenWatchTests/Providers/Codex/CodexRecordTests.swift`: event/info model 解码。
- Modify `TokenWatchTests/Providers/Codex/CodexRolloutParserTests.swift`: fallback、speed 与 cache invalidation 集成。
- Create `TokenWatchTests/Pricing/CCUsagePricingParityTests.swift`: 读取金额 fixture 并逐项比较。
- Create `TokenWatchTests/Fixtures/Pricing/ccusage-v20.0.16.json`: 固定基线元数据与完整金额矩阵。

---

### Task 1: 固定快照与 catalog 解码

**Files:**
- Modify: `TokenWatch/Models/ModelPricing.swift:12-60`
- Modify: `TokenWatch/Pricing/LiteLLMPriceCatalog.swift:15-111`
- Modify: `TokenWatch/Pricing/litellm_prices.json`
- Create: `TokenWatch/Pricing/ModelsDevPriceCatalog.swift`
- Create: `TokenWatch/Pricing/models-dev-pricing.json`
- Create: `TokenWatchTests/Pricing/PricingTableTests.swift`

**Interfaces:**
- Consumes: 固定 LiteLLM compact JSON，字段单位为 per-token USD；固定 models.dev JSON，字段单位为 per-million USD。
- Produces: `ModelPricing.cacheReadPriceIsExplicit: Bool`、`ModelPricing.longContextThreshold: Int?`、`CatalogPricingEntry`、`LiteLLMPriceCatalog.init(data:) throws`、`ModelsDevPriceCatalog.init(data:) throws`。

- [ ] **Step 1: 写 catalog 默认值和过滤规则的失败测试**

创建 `TokenWatchTests/Pricing/PricingTableTests.swift`：

```swift
import Foundation
import Testing
@testable import TokenWatch

@Suite("PricingTable")
struct PricingTableTests {
    @Test("LiteLLM 只载入 ccusage embedded 前缀并保留显式 cache/fast 元数据")
    func liteLLMFilteringAndDefaults() throws {
        let data = Data(#"""
        {
          "gpt-default-cache": {"i": 0.000002, "o": 0.000010},
          "claude-explicit-cache": {
            "i": 0.000003,
            "o": 0.000015,
            "cc": 0.000004,
            "cr": 0.0000004,
            "fast": 3.0
          },
          "vertex_ai/gpt-excluded": {"i": 0.000001, "o": 0.000002}
        }
        """#.utf8)

        let catalog = try LiteLLMPriceCatalog(data: data)
        let derived = try #require(catalog.entries["gpt-default-cache"])
        let explicit = try #require(catalog.entries["claude-explicit-cache"])

        #expect(catalog.entries["vertex_ai/gpt-excluded"] == nil)
        #expect(derived.pricing.inputPrice == 2.0)
        #expect(derived.pricing.cacheWritePrice == 2.5)
        #expect(derived.pricing.cacheReadPrice == 0.2)
        #expect(!derived.pricing.cacheReadPriceIsExplicit)
        #expect(derived.explicitFastMultiplier == nil)
        #expect(explicit.pricing.cacheWritePrice == 4.0)
        #expect(explicit.pricing.cacheReadPrice == 0.4)
        #expect(explicit.pricing.cacheReadPriceIsExplicit)
        #expect(explicit.explicitFastMultiplier == 3.0)
    }

    @Test("models.dev 使用相同 cache 默认值但保持独立单位")
    func modelsDevDefaults() throws {
        let data = Data(#"""
        {
          "fallback-model": {
            "cost": {"input": 4.0, "output": 20.0},
            "limit": {"context": 200000}
          },
          "explicit-cache-model": {
            "cost": {
              "input": 5.0,
              "output": 25.0,
              "cache_read": 0.7,
              "cache_write": 6.5
            }
          },
          "missing-output": {"cost": {"input": 1.0}}
        }
        """#.utf8)

        let catalog = try ModelsDevPriceCatalog(data: data)
        let fallback = try #require(catalog.entries["fallback-model"])
        let explicit = try #require(catalog.entries["explicit-cache-model"])

        #expect(fallback.inputPrice == 4.0)
        #expect(fallback.cacheWritePrice == 5.0)
        #expect(fallback.cacheReadPrice == 0.4)
        #expect(!fallback.cacheReadPriceIsExplicit)
        #expect(explicit.cacheWritePrice == 6.5)
        #expect(explicit.cacheReadPrice == 0.7)
        #expect(explicit.cacheReadPriceIsExplicit)
        #expect(catalog.entries["missing-output"] == nil)
    }
}
```

- [ ] **Step 2: 运行测试并确认 RED**

Run:

```bash
xcodebuild -project TokenWatch.xcodeproj -scheme TokenWatch \
  -destination 'platform=macOS' \
  -only-testing:TokenWatchTests/PricingTableTests \
  -skip-testing:TokenWatchUITests \
  -derivedDataPath .build/DerivedData CODE_SIGN_STYLE=Manual DEVELOPMENT_TEAM= CODE_SIGN_IDENTITY=- test
```

Expected: 编译失败，明确报告 `ModelPricing` 没有 `cacheReadPriceIsExplicit` / `longContextThreshold`，且 `ModelsDevPriceCatalog`、可注入的 `LiteLLMPriceCatalog(data:)` 尚不存在。

- [ ] **Step 3: 扩展 ModelPricing 并实现两个 decoder**

将 `TokenWatch/Models/ModelPricing.swift` 的结构体与初始化器替换为：

```swift
import Foundation

/// 每百万 token 的离线模型价格及 ccusage 计价元数据。
struct ModelPricing: Sendable {
    let modelID: String
    let displayName: String
    let inputPrice: Double
    let outputPrice: Double
    let cacheReadPrice: Double
    let cacheWritePrice: Double
    let cacheReadPriceIsExplicit: Bool
    let inputPriceAbove200k: Double?
    let outputPriceAbove200k: Double?
    let cacheReadPriceAbove200k: Double?
    let cacheWritePriceAbove200k: Double?
    let longContextThreshold: Int?
    let fastMultiplier: Double

    init(
        modelID: String,
        displayName: String,
        inputPrice: Double,
        outputPrice: Double,
        cacheReadPrice: Double,
        cacheWritePrice: Double,
        cacheReadPriceIsExplicit: Bool = true,
        inputPriceAbove200k: Double? = nil,
        outputPriceAbove200k: Double? = nil,
        cacheReadPriceAbove200k: Double? = nil,
        cacheWritePriceAbove200k: Double? = nil,
        longContextThreshold: Int? = nil,
        fastMultiplier: Double = 1.0
    ) {
        self.modelID = modelID
        self.displayName = displayName
        self.inputPrice = inputPrice
        self.outputPrice = outputPrice
        self.cacheReadPrice = cacheReadPrice
        self.cacheWritePrice = cacheWritePrice
        self.cacheReadPriceIsExplicit = cacheReadPriceIsExplicit
        self.inputPriceAbove200k = inputPriceAbove200k
        self.outputPriceAbove200k = outputPriceAbove200k
        self.cacheReadPriceAbove200k = cacheReadPriceAbove200k
        self.cacheWritePriceAbove200k = cacheWritePriceAbove200k
        self.longContextThreshold = longContextThreshold
        self.fastMultiplier = fastMultiplier
    }
}
```

将 `TokenWatch/Pricing/LiteLLMPriceCatalog.swift` 替换为：

```swift
import Foundation

struct CatalogPricingEntry: Sendable {
    let pricing: ModelPricing
    let explicitFastMultiplier: Double?
}

struct LiteLLMPriceCatalog: Sendable {
    let entries: [String: CatalogPricingEntry]

    private struct RawEntry: Decodable {
        let i: Double?
        let o: Double?
        let cc: Double?
        let cr: Double?
        let ia: Double?
        let oa: Double?
        let cca: Double?
        let cra: Double?
        let ctx: Int?
        let fast: Double?
    }

    init(data: Data) throws {
        let raw = try JSONDecoder().decode([String: RawEntry].self, from: data)
        var decoded: [String: CatalogPricingEntry] = [:]
        for (modelID, entry) in raw where Self.isEmbeddedModel(modelID) {
            guard let inputPerToken = entry.i, let outputPerToken = entry.o else { continue }
            let input = inputPerToken * 1_000_000.0
            let output = outputPerToken * 1_000_000.0
            let cacheReadIsExplicit = entry.cr != nil
            let pricing = ModelPricing(
                modelID: modelID.lowercased(),
                displayName: modelID,
                inputPrice: input,
                outputPrice: output,
                cacheReadPrice: (entry.cr ?? inputPerToken * 0.1) * 1_000_000.0,
                cacheWritePrice: (entry.cc ?? inputPerToken * 1.25) * 1_000_000.0,
                cacheReadPriceIsExplicit: cacheReadIsExplicit,
                inputPriceAbove200k: entry.ia.map { $0 * 1_000_000.0 },
                outputPriceAbove200k: entry.oa.map { $0 * 1_000_000.0 },
                cacheReadPriceAbove200k: entry.cra.map { $0 * 1_000_000.0 },
                cacheWritePriceAbove200k: entry.cca.map { $0 * 1_000_000.0 },
                fastMultiplier: entry.fast ?? 1.0
            )
            decoded[modelID.lowercased()] = CatalogPricingEntry(
                pricing: pricing,
                explicitFastMultiplier: entry.fast
            )
        }
        entries = decoded
    }

    static func isEmbeddedModel(_ modelID: String) -> Bool {
        [
            "claude-", "anthropic.", "anthropic/", "us.anthropic.",
            "eu.anthropic.", "global.anthropic.", "jp.anthropic.",
            "au.anthropic.", "gpt-", "openai/", "azure/", "zai/",
            "openrouter/openai/",
        ].contains { modelID.hasPrefix($0) }
    }
}
```

创建 `TokenWatch/Pricing/ModelsDevPriceCatalog.swift`：

```swift
import Foundation

struct ModelsDevPriceCatalog: Sendable {
    let entries: [String: ModelPricing]

    private struct RawModel: Decodable {
        let cost: RawCost?
    }

    private struct RawCost: Decodable {
        let input: Double?
        let output: Double?
        let cache_read: Double?
        let cache_write: Double?
    }

    init(data: Data) throws {
        let raw = try JSONDecoder().decode([String: RawModel].self, from: data)
        var decoded: [String: ModelPricing] = [:]
        for (modelID, model) in raw {
            guard let cost = model.cost,
                  let input = cost.input,
                  let output = cost.output else { continue }
            decoded[modelID.lowercased()] = ModelPricing(
                modelID: modelID.lowercased(),
                displayName: modelID,
                inputPrice: input,
                outputPrice: output,
                cacheReadPrice: cost.cache_read ?? input * 0.1,
                cacheWritePrice: cost.cache_write ?? input * 1.25,
                cacheReadPriceIsExplicit: cost.cache_read != nil
            )
        }
        entries = decoded
    }
}
```

- [ ] **Step 4: 生成并校验固定 JSON 资源**

先下载并校验 LiteLLM 原始快照：

```bash
curl -fsSL \
  'https://raw.githubusercontent.com/BerriAI/litellm/49ca04d8c3ddea336237ce6f3082dbc26d19e944/model_prices_and_context_window.json' \
  -o /tmp/tokenwatch-litellm-pinned.json
shasum -a 256 /tmp/tokenwatch-litellm-pinned.json
```

Expected SHA-256: `ae4532ba0c5da03ed694f37fffa050a65e0e250b816dcdb475bee0b7b7b1aa97`。

用下面完整的一次性 Swift 转换器生成 `TokenWatch/Pricing/litellm_prices.json`；输出字段与 ccusage `build.rs::compact_pricing_json` 一致：

```swift
import Foundation

let inputURL = URL(fileURLWithPath: "/tmp/tokenwatch-litellm-pinned.json")
let outputURL = URL(fileURLWithPath: "TokenWatch/Pricing/litellm_prices.json")
let data = try Data(contentsOf: inputURL)
let root = try JSONSerialization.jsonObject(with: data) as! [String: Any]
let prefixes = [
    "claude-", "anthropic.", "anthropic/", "us.anthropic.",
    "eu.anthropic.", "global.anthropic.", "jp.anthropic.",
    "au.anthropic.", "gpt-", "openai/", "azure/", "zai/",
    "openrouter/openai/",
]
let fieldMap = [
    "input_cost_per_token": "i",
    "output_cost_per_token": "o",
    "cache_creation_input_token_cost": "cc",
    "cache_read_input_token_cost": "cr",
    "input_cost_per_token_above_200k_tokens": "ia",
    "output_cost_per_token_above_200k_tokens": "oa",
    "cache_creation_input_token_cost_above_200k_tokens": "cca",
    "cache_read_input_token_cost_above_200k_tokens": "cra",
    "max_input_tokens": "ctx",
]
var compact: [String: Any] = [:]
for (modelID, value) in root where prefixes.contains(where: modelID.hasPrefix) {
    guard let source = value as? [String: Any],
          source["input_cost_per_token"] is NSNumber,
          source["output_cost_per_token"] is NSNumber else { continue }
    var target: [String: Any] = [:]
    for (sourceKey, targetKey) in fieldMap {
        if let number = source[sourceKey] as? NSNumber {
            target[targetKey] = number
        }
    }
    if let provider = source["provider_specific_entry"] as? [String: Any],
       let fast = provider["fast"] as? NSNumber {
        target["fast"] = fast
    }
    compact[modelID] = target
}
let output = try JSONSerialization.data(withJSONObject: compact, options: [.sortedKeys])
try output.write(to: outputURL, options: .atomic)
```

运行方式：

```bash
swift /tmp/tokenwatch-compact-pricing.swift
```

实现时把上述 Swift 内容保存到 `/tmp/tokenwatch-compact-pricing.swift`，运行后不把临时脚本加入 Git。随后下载 models.dev 固定资源并校验：

```bash
curl -fsSL \
  'https://raw.githubusercontent.com/ccusage/ccusage/e32cc4820df1e13f4399560e03f3858869738dc8/rust/crates/ccusage/src/models-dev-pricing.json' \
  -o TokenWatch/Pricing/models-dev-pricing.json
shasum -a 256 TokenWatch/Pricing/models-dev-pricing.json
```

Expected SHA-256: `5d61cc3148100cd670d3289033b5e2fb05c4244cbe32f92888ef7bd2df1abf67`。

- [ ] **Step 5: 运行 catalog 测试并确认 GREEN**

Run:

```bash
xcodebuild -project TokenWatch.xcodeproj -scheme TokenWatch \
  -destination 'platform=macOS' \
  -only-testing:TokenWatchTests/PricingTableTests \
  -skip-testing:TokenWatchUITests \
  -derivedDataPath .build/DerivedData CODE_SIGN_STYLE=Manual DEVELOPMENT_TEAM= CODE_SIGN_IDENTITY=- test
```

Expected: `PricingTableTests` 两个测试通过；输出不包含 `vertex_ai/gpt-excluded`。

- [ ] **Step 6: 提交 catalog 与固定快照**

```bash
git add TokenWatch/Models/ModelPricing.swift \
  TokenWatch/Pricing/LiteLLMPriceCatalog.swift \
  TokenWatch/Pricing/ModelsDevPriceCatalog.swift \
  TokenWatch/Pricing/litellm_prices.json \
  TokenWatch/Pricing/models-dev-pricing.json \
  TokenWatchTests/Pricing/PricingTableTests.swift
git commit -m "feat(pricing): 固定 ccusage 离线定价快照"
```

---

### Task 2: 确定性 PricingTable 与来源优先级

**Files:**
- Modify: `TokenWatch/Pricing/PricingTable.swift:1-344`
- Modify: `TokenWatchTests/Pricing/PricingTableTests.swift`
- Modify: `TokenWatchTests/Pricing/PricingEngineTests.swift:163-252, 487-514, 695-751`

**Interfaces:**
- Consumes: `CatalogPricingEntry`、`LiteLLMPriceCatalog.entries`、`ModelsDevPriceCatalog.entries`、Task 1 的扩展 `ModelPricing`。
- Produces: `PricingTable.shared`、可注入初始化器、`func pricing(for:)` 与兼容现有调用的 `static func pricing(for:)`。

- [ ] **Step 1: 写来源冲突、匹配与 overlay 的失败测试**

在 `PricingTableTests` 中加入：

```swift
extension PricingTableTests {
    @Test("来源优先级是 builtin exact > LiteLLM，且 primary > models.dev")
    func sourcePriority() throws {
        let lite = [
            "same-key": catalogEntry(id: "same-key", input: 2.0),
            "primary-only": catalogEntry(id: "primary-only", input: 3.0),
        ]
        let fallback = [
            "same-key": pricing(id: "same-key", input: 9.0),
            "primary-only": pricing(id: "primary-only", input: 8.0),
            "fallback-only": pricing(id: "fallback-only", input: 7.0),
        ]
        let builtins = ["same-key": pricing(id: "same-key", input: 5.0)]
        let table = PricingTable(
            liteLLMEntries: lite,
            modelsDevEntries: fallback,
            builtins: builtins
        )

        #expect(table.pricing(for: "same-key")?.inputPrice == 5.0)
        #expect(table.pricing(for: "primary-only")?.inputPrice == 3.0)
        #expect(table.pricing(for: "fallback-only")?.inputPrice == 7.0)
    }

    @Test("primary exact 胜过 builtin fuzzy")
    func exactBeforeFuzzyAcrossPrimary() {
        let table = PricingTable(
            liteLLMEntries: ["gpt-5-mini": catalogEntry(id: "gpt-5-mini", input: 0.25)],
            modelsDevEntries: [:],
            builtins: ["gpt-5": pricing(id: "gpt-5", input: 1.25)]
        )
        #expect(table.pricing(for: "gpt-5-mini")?.modelID == "gpt-5-mini")
    }

    @Test("fuzzy 多候选先最长，等长取 canonical 字典序最小")
    func deterministicFuzzySelection() {
        let table = PricingTable(
            liteLLMEntries: [
                "z/model-x": catalogEntry(id: "z/model-x", input: 9.0),
                "a/model-x": catalogEntry(id: "a/model-x", input: 1.0),
                "model": catalogEntry(id: "model", input: 5.0),
            ],
            modelsDevEntries: [:],
            builtins: [:]
        )
        #expect(table.pricing(for: "model-x")?.modelID == "a/model-x")
    }

    @Test("点号与 @ 规范化、provider 边界和数字版本守卫")
    func normalizationAndBoundaries() {
        let table = PricingTable(
            liteLLMEntries: [
                "claude-opus-4-7": catalogEntry(id: "claude-opus-4-7", input: 5.0),
                "glm-5.1": catalogEntry(id: "glm-5.1", input: 1.4),
            ],
            modelsDevEntries: [:],
            builtins: [:]
        )
        #expect(table.pricing(for: "claude-opus-4.7-20260416")?.inputPrice == 5.0)
        #expect(table.pricing(for: "provider/glm-5.1")?.inputPrice == 1.4)
        #expect(table.pricing(for: "claude-opus-4.70") == nil)
        #expect(table.pricing(for: "claude-opus-4-9") == nil)
    }

    @Test("alias 仅在原 model primary miss 后解析，fallback 使用 resolved alias")
    func aliasOrdering() {
        let table = PricingTable(
            liteLLMEntries: [
                "gpt-5.3-codex": catalogEntry(id: "gpt-5.3-codex", input: 1.75),
            ],
            modelsDevEntries: [
                "gpt-5.3-codex-spark": pricing(id: "gpt-5.3-codex-spark", input: 99.0),
            ],
            builtins: [:]
        )
        #expect(table.pricing(for: "gpt-5.3-spark")?.inputPrice == 1.75)
    }

    @Test("exact builtin 整条覆盖 LiteLLM；provider fast 显式优先且 override 只补缺失")
    func fastOverlayPriority() {
        let conflictingExact = catalogEntry(
            id: "gpt-5.5",
            input: 99.0,
            explicitFast: 3.0
        )
        let providerExplicit = catalogEntry(
            id: "anthropic/claude-opus-4-6-v1",
            input: 5.0,
            explicitFast: 7.0
        )
        let providerMissing = catalogEntry(
            id: "amazon/claude-opus-4-6-v1",
            input: 5.0
        )
        let table = PricingTable(
            liteLLMEntries: [
                "gpt-5.5": conflictingExact,
                "anthropic/claude-opus-4-6-v1": providerExplicit,
                "amazon/claude-opus-4-6-v1": providerMissing,
            ],
            modelsDevEntries: [:],
            builtins: ["gpt-5.5": pricing(id: "gpt-5.5", input: 5.0, fast: 2.5)]
        )
        #expect(table.pricing(for: "gpt-5.5")?.inputPrice == 5.0)
        #expect(table.pricing(for: "gpt-5.5")?.fastMultiplier == 2.5)
        #expect(table.pricing(
            for: "anthropic/claude-opus-4-6-v1"
        )?.fastMultiplier == 7.0)
        #expect(table.pricing(
            for: "amazon/claude-opus-4-6-v1"
        )?.fastMultiplier == 6.0)
    }

    @Test("long-context overlay 整组补齐，不与已有任意 above 字段混用")
    func longContextOverlayIsAllOrNothing() throws {
        let empty = catalogEntry(id: "gpt-5.4", input: 2.5)
        let partialPricing = ModelPricing(
            modelID: "gpt-5.5",
            displayName: "gpt-5.5",
            inputPrice: 5.0,
            outputPrice: 30.0,
            cacheReadPrice: 0.5,
            cacheWritePrice: 5.0,
            inputPriceAbove200k: 123.0
        )
        let partial = CatalogPricingEntry(pricing: partialPricing, explicitFastMultiplier: nil)
        let table = PricingTable(
            liteLLMEntries: ["gpt-5.4": empty, "gpt-5.5": partial],
            modelsDevEntries: [:],
            builtins: [:]
        )

        let gpt54 = try #require(table.pricing(for: "gpt-5.4"))
        let gpt55 = try #require(table.pricing(for: "gpt-5.5"))
        #expect(gpt54.longContextThreshold == 272_000)
        #expect(gpt54.inputPriceAbove200k == 5.0)
        #expect(gpt54.outputPriceAbove200k == 22.5)
        #expect(gpt54.cacheReadPriceAbove200k == 0.5)
        #expect(gpt55.inputPriceAbove200k == 123.0)
        #expect(gpt55.outputPriceAbove200k == nil)
        #expect(gpt55.longContextThreshold == nil)
    }

    private func catalogEntry(
        id: String,
        input: Double,
        explicitFast: Double? = nil
    ) -> CatalogPricingEntry {
        CatalogPricingEntry(
            pricing: pricing(id: id, input: input, fast: explicitFast ?? 1.0),
            explicitFastMultiplier: explicitFast
        )
    }

    private func pricing(
        id: String,
        input: Double,
        fast: Double = 1.0
    ) -> ModelPricing {
        ModelPricing(
            modelID: id,
            displayName: id,
            inputPrice: input,
            outputPrice: input * 4,
            cacheReadPrice: input * 0.1,
            cacheWritePrice: input * 1.25,
            fastMultiplier: fast
        )
    }
}
```

- [ ] **Step 2: 运行查价测试并确认 RED**

Run:

```bash
xcodebuild -project TokenWatch.xcodeproj -scheme TokenWatch \
  -destination 'platform=macOS' \
  -only-testing:TokenWatchTests/PricingTableTests \
  -skip-testing:TokenWatchUITests \
  -derivedDataPath .build/DerivedData CODE_SIGN_STYLE=Manual DEVELOPMENT_TEAM= CODE_SIGN_IDENTITY=- test
```

Expected: 编译失败，指出 `PricingTable(liteLLMEntries:modelsDevEntries:builtins:)` 不存在；当前 static 手写表也无法满足来源冲突、alias 与 deterministic fuzzy 断言。

- [ ] **Step 3: 用 primary/fallback 双 map 替换 PricingTable 查价骨架**

将 `TokenWatch/Pricing/PricingTable.swift` 的结构和查价函数替换为以下实现；Step 4 紧接着填入完整 builtin map：

```swift
import Foundation
import os.log

struct PricingTable: Sendable {
    private let primary: [String: ModelPricing]
    private let fallback: [String: ModelPricing]

    private static let logger = Logger(
        subsystem: "com.xiaoao.TokenWatch",
        category: "PricingTable"
    )

    static let shared: PricingTable = loadBundled()

    init(
        liteLLMEntries: [String: CatalogPricingEntry],
        modelsDevEntries: [String: ModelPricing],
        builtins: [String: ModelPricing] = Self.builtinPrices
    ) {
        var assembled: [String: CatalogPricingEntry] = [:]
        for (key, entry) in liteLLMEntries {
            let override = Self.builtinFastMultiplier(for: key)
            let fast = entry.explicitFastMultiplier ?? override ?? entry.pricing.fastMultiplier
            assembled[key.lowercased()] = CatalogPricingEntry(
                pricing: Self.replacingFastMultiplier(entry.pricing, with: fast),
                explicitFastMultiplier: entry.explicitFastMultiplier
            )
        }
        for (key, builtin) in builtins {
            // ccusage 在 LiteLLM 之后 insert builtin：同 key 时整条覆盖，
            // 不保留 LiteLLM 的 provider_specific fast。
            assembled[key.lowercased()] = CatalogPricingEntry(
                pricing: builtin,
                explicitFastMultiplier: nil
            )
        }
        var prices = assembled.mapValues(\.pricing)
        for (key, value) in prices {
            prices[key] = Self.applyingLongContextOverlay(value, modelID: key)
        }
        primary = prices
        fallback = Dictionary(
            uniqueKeysWithValues: modelsDevEntries.map { ($0.key.lowercased(), $0.value) }
        )
    }

    func pricing(for modelID: String) -> ModelPricing? {
        let model = modelID.lowercased()
        if let direct = Self.find(model, in: primary) { return direct }

        let alias = Self.alias(for: model)
        if alias != model, let aliased = Self.find(alias, in: primary) { return aliased }

        return Self.find(alias, in: fallback)
    }

    static func pricing(for modelID: String) -> ModelPricing? {
        shared.pricing(for: modelID)
    }

    private static func loadBundled() -> PricingTable {
        do {
            guard let liteURL = Bundle.main.url(
                forResource: "litellm_prices",
                withExtension: "json"
            ), let modelsURL = Bundle.main.url(
                forResource: "models-dev-pricing",
                withExtension: "json"
            ) else {
                logger.error("离线定价资源缺失，仅使用 builtin")
                return PricingTable(
                    liteLLMEntries: [:],
                    modelsDevEntries: [:]
                )
            }
            let lite = try LiteLLMPriceCatalog(data: Data(contentsOf: liteURL))
            let models = try ModelsDevPriceCatalog(data: Data(contentsOf: modelsURL))
            return PricingTable(
                liteLLMEntries: lite.entries,
                modelsDevEntries: models.entries
            )
        } catch {
            logger.error("离线定价资源解析失败：\(error.localizedDescription)")
            return PricingTable(liteLLMEntries: [:], modelsDevEntries: [:])
        }
    }

    private static func find(
        _ model: String,
        in entries: [String: ModelPricing]
    ) -> ModelPricing? {
        if let exact = entries[model] { return exact }
        return entries
            .filter { keyMatches(candidate: $0.key, model: model) }
            .sorted {
                if $0.key.count != $1.key.count {
                    return $0.key.count > $1.key.count
                }
                return $0.key < $1.key
            }
            .first?
            .value
    }

    private static func keyMatches(candidate: String, model: String) -> Bool {
        if containsPricingKey(model, key: candidate)
            || containsPricingKey(candidate, key: model) {
            return true
        }
        let normalizedCandidate = normalizeSeparators(candidate)
        let normalizedModel = normalizeSeparators(model)
        return containsPricingKey(normalizedModel, key: normalizedCandidate)
            || containsPricingKey(normalizedCandidate, key: normalizedModel)
    }

    private static func containsPricingKey(_ value: String, key: String) -> Bool {
        var search = value.startIndex..<value.endIndex
        while let range = value.range(of: key, range: search) {
            let before = range.lowerBound == value.startIndex
                ? nil
                : value[value.index(before: range.lowerBound)]
            let suffix = String(value[range.upperBound...])
            let validBefore = before.map { !$0.isLetter && !$0.isNumber } ?? true
            if validBefore && suffixAllowsMatch(key: key, suffix: suffix) {
                return true
            }
            search = range.upperBound..<value.endIndex
        }
        return false
    }

    private static func suffixAllowsMatch(key: String, suffix: String) -> Bool {
        guard let separator = suffix.first else { return true }
        guard !separator.isLetter && !separator.isNumber else { return false }
        return !suffixStartsWithNumericVersion(key: key, suffix: suffix)
    }

    private static func suffixStartsWithNumericVersion(
        key: String,
        suffix: String
    ) -> Bool {
        guard key.last?.isNumber == true,
              suffix.first == "-" || suffix.first == "." else { return false }
        let rest = suffix.dropFirst()
        let digits = rest.prefix { $0.isNumber }
        guard !digits.isEmpty else { return false }
        let afterDigits = rest.dropFirst(digits.count).first
        let dateLike = digits.count == 8
            && (afterDigits.map { !$0.isLetter && !$0.isNumber } ?? true)
        return !dateLike
    }

    private static func normalizeSeparators(_ value: String) -> String {
        value.replacingOccurrences(of: ".", with: "-")
            .replacingOccurrences(of: "@", with: "-")
    }

    private static func alias(for model: String) -> String {
        model == "gpt-5.3-spark" ? "gpt-5.3-codex-spark" : model
    }
}
```

- [ ] **Step 4: 添加完整 builtin、fast 与 long-context overlay**

把下面代码放入 `PricingTable` 内部：

```swift
private extension PricingTable {
    struct LongContextRates {
        let input: Double
        let output: Double
        let cacheWrite: Double?
        let cacheRead: Double?
    }

    static let builtinPrices: [String: ModelPricing] = {
        func p(
            _ id: String,
            _ input: Double,
            _ output: Double,
            _ cacheRead: Double,
            _ cacheWrite: Double,
            explicitCacheRead: Bool = true,
            inputAbove: Double? = nil,
            outputAbove: Double? = nil,
            cacheReadAbove: Double? = nil,
            cacheWriteAbove: Double? = nil,
            fast: Double = 1.0
        ) -> ModelPricing {
            ModelPricing(
                modelID: id,
                displayName: id,
                inputPrice: input,
                outputPrice: output,
                cacheReadPrice: cacheRead,
                cacheWritePrice: cacheWrite,
                cacheReadPriceIsExplicit: explicitCacheRead,
                inputPriceAbove200k: inputAbove,
                outputPriceAbove200k: outputAbove,
                cacheReadPriceAbove200k: cacheReadAbove,
                cacheWritePriceAbove200k: cacheWriteAbove,
                fastMultiplier: fast
            )
        }

        let claude35Haiku = p("claude-3-5-haiku", 0.8, 4, 0.08, 1)
        let gpt51 = p("gpt-5.1", 1.25, 10, 0.125, 1.25)
        let gpt52Codex = p("gpt-5.2-codex", 1.75, 14, 0.175, 1.75)
        let glmBase = p("glm-4.5", 0.6, 2.2, 0.11, 0)

        var result: [String: ModelPricing] = [
            "claude-opus-4-5": p("claude-opus-4-5", 5, 25, 0.5, 6.25),
            "claude-opus-4-6": p("claude-opus-4-6", 5, 25, 0.5, 6.25, fast: 6),
            "claude-opus-4-7": p("claude-opus-4-7", 5, 25, 0.5, 6.25, fast: 6),
            "claude-opus-4-8": p("claude-opus-4-8", 5, 25, 0.5, 6.25, fast: 2),
            "claude-haiku-4-5": p("claude-haiku-4-5", 1, 5, 0.1, 1.25),
            "claude-opus-4": p("claude-opus-4", 15, 75, 1.5, 18.75),
            "claude-sonnet-4-6": p("claude-sonnet-4-6", 3, 15, 0.3, 3.75),
            "claude-sonnet-4": p(
                "claude-sonnet-4", 3, 15, 0.3, 3.75,
                inputAbove: 6, outputAbove: 22.5,
                cacheReadAbove: 0.6, cacheWriteAbove: 7.5
            ),
            "claude-3-5-haiku": claude35Haiku,
            "claude-3-5-haiku-20241022": ModelPricing(
                modelID: "claude-3-5-haiku-20241022",
                displayName: "claude-3-5-haiku-20241022",
                inputPrice: claude35Haiku.inputPrice,
                outputPrice: claude35Haiku.outputPrice,
                cacheReadPrice: claude35Haiku.cacheReadPrice,
                cacheWritePrice: claude35Haiku.cacheWritePrice
            ),
            "claude-3-opus": p("claude-3-opus", 15, 75, 1.5, 18.75),
            "claude-3-sonnet": p("claude-3-sonnet", 3, 15, 0.3, 3.75),
            "claude-3-haiku": p("claude-3-haiku", 0.25, 1.25, 0.03, 0.3),
            "gpt-5": p("gpt-5", 1.25, 10, 0.125, 1.25),
            "gpt-5.5": p("gpt-5.5", 5, 30, 0.5, 5, fast: 2.5),
            "grok-4.3": p("grok-4.3", 1.25, 2.5, 0.125, 1.25, explicitCacheRead: false),
            "moonshot/kimi-k2.5": p("moonshot/kimi-k2.5", 0.6, 3, 0.1, 0.75),
            "moonshot/kimi-k2.6": p("moonshot/kimi-k2.6", 0.95, 4, 0.16, 1.1875),
            "gpt-5.1": gpt51,
            "gpt-5.1-codex": ModelPricing(
                modelID: "gpt-5.1-codex",
                displayName: "gpt-5.1-codex",
                inputPrice: gpt51.inputPrice,
                outputPrice: gpt51.outputPrice,
                cacheReadPrice: gpt51.cacheReadPrice,
                cacheWritePrice: gpt51.cacheWritePrice
            ),
            "gpt-5.2-codex": gpt52Codex,
            "gpt-5.3-codex": p("gpt-5.3-codex", 1.75, 14, 0.175, 1.75, fast: 2),
            "gpt-5.2": p("gpt-5.2", 1.75, 14, 0.175, 1.75),
            "gpt-5.4": p("gpt-5.4", 2.5, 15, 0.25, 2.5, fast: 2),
            "gpt-5.4-mini": p("gpt-5.4-mini", 0.75, 4.5, 0.075, 0.75),
            "gpt-5.4-nano": p("gpt-5.4-nano", 0.2, 1.25, 0.02, 0.2),
            "gpt-5.6-sol": p("gpt-5.6-sol", 5, 30, 0.5, 6.25),
            "gpt-5.6-terra": p("gpt-5.6-terra", 2.5, 15, 0.25, 3.125),
            "gpt-5.6-luna": p("gpt-5.6-luna", 1, 6, 0.1, 1.25),
            "glm-4.5": glmBase,
            "zai/glm-4.5": p("zai/glm-4.5", 0.6, 2.2, 0.11, 0),
            "zai/glm-4.5-x": p("zai/glm-4.5-x", 2.2, 8.9, 0.45, 0),
            "zai/glm-4.5-air": p("zai/glm-4.5-air", 0.2, 1.1, 0.03, 0),
            "zai/glm-4.5-airx": p("zai/glm-4.5-airx", 1.1, 4.5, 0.22, 0),
            "zai/glm-4.5v": p("zai/glm-4.5v", 0.6, 1.8, 0.11, 0),
            "zai/glm-4-32b-0414-128k": p("zai/glm-4-32b-0414-128k", 0.1, 0.1, 0, 0),
            "zai/glm-4.5-flash": p("zai/glm-4.5-flash", 0, 0, 0, 0),
            "glm-4.6": p("glm-4.6", 0.6, 2.2, 0.11, 0),
            "glm-4.7": p("glm-4.7", 0.6, 2.2, 0.11, 0),
            "glm-5": p("glm-5", 1, 3.2, 0.2, 0),
            "glm-5-turbo": p("glm-5-turbo", 1.2, 4, 0.24, 0),
            "glm-5.1": p("glm-5.1", 1.4, 4.4, 0.26, 0),
        ]
        result["gpt-5.2-codex"] = ModelPricing(
            modelID: "gpt-5.2-codex",
            displayName: "gpt-5.2-codex",
            inputPrice: gpt52Codex.inputPrice,
            outputPrice: gpt52Codex.outputPrice,
            cacheReadPrice: gpt52Codex.cacheReadPrice,
            cacheWritePrice: gpt52Codex.cacheWritePrice
        )
        return result
    }()

    static func builtinFastMultiplier(for modelID: String) -> Double? {
        let exact: [String: Double] = [
            "gpt-5.5": 2.5,
            "gpt-5.4": 2.0,
            "gpt-5.3-codex": 2.0,
        ]
        if let value = exact[modelID] { return value }

        let normalized = normalizeSeparators(modelID)
        let prefixes: [(String, Double)] = [
            ("claude-opus-4-6", 6.0),
            ("claude-opus-4-7", 6.0),
            ("claude-opus-4-8", 2.0),
        ]
        for part in normalized.split(whereSeparator: { $0 == "/" || $0 == ":" }) {
            for (base, multiplier) in prefixes {
                guard let range = part.range(of: base, options: .backwards) else { continue }
                let suffix = part[range.lowerBound...]
                if suffix == base || suffix.dropFirst(base.count).first == "-" {
                    return multiplier
                }
            }
        }
        return nil
    }

    static func replacingFastMultiplier(
        _ pricing: ModelPricing,
        with fast: Double
    ) -> ModelPricing {
        ModelPricing(
            modelID: pricing.modelID,
            displayName: pricing.displayName,
            inputPrice: pricing.inputPrice,
            outputPrice: pricing.outputPrice,
            cacheReadPrice: pricing.cacheReadPrice,
            cacheWritePrice: pricing.cacheWritePrice,
            cacheReadPriceIsExplicit: pricing.cacheReadPriceIsExplicit,
            inputPriceAbove200k: pricing.inputPriceAbove200k,
            outputPriceAbove200k: pricing.outputPriceAbove200k,
            cacheReadPriceAbove200k: pricing.cacheReadPriceAbove200k,
            cacheWritePriceAbove200k: pricing.cacheWritePriceAbove200k,
            longContextThreshold: pricing.longContextThreshold,
            fastMultiplier: fast
        )
    }

    static func applyingLongContextOverlay(
        _ pricing: ModelPricing,
        modelID: String
    ) -> ModelPricing {
        guard pricing.inputPriceAbove200k == nil,
              pricing.outputPriceAbove200k == nil,
              pricing.cacheReadPriceAbove200k == nil,
              pricing.cacheWritePriceAbove200k == nil,
              let rates = longContextRates(for: modelWithoutDateSuffix(modelID)) else {
            return pricing
        }
        return ModelPricing(
            modelID: pricing.modelID,
            displayName: pricing.displayName,
            inputPrice: pricing.inputPrice,
            outputPrice: pricing.outputPrice,
            cacheReadPrice: pricing.cacheReadPrice,
            cacheWritePrice: pricing.cacheWritePrice,
            cacheReadPriceIsExplicit: pricing.cacheReadPriceIsExplicit,
            inputPriceAbove200k: rates.input,
            outputPriceAbove200k: rates.output,
            cacheReadPriceAbove200k: rates.cacheRead,
            cacheWritePriceAbove200k: rates.cacheWrite,
            longContextThreshold: 272_000,
            fastMultiplier: pricing.fastMultiplier
        )
    }

    static func longContextRates(for modelID: String) -> LongContextRates? {
        switch modelID {
        case "gpt-5.6-sol": return LongContextRates(input: 10, output: 45, cacheWrite: 12.5, cacheRead: 1)
        case "gpt-5.6-terra": return LongContextRates(input: 5, output: 22.5, cacheWrite: 6.25, cacheRead: 0.5)
        case "gpt-5.6-luna": return LongContextRates(input: 2, output: 9, cacheWrite: 2.5, cacheRead: 0.2)
        case "gpt-5.5": return LongContextRates(input: 10, output: 45, cacheWrite: 10, cacheRead: 1)
        case "gpt-5.4": return LongContextRates(input: 5, output: 22.5, cacheWrite: 5, cacheRead: 0.5)
        case "gpt-5.5-pro", "gpt-5.4-pro":
            return LongContextRates(input: 60, output: 270, cacheWrite: nil, cacheRead: nil)
        default: return nil
        }
    }

    static func modelWithoutDateSuffix(_ modelID: String) -> String {
        let dashedDate = #"-\d{4}-\d{2}-\d{2}$"#
        let compactDate = #"-\d{8}$"#
        if let range = modelID.range(of: dashedDate, options: .regularExpression) {
            return String(modelID[..<range.lowerBound])
        }
        if let range = modelID.range(of: compactDate, options: .regularExpression) {
            return String(modelID[..<range.lowerBound])
        }
        return modelID
    }
}
```

在 `TokenWatchTests/Pricing/PricingEngineTests.swift` 删除三个与确认设计冲突的手写产品价测试：`exactModelMatch`、`exactDeepseekV4FlashMatch` 以及它们宣称 TokenTracker 价格优先的注释；保留 `exactGLM51Match`。把 LiteLLM fallback 注释改为“filtered LiteLLM primary + 独立 models.dev fallback”。

- [ ] **Step 5: 运行 PricingTable 与既有 PricingEngine 测试并确认 GREEN**

Run:

```bash
xcodebuild -project TokenWatch.xcodeproj -scheme TokenWatch \
  -destination 'platform=macOS' \
  -only-testing:TokenWatchTests/PricingTableTests \
  -only-testing:TokenWatchTests/PricingEngineTests \
  -skip-testing:TokenWatchUITests \
  -derivedDataPath .build/DerivedData CODE_SIGN_STYLE=Manual DEVELOPMENT_TEAM= CODE_SIGN_IDENTITY=- test
```

Expected: 两个 suite 全部通过；`gpt-5-mini` / `gpt-5-nano` 不会被 `gpt-5` fuzzy 抢先，`gpt-5.3-spark` 命中 primary 的 `gpt-5.3-codex` 价格，exact `gpt-5.5` 使用 builtin `2.5` fast，非冲突 provider 条目分别保留显式 `7.0` 或补入 override `6.0`。

- [ ] **Step 6: 提交确定性查价**

```bash
git add TokenWatch/Pricing/PricingTable.swift \
  TokenWatchTests/Pricing/PricingTableTests.swift \
  TokenWatchTests/Pricing/PricingEngineTests.swift
git commit -m "feat(pricing): 对齐 ccusage 定价查找优先级"
```

---

---

### Task 3: PricingEngine 的 marginal tier 与 Codex whole-request tier

**Files:**
- Prerequisite (already modified and GREEN in Provider 数据正确性计划 Task 1): `TokenWatch/Models/TokenUsage.swift`
- Modify: `TokenWatch/Pricing/PricingEngine.swift:94-197`
- Modify: `TokenWatchTests/Pricing/PricingEngineTests.swift`

**Interfaces:**
- Consumes: `PricingTable.shared`、Task 1 的 `ModelPricing.cacheReadPriceIsExplicit` / `longContextThreshold`，以及 Provider 数据正确性计划 Task 1 已产出的 `TokenUsage.cacheCreation: CacheCreation?` 与接受 optional 的显式 initializer。
- Produces: `PricingSemantics.standard` / `.codex`，以及带 `semantics:` 参数的两个 `PricingEngine.calculateCost` overload。

**执行门禁：** 开始本 Task 前，必须已按 Provider 数据正确性计划 Task 1 完成 `TokenUsage.cacheCreation` 的 optional production change，并确认该 Task 的 `TokenUsageDecodingTests`、OpenCode/Codex 扁平 usage 定向测试 GREEN。若尚未完成，停止本计划并先执行该 Task；不能临时把下方 `cacheCreation: nil` 改回零对象绕过依赖。

- [ ] **Step 1: 写 whole-request、implicit cache 和 Codex fast 的失败测试**

在 `PricingEngineTests.swift` 末尾加入：

```swift
extension PricingEngineTests {
    @Test("Codex raw input 超过 272K 时整请求使用 long-context rates")
    func codexWholeRequestLongContext() {
        let pricing = openAIPrice(
            id: "gpt-5.4",
            input: 2.5,
            output: 15,
            cacheRead: 0.25,
            longInput: 5,
            longOutput: 22.5,
            longCacheRead: 0.5,
            fast: 2
        )
        let usage = codexUsage(rawInput: 300_000, cached: 100_000, output: 1_000)

        let cost = PricingEngine().calculateCost(
            usage: usage,
            pricing: pricing,
            semantics: .codex
        )

        #expect(abs(cost - 1.0725) < 1e-9)
    }

    @Test("恰好 272K 保持 base，且两条短请求不能先聚合后切档")
    func codexLongContextIsPerRequestAndStrictlyAboveThreshold() {
        let pricing = openAIPrice(
            id: "gpt-5.4",
            input: 2.5,
            output: 15,
            cacheRead: 0.25,
            longInput: 5,
            longOutput: 22.5,
            longCacheRead: 0.5,
            fast: 2
        )
        let exactlyThreshold = codexUsage(rawInput: 272_000, cached: 0, output: 0)
        let first = codexUsage(rawInput: 150_000, cached: 0, output: 0)
        let second = codexUsage(rawInput: 150_000, cached: 0, output: 0)
        let engine = PricingEngine()

        #expect(abs(engine.calculateCost(
            usage: exactlyThreshold,
            pricing: pricing,
            semantics: .codex
        ) - 0.68) < 1e-9)
        let separate = engine.calculateCost(
            usage: first,
            pricing: pricing,
            semantics: .codex
        ) + engine.calculateCost(
            usage: second,
            pricing: pricing,
            semantics: .codex
        )
        #expect(abs(separate - 0.75) < 1e-9)
    }

    @Test("Codex 非显式 cache read 使用完整 input price，standard 仍使用推导 cache price")
    func codexImplicitCacheReadUsesInputPrice() {
        let pricing = ModelPricing(
            modelID: "gpt-4",
            displayName: "gpt-4",
            inputPrice: 30,
            outputPrice: 60,
            cacheReadPrice: 3,
            cacheWritePrice: 37.5,
            cacheReadPriceIsExplicit: false
        )
        let usage = codexUsage(rawInput: 1_000, cached: 400, output: 0)
        let engine = PricingEngine()

        let codex = engine.calculateCost(
            usage: usage,
            pricing: pricing,
            semantics: .codex
        )
        let standard = engine.calculateCost(
            usage: usage,
            pricing: pricing,
            semantics: .standard
        )

        #expect(abs(codex - 0.03) < 1e-9)
        #expect(abs(standard - 0.0192) < 1e-9)
    }

    @Test("standard OpenAI 阈值只看 inputTokens，Codex 才重建 pure 加 cached")
    func standardLongContextUsesRawInputField() {
        let pricing = openAIPrice(
            id: "gpt-5.4",
            input: 2.5,
            output: 15,
            cacheRead: 0.25,
            longInput: 5,
            longOutput: 22.5,
            longCacheRead: 0.5,
            fast: 2
        )
        let usage = codexUsage(rawInput: 300_000, cached: 100_000, output: 0)
        let engine = PricingEngine()

        let standard = engine.calculateCost(
            usage: usage,
            pricing: pricing,
            semantics: .standard
        )
        let codex = engine.calculateCost(
            usage: usage,
            pricing: pricing,
            semantics: .codex
        )

        #expect(abs(standard - 0.525) < 1e-9)
        #expect(abs(codex - 1.05) < 1e-9)
    }

    @Test("Codex fast 使用模型 multiplier，缺失模型 multiplier 时默认 2")
    func codexFastMultipliers() {
        let gpt54 = openAIPrice(
            id: "gpt-5.4",
            input: 2.5,
            output: 15,
            cacheRead: 0.25,
            longInput: 5,
            longOutput: 22.5,
            longCacheRead: 0.5,
            fast: 2
        )
        let gpt55 = openAIPrice(
            id: "gpt-5.5",
            input: 5,
            output: 30,
            cacheRead: 0.5,
            longInput: 10,
            longOutput: 45,
            longCacheRead: 1,
            fast: 2.5
        )
        let noOverride = ModelPricing(
            modelID: "gpt-private",
            displayName: "gpt-private",
            inputPrice: 1,
            outputPrice: 4,
            cacheReadPrice: 0.1,
            cacheWritePrice: 1.25
        )
        let usage = codexUsage(
            rawInput: 100_000,
            cached: 40_000,
            output: 1_000,
            serviceTier: "fast"
        )
        let defaultUsage = codexUsage(
            rawInput: 100_000,
            cached: 0,
            output: 0,
            serviceTier: "priority"
        )
        let engine = PricingEngine()

        #expect(abs(engine.calculateCost(
            usage: usage,
            pricing: gpt54,
            semantics: .codex
        ) - 0.35) < 1e-9)
        #expect(abs(engine.calculateCost(
            usage: usage,
            pricing: gpt55,
            semantics: .codex
        ) - 0.875) < 1e-9)
        #expect(abs(engine.calculateCost(
            usage: defaultUsage,
            pricing: noOverride,
            semantics: .codex
        ) - 0.2) < 1e-9)
    }

    private func openAIPrice(
        id: String,
        input: Double,
        output: Double,
        cacheRead: Double,
        longInput: Double,
        longOutput: Double,
        longCacheRead: Double,
        fast: Double
    ) -> ModelPricing {
        ModelPricing(
            modelID: id,
            displayName: id,
            inputPrice: input,
            outputPrice: output,
            cacheReadPrice: cacheRead,
            cacheWritePrice: input,
            cacheReadPriceIsExplicit: true,
            inputPriceAbove200k: longInput,
            outputPriceAbove200k: longOutput,
            cacheReadPriceAbove200k: longCacheRead,
            cacheWritePriceAbove200k: longInput,
            longContextThreshold: 272_000,
            fastMultiplier: fast
        )
    }

    private func codexUsage(
        rawInput: Int,
        cached: Int,
        output: Int,
        serviceTier: String = ""
    ) -> TokenUsage {
        let boundedRawInput = max(0, rawInput)
        let boundedCached = min(max(0, cached), boundedRawInput)
        return TokenUsage(
            inputTokens: boundedRawInput - boundedCached,
            cacheCreationInputTokens: 0,
            cacheReadInputTokens: boundedCached,
            outputTokens: output,
            serverToolUse: ServerToolUse(webSearchRequests: 0, webFetchRequests: 0),
            serviceTier: serviceTier,
            cacheCreation: nil,
            inferenceGeo: "",
            iterations: [],
            speed: ""
        )
    }
}
```

- [ ] **Step 2: 运行 PricingEngineTests 并确认 RED**

Run:

```bash
xcodebuild -project TokenWatch.xcodeproj -scheme TokenWatch \
  -destination 'platform=macOS' \
  -only-testing:TokenWatchTests/PricingEngineTests \
  -skip-testing:TokenWatchUITests \
  -derivedDataPath .build/DerivedData CODE_SIGN_STYLE=Manual DEVELOPMENT_TEAM= CODE_SIGN_IDENTITY=- test
```

Expected: 编译失败，报告 `PricingSemantics` 和带 `semantics:` 的 `calculateCost` 不存在。

- [ ] **Step 3: 实现两套计价语义**

保留 `MissingPricingLogOnceGate` 与 `PricingLookupCache`，将 `PricingEngine` 替换为：

```swift
enum PricingSemantics: Sendable, Equatable {
    case standard
    case codex
}

struct PricingEngine: Sendable {
    private static let marginalTierThreshold = 200_000
    private static let cacheCreate1hInputMultiplier = 2.0

    private let logger = Logger(
        subsystem: "com.xiaoao.TokenWatch",
        category: "PricingEngine"
    )
    private let missingPricingLogGate: MissingPricingLogOnceGate
    private let pricingTable: PricingTable
    private let pricingCache = PricingLookupCache()

    var debugCachedPricingCount: Int { pricingCache.count }

    init(
        pricingTable: PricingTable = .shared,
        missingPricingLogGate: MissingPricingLogOnceGate = .shared
    ) {
        self.pricingTable = pricingTable
        self.missingPricingLogGate = missingPricingLogGate
    }

    func calculateCost(
        usage: TokenUsage,
        pricing: ModelPricing,
        semantics: PricingSemantics = .standard
    ) -> Double {
        let baseCacheRead = semantics == .codex && !pricing.cacheReadPriceIsExplicit
            ? pricing.inputPrice
            : pricing.cacheReadPrice
        let cache1hBase = pricing.inputPrice * Self.cacheCreate1hInputMultiplier
        let cache1hAbove = pricing.inputPriceAbove200k.map {
            $0 * Self.cacheCreate1hInputMultiplier
        }

        let subtotal: Double
        if let threshold = pricing.longContextThreshold {
            let rawInput = semantics == .codex
                ? usage.inputTokens + usage.cacheReadInputTokens
                : usage.inputTokens
            let isLong = rawInput > threshold
            let rate: (Double, Double?) -> Double = { base, above in
                isLong ? (above ?? base) : base
            }
            let inputRate = rate(pricing.inputPrice, pricing.inputPriceAbove200k)
            let outputRate = rate(pricing.outputPrice, pricing.outputPriceAbove200k)
            let cacheWriteRate = rate(
                pricing.cacheWritePrice,
                pricing.cacheWritePriceAbove200k
            )
            let cache1hRate = rate(cache1hBase, cache1hAbove)
            let cacheReadRate: Double
            if semantics == .codex && !pricing.cacheReadPriceIsExplicit {
                cacheReadRate = inputRate
            } else {
                cacheReadRate = rate(
                    baseCacheRead,
                    pricing.cacheReadPriceAbove200k
                )
            }
            subtotal = (
                Double(usage.inputTokens) * inputRate
                + Double(usage.outputTokens) * outputRate
                + Double(usage.cacheCreate5mTokens) * cacheWriteRate
                + Double(usage.cacheCreate1hTokens) * cache1hRate
                + Double(usage.cacheReadInputTokens) * cacheReadRate
            ) / 1_000_000.0
        } else {
            subtotal = Self.tieredCost(
                tokens: usage.inputTokens,
                base: pricing.inputPrice,
                above: pricing.inputPriceAbove200k
            ) + Self.tieredCost(
                tokens: usage.outputTokens,
                base: pricing.outputPrice,
                above: pricing.outputPriceAbove200k
            ) + Self.tieredCost(
                tokens: usage.cacheCreate5mTokens,
                base: pricing.cacheWritePrice,
                above: pricing.cacheWritePriceAbove200k
            ) + Self.tieredCost(
                tokens: usage.cacheCreate1hTokens,
                base: cache1hBase,
                above: cache1hAbove
            ) + Self.tieredCost(
                tokens: usage.cacheReadInputTokens,
                base: baseCacheRead,
                above: pricing.cacheReadPriceAbove200k
            )
        }
        return subtotal * multiplier(
            usage: usage,
            pricing: pricing,
            semantics: semantics
        )
    }

    func calculateCost(
        usage: TokenUsage,
        model: String,
        semantics: PricingSemantics = .standard
    ) -> (cost: Double, pricing: ModelPricing?) {
        let normalized = model.lowercased()
        let pricing: ModelPricing?
        if let cached = pricingCache.cachedValue(for: normalized) {
            pricing = cached.pricing
        } else {
            pricing = pricingTable.pricing(for: normalized)
            pricingCache.store(pricing, for: normalized)
        }
        guard let pricing else {
            if missingPricingLogGate.shouldLogMiss(for: normalized) {
                logger.warning("未找到模型定价: \(model)，费用计为 $0.00")
            }
            return (0, nil)
        }
        return (
            calculateCost(usage: usage, pricing: pricing, semantics: semantics),
            pricing
        )
    }

    private static func tieredCost(
        tokens: Int,
        base: Double,
        above: Double?
    ) -> Double {
        guard tokens > 0 else { return 0 }
        if let above, tokens > marginalTierThreshold {
            return (
                Double(marginalTierThreshold) * base
                + Double(tokens - marginalTierThreshold) * above
            ) / 1_000_000.0
        }
        return Double(tokens) * base / 1_000_000.0
    }

    private func multiplier(
        usage: TokenUsage,
        pricing: ModelPricing,
        semantics: PricingSemantics
    ) -> Double {
        switch semantics {
        case .standard:
            return usage.speed == "fast" ? pricing.fastMultiplier : 1
        case .codex:
            guard usage.serviceTier == "fast" || usage.serviceTier == "priority" else {
                return 1
            }
            return pricing.fastMultiplier == 1 ? 2 : pricing.fastMultiplier
        }
    }
}
```

- [ ] **Step 4: 运行 PricingEngineTests 并确认 GREEN**

Run:

```bash
xcodebuild -project TokenWatch.xcodeproj -scheme TokenWatch \
  -destination 'platform=macOS' \
  -only-testing:TokenWatchTests/PricingEngineTests \
  -skip-testing:TokenWatchUITests \
  -derivedDataPath .build/DerivedData CODE_SIGN_STYLE=Manual DEVELOPMENT_TEAM= CODE_SIGN_IDENTITY=- test
```

Expected: 全部通过；新增断言精确得到 `1.0725`、`0.03`、`0.35`、`0.875`，既有 Claude marginal tier / speed 测试保持通过。

- [ ] **Step 5: 提交两类计价算法**

```bash
git add TokenWatch/Pricing/PricingEngine.swift \
  TokenWatchTests/Pricing/PricingEngineTests.swift
git commit -m "feat(pricing): 对齐 Codex 长上下文与缓存计价"
```

---

### Task 4: Auto upstream cost 与 Claude/OpenCode 传播语义

**Files:**
- Modify: `TokenWatch/Analytics/UsageCostResolver.swift:1-21`
- Modify: `TokenWatch/Models/ParsedUsageEntry.swift:24-27`
- Modify: `TokenWatch/Providers/Claude/ClaudeRecord.swift:5-68`
- Modify: `TokenWatch/Providers/Claude/ClaudeJSONLParser.swift:85-99`
- Modify: `TokenWatch/Providers/OpenCode/OpenCodeMessageData.swift:1-48`
- Modify: `TokenWatch/Providers/OpenCode/OpenCodeMessageParser.swift:4-11, 78-79`
- Create: `TokenWatch/Providers/OpenCode/OpenCodePricingCandidateResolver.swift`
- Create: `TokenWatchTests/Analytics/UsageCostResolverTests.swift`
- Modify: `TokenWatchTests/Analytics/UsageAggregatorTests.swift:340-376`
- Modify: `TokenWatchTests/Providers/Claude/ClaudeJSONLParserTests.swift`
- Modify: `TokenWatchTests/Providers/OpenCode/OpenCodeMessageParserTests.swift:1-220`

**Interfaces:**
- Consumes: Task 3 的 `PricingEngine.calculateCost(usage:model:semantics:)`。
- Produces: `UsageCostResolver.init(pricingEngine:)` 与 Auto upstream-first；`ClaudeRecord.costUSD: Double?`；`OpenCodeTokens.billableOutputTokens`；`OpenCodePricingCandidateResolver.candidates(modelKey:providerID:)`。

- [ ] **Step 1: 写 Auto 矩阵、Claude costUSD 与 OpenCode total fallback 的失败测试**

创建 `TokenWatchTests/Analytics/UsageCostResolverTests.swift`：

```swift
import Foundation
import Testing
@testable import TokenWatch

@Suite("UsageCostResolver")
struct UsageCostResolverTests {
    private let resolver: UsageCostResolver = {
        let known = ModelPricing(
            modelID: "claude-sonnet-4-5",
            displayName: "claude-sonnet-4-5",
            inputPrice: 3,
            outputPrice: 15,
            cacheReadPrice: 0.3,
            cacheWritePrice: 3.75
        )
        let table = PricingTable(
            liteLLMEntries: [
                "claude-sonnet-4-5": CatalogPricingEntry(
                    pricing: known,
                    explicitFastMultiplier: nil
                ),
                "moonshot/kimi-k2.6": CatalogPricingEntry(
                    pricing: ModelPricing(
                        modelID: "moonshot/kimi-k2.6",
                        displayName: "moonshot/kimi-k2.6",
                        inputPrice: 0.95,
                        outputPrice: 4,
                        cacheReadPrice: 0.16,
                        cacheWritePrice: 1.1875
                    ),
                    explicitFastMultiplier: nil
                ),
            ],
            modelsDevEntries: [:],
            builtins: [:]
        )
        return UsageCostResolver(
            pricingEngine: PricingEngine(pricingTable: table)
        )
    }()

    @Test("Auto 有 upstream 时 authoritative，包含已知模型和显式零")
    func authoritativeUpstream() {
        #expect(resolver.resolvedCost(for: entry(
            model: "claude-sonnet-4-5",
            provider: .claude,
            upstreamCost: 0.123
        )) == 0.123)
        #expect(resolver.resolvedCost(for: entry(
            model: "claude-sonnet-4-5",
            provider: .claude,
            upstreamCost: 0
        )) == 0)
        #expect(resolver.resolvedCost(for: entry(
            model: "private-model",
            provider: .claude,
            upstreamCost: 0.123
        )) == 0.123)
    }

    @Test("Auto upstream 缺失时才查本地，未知模型为零")
    func calculatesOnlyWhenUpstreamMissing() {
        let local = resolver.resolvedCost(for: entry(
            model: "claude-sonnet-4-5",
            provider: .claude,
            upstreamCost: nil
        ))
        let unknown = resolver.resolvedCost(for: entry(
            model: "private-model",
            provider: .claude,
            upstreamCost: nil
        ))
        #expect(abs(local - 0.0045) < 1e-9)
        #expect(unknown == 0)
    }

    @Test("OpenCode 按 ccusage 候选顺序解析 provider 与 k2p6 alias")
    func openCodeProviderAndAliasCandidates() {
        #expect(OpenCodePricingCandidateResolver.candidates(
            modelKey: "github-copilot/claude-sonnet-4.5",
            providerID: "github-copilot"
        ) == [
            "claude-sonnet-4.5",
            "claude-sonnet-4-5",
            "github_copilot/claude-sonnet-4.5",
            "github_copilot/claude-sonnet-4-5",
        ])

        let cost = resolver.resolvedCost(for: entry(
            model: "kimi-for-coding/k2p6",
            provider: .opencode,
            upstreamCost: nil,
            upstreamProviderID: "kimi-for-coding"
        ))
        // helper 固定 input=1_000/output=100：0.95/M + 4.0/M = 0.00135。
        #expect(abs(cost - 0.00135) < 1e-9)
    }

    private func entry(
        model: String,
        provider: ProviderID,
        upstreamCost: Double?,
        upstreamProviderID: String? = nil
    ) -> ParsedUsageEntry {
        ParsedUsageEntry(
            recordUUID: UUID().uuidString,
            messageId: UUID().uuidString,
            requestId: nil,
            sessionID: "session",
            timestamp: Date(timeIntervalSince1970: 0),
            model: model,
            cwd: "/tmp",
            agentId: nil,
            usage: TokenUsage(
                inputTokens: 1_000,
                cacheCreationInputTokens: 0,
                cacheReadInputTokens: 0,
                outputTokens: 100,
                serverToolUse: ServerToolUse(webSearchRequests: 0, webFetchRequests: 0),
                serviceTier: "standard",
                cacheCreation: CacheCreation(
                    ephemeral1hInputTokens: 0,
                    ephemeral5mInputTokens: 0
                ),
                inferenceGeo: "",
                iterations: [],
                speed: "standard"
            ),
            isSubagent: false,
            provider: provider,
            upstreamProviderID: upstreamProviderID,
            upstreamCost: upstreamCost
        )
    }
}
```

在 `ClaudeJSONLParserTests` 中加入：

```swift
@Test("Claude 顶层 costUSD 正数和显式零原样传播")
func propagatesCostUSDIncludingZero() throws {
    let lines = [
        #"{"type":"assistant","uuid":"u1","sessionId":"s1","timestamp":"2026-06-13T12:00:00Z","costUSD":0.123,"message":{"id":"m1","role":"assistant","model":"claude-sonnet-4-5","usage":{"input_tokens":1,"output_tokens":1}}}"#,
        #"{"type":"assistant","uuid":"u2","sessionId":"s1","timestamp":"2026-06-13T12:01:00Z","costUSD":0,"message":{"id":"m2","role":"assistant","model":"claude-sonnet-4-5","usage":{"input_tokens":1,"output_tokens":1}}}"#,
    ]
    let dir = FileManager.default.temporaryDirectory
        .appendingPathComponent("ClaudeCostUSD-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: dir) }
    let url = dir.appendingPathComponent("cost.jsonl")
    try (lines.joined(separator: "\n") + "\n").write(
        to: url,
        atomically: true,
        encoding: .utf8
    )
    let info = ClaudeJSONLFileInfo(
        url: url,
        sessionID: "s1",
        projectPath: "/tmp",
        isSubagent: false,
        agentId: nil
    )

    let entries = try ClaudeJSONLParser()
        .parseJSONLFile(info, claudeDataRoot: dir)
        .sorted { $0.messageId < $1.messageId }

    #expect(entries.map(\.upstreamCost) == [0.123, 0])
}
```

把 `UsageAggregatorTests.upstreamCostDoesNotPolluteEngineCost` 替换为：

```swift
@Test("Auto 模式已知模型也优先 upstreamCost")
func upstreamCostWinsForKnownModel() {
    let entries = [
        makeEntry(
            sessionID: "s1",
            date: date(2026, 6, 13),
            model: "claude-sonnet-4-5",
            input: 1_000,
            output: 500,
            upstreamCost: 999.99
        ),
    ]
    #expect(aggregator.aggregate(entries).overall.cost == 999.99)
}
```

在 `OpenCodeMessageParserTests` 中加入：

```swift
@Test("tokens.total-only 把全部缺口并入可计费 output")
func totalOnlyFallsBackToBillableOutput() throws {
    let row = makeRow(
        id: "total-only",
        sessionID: "s",
        timeMs: 0,
        json: #"{"role":"assistant","modelID":"claude-sonnet-4-5","providerID":"anthropic","tokens":{"total":123}}"#,
        directory: "/d"
    )

    let entry = try #require(parser.parseAll([row]).first)
    #expect(entry.usage.inputTokens == 0)
    #expect(entry.usage.cacheReadInputTokens == 0)
    #expect(entry.usage.totalCacheCreationTokens == 0)
    #expect(entry.usage.outputTokens == 123)
    #expect(entry.usage.reasoningTokens == 0)
}

@Test("tokens.total 只补 known token 之外的余量，不重复计费")
func partialTotalAddsOnlyMissingRemainder() throws {
    let row = makeRow(
        id: "partial-total",
        sessionID: "s",
        timeMs: 0,
        json: #"{"role":"assistant","modelID":"claude-sonnet-4-5","providerID":"anthropic","tokens":{"total":200,"input":100,"output":10,"cache":{"read":50,"write":25}}}"#,
        directory: "/d"
    )

    let entry = try #require(parser.parseAll([row]).first)
    #expect(entry.usage.inputTokens == 100)
    #expect(entry.usage.cacheReadInputTokens == 50)
    #expect(entry.usage.totalCacheCreationTokens == 25)
    #expect(entry.usage.outputTokens == 25) // 10 + max(200 - 185, 0)
    #expect(entry.usage.reasoningTokens == 0)
}

@Test("OpenCode token 坏类型归零而不丢整行，reasoning-only 不计入")
func lenientTokenFieldsMatchPinnedAdapter() throws {
    let usable = makeRow(
        id: "usable",
        sessionID: "s",
        timeMs: 0,
        json: #"{"role":"assistant","modelID":" claude-sonnet-4-5 ","providerID":"anthropic","cost":"bad","path":5,"tokens":{"input":"100","output":10,"cache":"bad"}}"#,
        directory: "/d"
    )
    let reasoningOnly = makeRow(
        id: "reasoning-only",
        sessionID: "s",
        timeMs: 1,
        json: #"{"role":"assistant","modelID":"claude-sonnet-4-5","providerID":"anthropic","tokens":{"reasoning":20}}"#,
        directory: "/d"
    )

    let entries = parser.parseAll([usable, reasoningOnly])

    #expect(entries.count == 1)
    #expect(entries.first?.recordUUID == "usable")
    #expect(entries.first?.usage.inputTokens == 0)
    #expect(entries.first?.usage.outputTokens == 10)
}
```

- [ ] **Step 2: 运行 Auto 与 parser 测试并确认 RED**

Run:

```bash
xcodebuild -project TokenWatch.xcodeproj -scheme TokenWatch \
  -destination 'platform=macOS' \
  -only-testing:TokenWatchTests/UsageCostResolverTests \
  -only-testing:TokenWatchTests/UsageAggregatorTests \
  -only-testing:TokenWatchTests/ClaudeJSONLParserTests \
  -only-testing:TokenWatchTests/OpenCodeMessageParserTests \
  -skip-testing:TokenWatchUITests \
  -derivedDataPath .build/DerivedData CODE_SIGN_STYLE=Manual DEVELOPMENT_TEAM= CODE_SIGN_IDENTITY=- test
```

Expected: 编译先报告 `OpenCodePricingCandidateResolver` 不存在；补齐测试 seam 后，`UsageCostResolverTests.authoritativeUpstream` 和 aggregator 已知模型断言仍失败，Claude 测试报告 `upstreamCost` 为 nil，OpenCode total-only / partial-total 因子字段强制解码而被整行跳过。

- [ ] **Step 3: 实现 Auto upstream-first、Claude 传播与 OpenCode total fallback**

创建 `TokenWatch/Providers/OpenCode/OpenCodePricingCandidateResolver.swift`：

```swift
import Foundation

enum OpenCodePricingCandidateResolver {
    static func candidates(modelKey: String, providerID: String?) -> [String] {
        let rawModel: String
        if let providerID,
           modelKey.hasPrefix("\(providerID)/") {
            rawModel = String(modelKey.dropFirst(providerID.count + 1))
        } else {
            rawModel = modelKey
        }

        let resolved: String
        switch rawModel {
        case "gemini-3-pro-high": resolved = "gemini-3-pro-preview"
        case "k2p6": resolved = "kimi-k2.6"
        default: resolved = rawModel
        }

        let normalized = normalizeClaudeModel(resolved)
        var base = [resolved]
        if normalized != resolved { base.append(normalized) }
        var result = base
        if let providerID,
           !providerID.isEmpty,
           providerID != "unknown" {
            let provider = providerID.replacingOccurrences(of: "-", with: "_")
            result.append(contentsOf: base.map { "\(provider)/\($0)" })
        }

        var seen: Set<String> = []
        return result.filter { seen.insert($0).inserted }
    }

    private static func normalizeClaudeModel(_ model: String) -> String {
        for family in ["claude-haiku-", "claude-opus-", "claude-sonnet-"] {
            guard model.hasPrefix(family) else { continue }
            let rest = String(model.dropFirst(family.count))
            if let dot = rest.firstIndex(of: ".") {
                let major = rest[..<dot]
                let minorAndSuffix = rest[rest.index(after: dot)...]
                if !major.isEmpty,
                   major.allSatisfy(\.isNumber),
                   minorAndSuffix.first?.isNumber == true {
                    return "\(family)\(major)-\(minorAndSuffix)"
                }
            }
            let chars = Array(rest)
            if chars.count >= 2,
               chars[0].isNumber,
               chars[1].isNumber {
                return "\(family)\(chars[0])-\(String(chars.dropFirst(1)))"
            }
        }
        return model
    }
}
```

先为 `OpenCodeMessageData` 增加自定义解码：只有 JSON number 才作为 cost，坏类型的 cost/path/tokens 分别视为 nil，不得令其他可用字段的整行解码失败；model/provider 保留 trim 后非空字符串：

```swift
init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    role = (try? container.decode(String.self, forKey: .role)) ?? ""
    modelID = container.nonEmptyString(forKey: .modelID)
    providerID = container.nonEmptyString(forKey: .providerID)
    cost = try? container.decode(Double.self, forKey: .cost)
    tokens = try? container.decode(OpenCodeTokens.self, forKey: .tokens)
    path = try? container.decode(OpenCodePath.self, forKey: .path)
}
```

再将 `OpenCodeTokens` 和 `OpenCodeCache` 替换为：

```swift
/// `data.tokens` 子结构。OpenCode 历史数据可能只写 `total`，
/// 因此所有子字段都按 ccusage 的 serde default 语义宽容解码。
struct OpenCodeTokens: Decodable {
    let input: Int
    let output: Int
    let reasoning: Int
    let total: Int
    let cache: OpenCodeCache

    enum CodingKeys: String, CodingKey {
        case input, output, reasoning, total, cache
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        input = container.lenientUnsignedInt(forKey: .input)
        output = container.lenientUnsignedInt(forKey: .output)
        reasoning = container.lenientUnsignedInt(forKey: .reasoning)
        total = container.lenientUnsignedInt(forKey: .total)
        cache = (try? container.decode(OpenCodeCache.self, forKey: .cache)) ?? .zero
    }

    /// ccusage `apply_total_token_fallback` 将 total 中未被已知类别覆盖的余量
    /// 按 output rate 计费。TokenWatch 没有 extra-total 维度，因此并入 output。
    var billableOutputTokens: Int {
        let known = input + output + cache.read + cache.write
        return output + max(total - known, 0)
    }

    /// 已应用 total fallback 后仍全 0 才是可跳过的空 usage。
    var isAllZero: Bool {
        // pinned OpenCode adapter 不把 tokens.reasoning 映射到 TokenUsageRaw；
        // total 若包含它，会由 total fallback 以 output rate 计价。
        input == 0 && billableOutputTokens == 0
            && cache.read == 0 && cache.write == 0
    }
}

struct OpenCodeCache: Decodable {
    let read: Int
    let write: Int

    enum CodingKeys: String, CodingKey {
        case read, write
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        read = container.lenientUnsignedInt(forKey: .read)
        write = container.lenientUnsignedInt(forKey: .write)
    }

    private init(read: Int, write: Int) {
        self.read = read
        self.write = write
    }

    static let zero = OpenCodeCache(read: 0, write: 0)
}

private struct LenientUnsignedInt: Decodable {
    let value: Int

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let raw = (try? container.decode(UInt64.self)) ?? 0
        value = Int(min(raw, UInt64(Int.max)))
    }
}

private extension KeyedDecodingContainer {
    func lenientUnsignedInt(forKey key: Key) -> Int {
        guard contains(key), (try? decodeNil(forKey: key)) != true else { return 0 }
        return (try? decode(LenientUnsignedInt.self, forKey: key).value) ?? 0
    }

    func nonEmptyString(forKey key: Key) -> String? {
        guard let value = try? decode(String.self, forKey: key) else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
```

在 `OpenCodeMessageParser` 构造 `TokenUsage` 时把 output 映射改为：

```swift
outputTokens: tokens.billableOutputTokens,
```

将 `UsageCostResolver.swift` 替换为：

```swift
import Foundation

/// 以 ccusage 默认 Auto 模式解析单条记录成本。
struct UsageCostResolver: Sendable {
    private let pricingEngine: PricingEngine

    init(pricingEngine: PricingEngine = PricingEngine()) {
        self.pricingEngine = pricingEngine
    }

    func resolvedCost(for entry: ParsedUsageEntry) -> Double {
        if let upstreamCost = entry.upstreamCost {
            return upstreamCost
        }
        if entry.provider == .opencode {
            for candidate in OpenCodePricingCandidateResolver.candidates(
                modelKey: entry.model,
                providerID: entry.upstreamProviderID
            ) {
                let result = pricingEngine.calculateCost(
                    usage: entry.usage,
                    model: candidate,
                    semantics: .standard
                )
                if result.cost > 0 { return result.cost }
            }
            return 0
        }
        let semantics: PricingSemantics = entry.provider == .codex
            ? .codex
            : .standard
        return pricingEngine.calculateCost(
            usage: entry.usage,
            model: entry.model,
            semantics: semantics
        ).cost
    }
}
```

在 `ClaudeRecord` 中加入字段与 CodingKey，并在初始化器末尾解码：

```swift
let costUSD: Double?

enum CodingKeys: String, CodingKey {
    case type, uuid, sessionId, timestamp
    case parentUuid, isSidechain, cwd, gitBranch
    case version, userType, entrypoint
    case message, subtype, agentId, slug, permissionMode, requestId
    case costUSD
}

// init(from:) 末尾
costUSD = try container.decodeIfPresent(Double.self, forKey: .costUSD)
```

把 `ClaudeJSONLParser` 构造 entry 的最后一项改成：

```swift
upstreamCost: record.costUSD
```

把 `ParsedUsageEntry.upstreamCost` 注释改成：

```swift
/// 数据源自带的单条 cost(USD)；Auto 模式下只要非 nil 就优先于本地计价。
/// Claude 可传播显式 0；OpenCode adapter 只传播大于 0 的值。
let upstreamCost: Double?
```

把 `OpenCodeMessageParser` 对应注释改成：

```swift
// OpenCode provider-specific 规则：只有严格大于 0 的 cost 才 authoritative；
// 0 与缺失都保持 nil，让 UsageCostResolver 尝试本地 token 计价。
let upstreamCost: Double? = parsed.cost.flatMap { $0 > 0 ? $0 : nil }
```

- [ ] **Step 4: 运行 Auto 与 parser 测试并确认 GREEN**

Run:

```bash
xcodebuild -project TokenWatch.xcodeproj -scheme TokenWatch \
  -destination 'platform=macOS' \
  -only-testing:TokenWatchTests/UsageCostResolverTests \
  -only-testing:TokenWatchTests/UsageAggregatorTests \
  -only-testing:TokenWatchTests/ClaudeJSONLParserTests \
  -only-testing:TokenWatchTests/OpenCodeMessageParserTests \
  -skip-testing:TokenWatchUITests \
  -derivedDataPath .build/DerivedData CODE_SIGN_STYLE=Manual DEVELOPMENT_TEAM= CODE_SIGN_IDENTITY=- test
```

Expected: 四个 suite 全部通过；Claude `0` 保留为非 nil，OpenCode `cost == 0` 仍解析为 nil，total-only `123` 产生 `outputTokens == 123`，partial-total 只补 `15` 个 token，`k2p6` 在无上游 cost 时通过 ccusage 候选得到 `$4.95`。

- [ ] **Step 5: 提交 Auto upstream 与 OpenCode total fallback**

```bash
git add TokenWatch/Analytics/UsageCostResolver.swift \
  TokenWatch/Models/ParsedUsageEntry.swift \
  TokenWatch/Providers/Claude/ClaudeRecord.swift \
  TokenWatch/Providers/Claude/ClaudeJSONLParser.swift \
  TokenWatch/Providers/OpenCode/OpenCodeMessageData.swift \
  TokenWatch/Providers/OpenCode/OpenCodeMessageParser.swift \
  TokenWatch/Providers/OpenCode/OpenCodePricingCandidateResolver.swift \
  TokenWatchTests/Analytics/UsageCostResolverTests.swift \
  TokenWatchTests/Analytics/UsageAggregatorTests.swift \
  TokenWatchTests/Providers/Claude/ClaudeJSONLParserTests.swift \
  TokenWatchTests/Providers/OpenCode/OpenCodeMessageParserTests.swift
git commit -m "fix(pricing): 对齐 Auto 与 OpenCode token 回退"
```

---

### Task 5: Codex service tier、模型 fallback 与真实模型覆盖

**Files:**
- Create: `TokenWatch/Providers/Codex/CodexServiceTierResolver.swift`
- Create: `TokenWatch/Providers/Codex/CodexModelResolver.swift`
- Modify: `TokenWatch/Providers/Codex/CodexRecord.swift:77-96`
- Modify: `TokenWatch/Providers/Codex/CodexRolloutParser.swift:12-250`
- Modify: `TokenWatch/Providers/Codex/CodexProvider.swift:5-26`
- Create: `TokenWatchTests/Providers/Codex/CodexServiceTierResolverTests.swift`
- Create: `TokenWatchTests/Providers/Codex/CodexModelResolverTests.swift`
- Modify: `TokenWatchTests/Providers/Codex/CodexRecordTests.swift`
- Modify: `TokenWatchTests/Providers/Codex/CodexRolloutParserTests.swift`

**Interfaces:**
- Consumes: `TokenUsage.serviceTier` 与 Task 3 的 `.codex` fast/cache 语义及 `PricingEngine.calculateCost(usage:model:semantics:)`。
- Produces: `CodexPricingSpeed`、只接受顶层 `service_tier` 的 `CodexServiceTierResolver`、`CodexModelState`、`CodexModelResolver.resolve(parsedModel:eventDate:current:)`，以及带 `pricingSpeed:` 的 parser API。

- [ ] **Step 1: 写 service tier 与模型状态的失败测试**

创建 `TokenWatchTests/Providers/Codex/CodexServiceTierResolverTests.swift`：

```swift
import Testing
@testable import TokenWatch

@Suite("CodexServiceTierResolver")
struct CodexServiceTierResolverTests {
    @Test("只识别顶层 service_tier fast 或 priority")
    func detectsFastAndPriority() {
        #expect(CodexServiceTierResolver.pricingSpeed(
            in: #"service_tier = "fast""#
        ) == .fast)
        #expect(CodexServiceTierResolver.pricingSpeed(
            in: "service_tier = 'priority' # higher tier"
        ) == .fast)
        #expect(CodexServiceTierResolver.pricingSpeed(
            in: #"service_tier = "standard""#
        ) == .standard)
        #expect(CodexServiceTierResolver.pricingSpeed(
            in: #"service_tier_override = "fast""#
        ) == .standard)
        #expect(CodexServiceTierResolver.pricingSpeed(
            in: #"service_tier = "breakfast""#
        ) == .standard)
    }

    @Test("TOML table 内同名 service_tier 不得冒充顶层设置")
    func rejectsServiceTierInsideTables() {
        let nestedConfigurations = [
            """
            [model_providers.openai]
            service_tier = "fast"
            """,
            """
            [profiles.fast]
            model = "gpt-5.4"
            service_tier = "priority"
            """,
            """
            [[profiles]]
            name = "fast"
            service_tier = "fast"
            """,
        ]

        for contents in nestedConfigurations {
            #expect(
                CodexServiceTierResolver.pricingSpeed(in: contents) == .standard,
                Comment(contents)
            )
        }

        #expect(CodexServiceTierResolver.pricingSpeed(in: """
        service_tier = "priority"
        [profiles.default]
        service_tier = "standard"
        """) == .fast)
    }
}
```

创建 `TokenWatchTests/Providers/Codex/CodexModelResolverTests.swift`：

```swift
import Foundation
import Testing
@testable import TokenWatch

@Suite("CodexModelResolver")
struct CodexModelResolverTests {
    @Test("无模型回退 gpt-5，真实模型随后覆盖 fallback")
    func missingThenExplicit() {
        var state: CodexModelState?
        let fallback = CodexModelResolver.resolve(
            parsedModel: nil,
            eventDate: date("2026-01-01T00:00:00Z"),
            current: &state
        )
        #expect(fallback == "gpt-5")
        #expect(state?.source == .fallback)

        let explicit = CodexModelResolver.resolve(
            parsedModel: "gpt-real",
            eventDate: date("2026-01-01T00:01:00Z"),
            current: &state
        )
        #expect(explicit == "gpt-real")
        #expect(state == CodexModelState(rawModel: "gpt-real", source: .explicit))
    }

    @Test("codex-auto-review 按 ccusage 固定发布日期映射")
    func autoReviewDateMap() {
        let cases = [
            ("2026-04-23T00:00:00Z", "gpt-5.5"),
            ("2026-03-05T00:00:00Z", "gpt-5.4"),
            ("2026-02-05T00:00:00Z", "gpt-5.3-codex"),
            ("2025-12-11T00:00:00Z", "gpt-5.2-codex"),
            ("2025-11-13T00:00:00Z", "gpt-5.1-codex"),
            ("2025-09-15T00:00:00Z", "gpt-5-codex"),
            ("2025-08-07T00:00:00Z", "gpt-5"),
            ("2025-01-01T00:00:00Z", "gpt-5"),
        ]

        for (timestamp, expected) in cases {
            var state: CodexModelState?
            let resolved = CodexModelResolver.resolve(
                parsedModel: "codex-auto-review",
                eventDate: date(timestamp),
                current: &state
            )
            #expect(resolved == expected, Comment(timestamp))
            #expect(state?.source == .fallback)
        }

        var missingDateState: CodexModelState?
        #expect(CodexModelResolver.resolve(
            parsedModel: "codex-auto-review",
            eventDate: nil,
            current: &missingDateState
        ) == "gpt-5")
    }

    private func date(_ value: String) -> Date {
        ISO8601DateFormatter().date(from: value)!
    }
}
```

在 `CodexRecordTests` 中加入：

```swift
@Test("event payload 与 info model 均可解码")
func decodeEventModels() throws {
    let payloadModel = #"{"timestamp":"2026-05-04T08:35:59Z","type":"event_msg","payload":{"type":"token_count","model":"gpt-payload","info":{"model":"gpt-info","last_token_usage":{"input_tokens":1,"output_tokens":1}}}}"#
    let record = try decoder.decode(CodexRecord.self, from: Data(payloadModel.utf8))
    guard case let .eventMsg(event) = record.payload else {
        Issue.record("payload 应为 eventMsg")
        return
    }
    #expect(event.model == "gpt-payload")
    #expect(event.info?.model == "gpt-info")
}
```

- [ ] **Step 2: 运行 resolver/record 测试并确认 RED**

Run:

```bash
xcodebuild -project TokenWatch.xcodeproj -scheme TokenWatch \
  -destination 'platform=macOS' \
  -only-testing:TokenWatchTests/CodexServiceTierResolverTests \
  -only-testing:TokenWatchTests/CodexModelResolverTests \
  -only-testing:TokenWatchTests/CodexRecordTests \
  -skip-testing:TokenWatchUITests \
  -derivedDataPath .build/DerivedData CODE_SIGN_STYLE=Manual DEVELOPMENT_TEAM= CODE_SIGN_IDENTITY=- test
```

Expected: 编译失败，报告 resolver 类型不存在，且 `CodexEventMsg` / `CodexTokenCountInfo` 没有 `model`。如果只先补入旧的逐行 key/value 实现，`rejectsServiceTierInsideTables` 仍会 RED，因为 table 内的同名键会被错误识别成 `.fast`。

- [ ] **Step 3: 实现 service tier 与模型 resolver**

创建 `TokenWatch/Providers/Codex/CodexServiceTierResolver.swift`：

```swift
import Foundation

enum CodexPricingSpeed: Sendable, Equatable {
    case standard
    case fast
}

struct CodexServiceTierResolver: Sendable {
    static func pricingSpeed(in contents: String) -> CodexPricingSpeed {
        var isTopLevel = true
        for line in contents.split(whereSeparator: \.isNewline) {
            let setting = String(line.split(separator: "#", maxSplits: 1).first ?? "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard !setting.isEmpty else { continue }

            // TOML table header 之后的裸 key 都属于该 table；TOML 没有
            // “返回文档根部”的 header，因此一旦进入 section 就保持 false。
            if setting.hasPrefix("[") {
                isTopLevel = false
                continue
            }

            guard isTopLevel else { continue }
            guard let equals = setting.firstIndex(of: "=") else { continue }
            let key = String(setting[..<equals]).trimmingCharacters(in: .whitespaces)
            guard key == "service_tier" else { continue }
            let rawValue = String(setting[setting.index(after: equals)...])
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
            if rawValue == "fast" || rawValue == "priority" {
                return .fast
            }
        }
        return .standard
    }

    func pricingSpeed(at codexRoot: URL) -> CodexPricingSpeed {
        let configURL = codexRoot.appendingPathComponent("config.toml")
        guard let contents = try? String(contentsOf: configURL, encoding: .utf8) else {
            return .standard
        }
        return Self.pricingSpeed(in: contents)
    }
}
```

创建 `TokenWatch/Providers/Codex/CodexModelResolver.swift`：

```swift
import Foundation

enum CodexModelSource: Sendable, Equatable {
    case explicit
    case fallback
}

struct CodexModelState: Sendable, Equatable {
    let rawModel: String
    let source: CodexModelSource
}

enum CodexModelResolver {
    private static let autoReviewModel = "codex-auto-review"
    private static let fallbackModels: [(releasedOn: String, model: String)] = [
        ("2026-04-23", "gpt-5.5"),
        ("2026-03-05", "gpt-5.4"),
        ("2026-02-05", "gpt-5.3-codex"),
        ("2025-12-11", "gpt-5.2-codex"),
        ("2025-11-13", "gpt-5.1-codex"),
        ("2025-09-15", "gpt-5-codex"),
        ("2025-08-07", "gpt-5"),
    ]

    static func resolve(
        parsedModel: String?,
        eventDate: Date?,
        current: inout CodexModelState?
    ) -> String {
        if let parsedModel, !parsedModel.isEmpty {
            current = CodexModelState(
                rawModel: parsedModel,
                source: parsedModel == autoReviewModel ? .fallback : .explicit
            )
        }
        if current == nil {
            current = CodexModelState(rawModel: "gpt-5", source: .fallback)
        }
        let state = current!
        guard state.rawModel == autoReviewModel else { return state.rawModel }
        guard let eventDate else { return "gpt-5" }
        let key = dateKey(eventDate)
        return fallbackModels.first { key >= $0.releasedOn }?.model ?? "gpt-5"
    }

    private static func dateKey(_ date: Date) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        return String(
            format: "%04d-%02d-%02d",
            parts.year ?? 0,
            parts.month ?? 0,
            parts.day ?? 0
        )
    }
}
```

在 `CodexRecord.swift` 中将两个结构改为：

```swift
struct CodexEventMsg: Decodable, Sendable {
    let type: String
    let info: CodexTokenCountInfo?
    let model: String?
}

struct CodexTokenCountInfo: Decodable, Sendable {
    let lastTokenUsage: CodexTokenCounts?
    let totalTokenUsage: CodexTokenCounts?
    let model: String?

    enum CodingKeys: String, CodingKey {
        case lastTokenUsage = "last_token_usage"
        case totalTokenUsage = "total_token_usage"
        case model
    }
}
```

- [ ] **Step 4: 写 parser fallback、speed、cache invalidation 与 cached clamp 的失败测试**

把现有 `CodexRolloutParserTests.skipsWhenNoModel` 替换为：

```swift
@Test("currentModel 缺失时回退 gpt-5")
func fallsBackWhenNoModel() throws {
    let (file, cleanup) = try makeJsonlFile([sessionMeta, normalEvent])
    defer { cleanup() }

    let entries = try CodexRolloutParser().parseFile(file)
    #expect(entries.count == 1)
    #expect(entries[0].model == "gpt-5")
}
```

在同一 suite 加入：

```swift
@Test("event/info 真实模型覆盖先前 fallback")
func eventModelOverridesFallback() throws {
    let fallbackEvent = #"{"timestamp":"2026-01-01T00:00:00Z","type":"event_msg","payload":{"type":"token_count","info":{"last_token_usage":{"input_tokens":10,"output_tokens":1}}}}"#
    let realEvent = #"{"timestamp":"2026-01-01T00:01:00Z","type":"event_msg","payload":{"type":"token_count","info":{"model":"gpt-real","last_token_usage":{"input_tokens":20,"output_tokens":2}}}}"#
    let (file, cleanup) = try makeJsonlFile([sessionMeta, fallbackEvent, realEvent])
    defer { cleanup() }

    let entries = try CodexRolloutParser().parseFile(file)
        .sorted { ($0.timestamp ?? .distantPast) < ($1.timestamp ?? .distantPast) }
    #expect(entries.map(\.model) == ["gpt-5", "gpt-real"])
}

@Test("pricing speed 改变时 rollout cache 失效并传播 fast")
func pricingSpeedInvalidatesCache() throws {
    let (file, cleanup) = try makeJsonlFile([sessionMeta, turnContextGpt5, normalEvent])
    defer { cleanup() }
    let parser = CodexRolloutParser()

    let standard = try parser.parseAllFiles([file], pricingSpeed: .standard)
    let hitsBefore = parser.debugCacheHitCount
    let fast = try parser.parseAllFiles([file], pricingSpeed: .fast)

    #expect(standard.first?.usage.serviceTier == "")
    #expect(fast.first?.usage.serviceTier == "fast")
    #expect(parser.debugCacheHitCount == hitsBefore)
}

@Test("cached input 超过 raw input 时夹到 raw input")
func clampsCachedInputToRawInput() throws {
    let overreportedCache = #"{"timestamp":"2026-05-04T08:35:59.868Z","type":"event_msg","payload":{"type":"token_count","info":{"last_token_usage":{"input_tokens":100,"cached_input_tokens":150,"output_tokens":1,"total_tokens":101}}}}"#
    let (file, cleanup) = try makeJsonlFile([
        sessionMeta,
        turnContextGpt5,
        overreportedCache,
    ])
    defer { cleanup() }

    let entry = try #require(CodexRolloutParser().parseFile(file).first)
    #expect(entry.usage.inputTokens == 0)
    #expect(entry.usage.cacheReadInputTokens == 100)
    #expect(entry.usage.inputTokens + entry.usage.cacheReadInputTokens == 100)
    let cost = PricingEngine().calculateCost(
        usage: entry.usage,
        model: "gpt-5",
        semantics: .codex
    ).cost
    #expect(abs(cost - 0.0000225) < 1e-9)
}
```

- [ ] **Step 5: 运行 CodexRolloutParserTests 并确认 RED**

Run:

```bash
xcodebuild -project TokenWatch.xcodeproj -scheme TokenWatch \
  -destination 'platform=macOS' \
  -only-testing:TokenWatchTests/CodexRolloutParserTests \
  -skip-testing:TokenWatchUITests \
  -derivedDataPath .build/DerivedData CODE_SIGN_STYLE=Manual DEVELOPMENT_TEAM= CODE_SIGN_IDENTITY=- test
```

Expected: 旧 parser 的无模型测试返回空数组；编译同时报告 `pricingSpeed:` 参数不存在。补齐 speed seam 后，cached clamp 回归仍会读到 `cacheReadInputTokens == 150`。

- [ ] **Step 6: 把 resolver 与 speed 接入 parser cache**

在 `CodexRolloutParser` 中应用以下精确替换：

```swift
private struct CachedFile {
    let signature: FileSignature
    let pricingSpeed: CodexPricingSpeed
    let entries: [ParsedUsageEntry]
}

func parseFile(
    _ fileInfo: CodexRolloutFileInfo,
    pricingSpeed: CodexPricingSpeed = .standard
) throws -> [ParsedUsageEntry] {
    let handle = try FileHandle(forReadingFrom: fileInfo.url)
    defer { try? handle.close() }

    let decoder = JSONDecoder()
    let newline: UInt8 = 0x0A
    var entries: [ParsedUsageEntry] = []
    var currentModel: CodexModelState?
    var sessionCwd: String?
    var sessionID = fileInfo.sessionID
    var previousTotals = CodexTokenCounts.zero
    var buffer = Data()
    let chunkSize = 64 * 1024

    let processLine: (Data) -> Void = { lineData in
        guard !lineData.isEmpty,
              let record = try? decoder.decode(CodexRecord.self, from: lineData) else {
            return
        }
        switch record.payload {
        case .sessionMeta(let meta):
            sessionID = meta.id
            sessionCwd = meta.cwd

        case .turnContext(let context):
            if let model = context.model {
                _ = CodexModelResolver.resolve(
                    parsedModel: model,
                    eventDate: record.timestamp,
                    current: &currentModel
                )
            }

        case .eventMsg(let event):
            guard event.type == "token_count", let info = event.info else { return }
            let delta: CodexTokenCounts
            if let last = info.lastTokenUsage {
                delta = last
            } else if let total = info.totalTokenUsage {
                delta = CodexTokenCounts(
                    inputTokens: max(0, total.inputTokens - previousTotals.inputTokens),
                    cachedInputTokens: max(0, total.cachedInputTokens - previousTotals.cachedInputTokens),
                    outputTokens: max(0, total.outputTokens - previousTotals.outputTokens),
                    reasoningOutputTokens: max(
                        0,
                        total.reasoningOutputTokens - previousTotals.reasoningOutputTokens
                    ),
                    totalTokens: max(0, total.totalTokens - previousTotals.totalTokens)
                )
            } else {
                return
            }
            if let total = info.totalTokenUsage {
                previousTotals = total
            }
            guard !delta.isAllZero else { return }

            let model = CodexModelResolver.resolve(
                parsedModel: event.model ?? info.model,
                eventDate: record.timestamp,
                current: &currentModel
            )
            let rawInput = max(0, delta.inputTokens)
            // ccusage 先将 cached_input_tokens 夹到 raw input，再拆 pure/cached。
            let cachedInput = min(max(0, delta.cachedInputTokens), rawInput)
            let pureInput = rawInput - cachedInput
            let usage = TokenUsage(
                inputTokens: pureInput,
                cacheCreationInputTokens: 0,
                cacheReadInputTokens: cachedInput,
                outputTokens: delta.outputTokens,
                serverToolUse: ServerToolUse(webSearchRequests: 0, webFetchRequests: 0),
                serviceTier: pricingSpeed == .fast ? "fast" : "",
                cacheCreation: nil,
                inferenceGeo: "",
                iterations: [],
                speed: ""
            )
            let timestampKey = record.timestamp.map(Self.iso8601Key)
                ?? "no-ts-\(UUID().uuidString)"
            let messageID = "\(sessionID):\(timestampKey)"
            entries.append(ParsedUsageEntry(
                recordUUID: messageID,
                messageId: messageID,
                requestId: nil,
                sessionID: sessionID,
                timestamp: record.timestamp,
                model: model,
                cwd: sessionCwd,
                agentId: nil,
                usage: usage,
                isSubagent: false,
                provider: .codex,
                upstreamProviderID: nil,
                upstreamCost: nil
            ))

        case .unknown:
            return
        }
    }

    while true {
        let chunk = try handle.read(upToCount: chunkSize) ?? Data()
        if chunk.isEmpty { break }
        buffer.append(chunk)
        var searchStart = buffer.startIndex
        while let newlineIndex = buffer[searchStart...].firstIndex(of: newline) {
            processLine(Data(buffer[searchStart..<newlineIndex]))
            searchStart = buffer.index(after: newlineIndex)
        }
        if searchStart > buffer.startIndex {
            buffer.removeSubrange(buffer.startIndex..<searchStart)
        }
    }
    if !buffer.isEmpty { processLine(buffer) }
    return entries
}
```

把批量与 cache 方法签名替换为：

```swift
func parseAllFiles(
    _ files: [CodexRolloutFileInfo],
    pricingSpeed: CodexPricingSpeed = .standard
) throws -> [ParsedUsageEntry] {
    var all: [ParsedUsageEntry] = []
    var currentCacheKeys: Set<String> = []
    for file in files {
        let key = Self.cacheKey(for: file.url)
        currentCacheKeys.insert(key)
        do {
            all.append(contentsOf: try parseCachedFile(
                file,
                cacheKey: key,
                pricingSpeed: pricingSpeed
            ))
        } catch {
            logger.warning("Codex 文件解析失败: \(file.url.lastPathComponent) — \(error.localizedDescription)")
        }
    }
    pruneCache(keeping: currentCacheKeys)
    var bestByKey: [String: ParsedUsageEntry] = [:]
    for entry in all {
        if let existing = bestByKey[entry.dedupKey] {
            if Self.magnitude(entry.usage) > Self.magnitude(existing.usage) {
                bestByKey[entry.dedupKey] = entry
            }
        } else {
            bestByKey[entry.dedupKey] = entry
        }
    }
    return Array(bestByKey.values)
}

private func parseCachedFile(
    _ fileInfo: CodexRolloutFileInfo,
    cacheKey: String,
    pricingSpeed: CodexPricingSpeed
) throws -> [ParsedUsageEntry] {
    let signature = try FileSignature(url: fileInfo.url)
    if let cached = cachedFile(
        for: cacheKey,
        matching: signature,
        pricingSpeed: pricingSpeed
    ) {
        return cached
    }
    let entries = try parseFile(fileInfo, pricingSpeed: pricingSpeed)
    withCacheLock {
        cachedFiles[cacheKey] = CachedFile(
            signature: signature,
            pricingSpeed: pricingSpeed,
            entries: entries
        )
    }
    return entries
}

private func cachedFile(
    for cacheKey: String,
    matching signature: FileSignature,
    pricingSpeed: CodexPricingSpeed
) -> [ParsedUsageEntry]? {
    withCacheLock {
        guard let cached = cachedFiles[cacheKey],
              cached.signature == signature,
              cached.pricingSpeed == pricingSpeed else { return nil }
        cacheHitCount += 1
        return cached.entries
    }
}
```

在 `CodexProvider.swift` 保留现有 metadata 属性，替换依赖与 `loadEntries`：

```swift
private let scanner: CodexRolloutScanner
private let parser: CodexRolloutParser
private let serviceTierResolver: CodexServiceTierResolver

init(
    scanner: CodexRolloutScanner = CodexRolloutScanner(),
    parser: CodexRolloutParser = CodexRolloutParser(),
    serviceTierResolver: CodexServiceTierResolver = CodexServiceTierResolver()
) {
    self.scanner = scanner
    self.parser = parser
    self.serviceTierResolver = serviceTierResolver
}

func loadEntries(from rootURL: URL) throws -> [ParsedUsageEntry] {
    let codexRoot = rootURL.appendingPathComponent(".codex", isDirectory: true)
    let files = try scanner.scanAll(in: codexRoot)
    let speed = serviceTierResolver.pricingSpeed(at: codexRoot)
    return try parser.parseAllFiles(files, pricingSpeed: speed)
}
```

- [ ] **Step 7: 运行全部 Codex 定向测试并确认 GREEN**

Run:

```bash
xcodebuild -project TokenWatch.xcodeproj -scheme TokenWatch \
  -destination 'platform=macOS' \
  -only-testing:TokenWatchTests/CodexServiceTierResolverTests \
  -only-testing:TokenWatchTests/CodexModelResolverTests \
  -only-testing:TokenWatchTests/CodexRecordTests \
  -only-testing:TokenWatchTests/CodexRolloutParserTests \
  -skip-testing:TokenWatchUITests \
  -derivedDataPath .build/DerivedData CODE_SIGN_STYLE=Manual DEVELOPMENT_TEAM= CODE_SIGN_IDENTITY=- test
```

Expected: 四个 suite 全部通过；只有 table header 之前的顶层 `service_tier` 能启用 fast，`[table]` / `[[array-of-tables]]` 内同名键保持 standard；无模型事件产出 `gpt-5`，真实模型覆盖 fallback，speed 改变不命中旧 cache，`raw=100 / cached=150` 被归一化为 `pure=0 / cached=100` 且本地成本为 `$0.0000225`。

- [ ] **Step 8: 提交 Codex speed 与 fallback**

```bash
git add TokenWatch/Providers/Codex/CodexServiceTierResolver.swift \
  TokenWatch/Providers/Codex/CodexModelResolver.swift \
  TokenWatch/Providers/Codex/CodexRecord.swift \
  TokenWatch/Providers/Codex/CodexRolloutParser.swift \
  TokenWatch/Providers/Codex/CodexProvider.swift \
  TokenWatchTests/Providers/Codex/CodexServiceTierResolverTests.swift \
  TokenWatchTests/Providers/Codex/CodexModelResolverTests.swift \
  TokenWatchTests/Providers/Codex/CodexRecordTests.swift \
  TokenWatchTests/Providers/Codex/CodexRolloutParserTests.swift
git commit -m "feat(codex): 对齐模型、fast 与缓存边界"
```

---

### Task 6: ccusage v20.0.16 固定金额契约与阶段验收

**Files:**
- Create: `TokenWatchTests/Pricing/CCUsagePricingParityTests.swift`
- Create: `TokenWatchTests/Fixtures/Pricing/ccusage-v20.0.16.json`

**Interfaces:**
- Consumes: `UsageCostResolver`、`ProviderID`、最终 `TokenUsage`、固定 bundled `PricingTable.shared`。
- Produces: 不联网的表驱动金额契约；fixture 中 Codex `inputTokens` 表示 raw input，test adapter 先夹住 cached 再转成 `pure input = raw - cached`；OpenCode `sourceTotalTokens` 通过同一 missing-token 公式并入 output。

- [ ] **Step 1: 写读取完整 fixture 的失败测试**

创建 `TokenWatchTests/Pricing/CCUsagePricingParityTests.swift`：

```swift
import Foundation
import Testing
@testable import TokenWatch

@Suite("ccusage v20.0.16 Pricing Parity")
struct CCUsagePricingParityTests {
    private struct Fixture: Decodable {
        let baseline: Baseline
        let cases: [Case]
    }

    private struct Baseline: Decodable {
        let ccusageVersion: String
        let ccusageCommit: String
        let costMode: String
        let offline: Bool
        let liteLLMRevision: String
        let liteLLMSourceSHA256: String
        let modelsDevSourceSHA256: String
        let fastOverridesSHA256: String
        let autoReviewFallbacksSHA256: String
    }

    private struct Case: Decodable {
        let name: String
        let provider: ProviderID
        let model: String
        let sourceUpstreamCost: Double?
        let upstreamProviderID: String?
        let usage: Usage
        let expectedUSD: Double
    }

    private struct Usage: Decodable {
        let inputTokens: Int
        let cachedInputTokens: Int?
        let outputTokens: Int
        let sourceTotalTokens: Int?
        let cacheReadTokens: Int?
        let cacheCreate5mTokens: Int?
        let cacheCreate1hTokens: Int?
        let speed: String?
        let serviceTier: String?
    }

    @Test("固定 fixture 全部金额与 ccusage offline Auto 一致")
    func fixedAmounts() throws {
        let fixture = try loadFixture()
        #expect(fixture.baseline.ccusageVersion == "v20.0.16")
        #expect(fixture.baseline.ccusageCommit == "e32cc4820df1e13f4399560e03f3858869738dc8")
        #expect(fixture.baseline.costMode == "auto")
        #expect(fixture.baseline.offline)
        #expect(fixture.baseline.liteLLMRevision == "49ca04d8c3ddea336237ce6f3082dbc26d19e944")
        #expect(fixture.baseline.liteLLMSourceSHA256 == "ae4532ba0c5da03ed694f37fffa050a65e0e250b816dcdb475bee0b7b7b1aa97")
        #expect(fixture.baseline.modelsDevSourceSHA256 == "5d61cc3148100cd670d3289033b5e2fb05c4244cbe32f92888ef7bd2df1abf67")
        #expect(fixture.baseline.fastOverridesSHA256 == "647b3ae8e44349455f32ce9f4633910b5151b08cda1707601a97701927490762")
        #expect(fixture.baseline.autoReviewFallbacksSHA256 == "344d2438312beed608c19e616031d1b194f3c6efdfcbd0925f39f4df9008c037")
        #expect(fixture.cases.count == 21)
        #expect(Set(fixture.cases.map(\.name)).count == fixture.cases.count)

        let resolver = UsageCostResolver()
        for testCase in fixture.cases {
            let actual = resolver.resolvedCost(for: entry(from: testCase))
            #expect(
                abs(actual - testCase.expectedUSD) < 1e-9,
                Comment("\(testCase.name): actual=\(actual), expected=\(testCase.expectedUSD)")
            )
        }
    }

    private func loadFixture() throws -> Fixture {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Fixtures/Pricing/ccusage-v20.0.16.json")
        return try JSONDecoder().decode(Fixture.self, from: Data(contentsOf: url))
    }

    private func entry(from testCase: Case) -> ParsedUsageEntry {
        let rawInput = max(0, testCase.usage.inputTokens)
        let reportedCached = max(0, testCase.usage.cachedInputTokens ?? 0)
        let cached = testCase.provider == .codex
            ? min(reportedCached, rawInput)
            : reportedCached
        let input = testCase.provider == .codex
            ? rawInput - cached
            : rawInput
        let cacheRead = testCase.usage.cacheReadTokens ?? cached
        let cacheCreate5m = testCase.usage.cacheCreate5mTokens ?? 0
        let cacheCreate1h = testCase.usage.cacheCreate1hTokens ?? 0
        let sourceOutput = max(0, testCase.usage.outputTokens)
        let totalFallback: Int
        if testCase.provider == .opencode,
           let sourceTotal = testCase.usage.sourceTotalTokens {
            let known = input + sourceOutput + cacheRead + cacheCreate5m + cacheCreate1h
            totalFallback = max(sourceTotal - known, 0)
        } else {
            totalFallback = 0
        }
        let billableOutput = sourceOutput + totalFallback
        let upstream: Double?
        if testCase.provider == .opencode {
            upstream = testCase.sourceUpstreamCost.flatMap { $0 > 0 ? $0 : nil }
        } else {
            upstream = testCase.sourceUpstreamCost
        }
        return ParsedUsageEntry(
            recordUUID: testCase.name,
            messageId: testCase.name,
            requestId: nil,
            sessionID: "fixture",
            timestamp: Date(timeIntervalSince1970: 0),
            model: testCase.model,
            cwd: "/fixture",
            agentId: nil,
            usage: TokenUsage(
                inputTokens: input,
                cacheCreationInputTokens: 0,
                cacheReadInputTokens: cacheRead,
                outputTokens: billableOutput,
                serverToolUse: ServerToolUse(webSearchRequests: 0, webFetchRequests: 0),
                serviceTier: testCase.usage.serviceTier ?? "",
                cacheCreation: testCase.provider == .claude
                    ? CacheCreation(
                        ephemeral1hInputTokens: cacheCreate1h,
                        ephemeral5mInputTokens: cacheCreate5m
                    )
                    : nil,
                inferenceGeo: "",
                iterations: [],
                speed: testCase.usage.speed ?? ""
            ),
            isSubagent: false,
            provider: testCase.provider,
            upstreamProviderID: testCase.provider == .opencode
                ? (testCase.upstreamProviderID ?? "fixture")
                : nil,
            upstreamCost: upstream
        )
    }
}
```

- [ ] **Step 2: 运行 parity suite 并确认 RED**

Run:

```bash
xcodebuild -project TokenWatch.xcodeproj -scheme TokenWatch \
  -destination 'platform=macOS' \
  -only-testing:TokenWatchTests/CCUsagePricingParityTests \
  -skip-testing:TokenWatchUITests \
  -derivedDataPath .build/DerivedData CODE_SIGN_STYLE=Manual DEVELOPMENT_TEAM= CODE_SIGN_IDENTITY=- test
```

Expected: 测试运行后因 `TokenWatchTests/Fixtures/Pricing/ccusage-v20.0.16.json` 不存在而失败。

- [ ] **Step 3: 添加完整固定金额 fixture**

创建 `TokenWatchTests/Fixtures/Pricing/ccusage-v20.0.16.json`：

```json
{
  "baseline": {
    "ccusageVersion": "v20.0.16",
    "ccusageCommit": "e32cc4820df1e13f4399560e03f3858869738dc8",
    "costMode": "auto",
    "offline": true,
    "liteLLMRevision": "49ca04d8c3ddea336237ce6f3082dbc26d19e944",
    "liteLLMSourceSHA256": "ae4532ba0c5da03ed694f37fffa050a65e0e250b816dcdb475bee0b7b7b1aa97",
    "modelsDevSourceSHA256": "5d61cc3148100cd670d3289033b5e2fb05c4244cbe32f92888ef7bd2df1abf67",
    "fastOverridesSHA256": "647b3ae8e44349455f32ce9f4633910b5151b08cda1707601a97701927490762",
    "autoReviewFallbacksSHA256": "344d2438312beed608c19e616031d1b194f3c6efdfcbd0925f39f4df9008c037"
  },
  "cases": [
    {"name":"sonnet-45-input-250k","provider":"claude","model":"claude-sonnet-4-5","usage":{"inputTokens":250000,"outputTokens":0},"expectedUSD":0.9},
    {"name":"sonnet-45-independent-tiers","provider":"claude","model":"claude-sonnet-4-5","usage":{"inputTokens":100000,"outputTokens":300000},"expectedUSD":5.55},
    {"name":"sonnet-45-cache-breakdown","provider":"claude","model":"claude-sonnet-4-5","usage":{"inputTokens":0,"outputTokens":0,"cacheReadTokens":30,"cacheCreate5mTokens":10,"cacheCreate1hTokens":20},"expectedUSD":0.0001665},
    {"name":"opus-48-fast","provider":"claude","model":"claude-opus-4-8","usage":{"inputTokens":1000000,"outputTokens":1000000,"speed":"fast"},"expectedUSD":60.0},
    {"name":"gpt-5-mini","provider":"codex","model":"gpt-5-mini","usage":{"inputTokens":1000000,"cachedInputTokens":0,"outputTokens":1000000},"expectedUSD":2.25},
    {"name":"gpt-5-nano","provider":"codex","model":"gpt-5-nano","usage":{"inputTokens":1000000,"cachedInputTokens":0,"outputTokens":1000000},"expectedUSD":0.45},
    {"name":"gpt-54-long-context","provider":"codex","model":"gpt-5.4","usage":{"inputTokens":300000,"cachedInputTokens":100000,"outputTokens":1000},"expectedUSD":1.0725},
    {"name":"gpt-55-long-context","provider":"codex","model":"gpt-5.5","usage":{"inputTokens":300000,"cachedInputTokens":100000,"outputTokens":1000},"expectedUSD":2.145},
    {"name":"gpt-56-sol-long-context","provider":"codex","model":"gpt-5.6-sol","usage":{"inputTokens":300000,"cachedInputTokens":100000,"outputTokens":1000},"expectedUSD":2.145},
    {"name":"gpt-54-fast","provider":"codex","model":"gpt-5.4","usage":{"inputTokens":100000,"cachedInputTokens":40000,"outputTokens":1000,"serviceTier":"fast"},"expectedUSD":0.35},
    {"name":"gpt-55-fast","provider":"codex","model":"gpt-5.5","usage":{"inputTokens":100000,"cachedInputTokens":40000,"outputTokens":1000,"serviceTier":"fast"},"expectedUSD":0.875},
    {"name":"claude-35-haiku-history","provider":"claude","model":"claude-3-5-haiku-20241022","usage":{"inputTokens":1000000,"outputTokens":1000000},"expectedUSD":4.8},
    {"name":"gpt-53-spark-alias","provider":"codex","model":"gpt-5.3-spark","usage":{"inputTokens":1000000,"cachedInputTokens":0,"outputTokens":1000000},"expectedUSD":15.75},
    {"name":"claude-known-upstream","provider":"claude","model":"claude-sonnet-4-5","sourceUpstreamCost":0.123,"usage":{"inputTokens":1,"outputTokens":1},"expectedUSD":0.123},
    {"name":"claude-known-upstream-zero","provider":"claude","model":"claude-sonnet-4-5","sourceUpstreamCost":0,"usage":{"inputTokens":1000000,"outputTokens":1000000},"expectedUSD":0},
    {"name":"claude-unknown-upstream","provider":"claude","model":"private-unknown","sourceUpstreamCost":0.123,"usage":{"inputTokens":1,"outputTokens":1},"expectedUSD":0.123},
    {"name":"claude-unknown-no-upstream","provider":"claude","model":"private-unknown","usage":{"inputTokens":1000,"outputTokens":100},"expectedUSD":0},
    {"name":"opencode-zero-recalculates","provider":"opencode","model":"claude-sonnet-4-5","sourceUpstreamCost":0,"usage":{"inputTokens":1000,"outputTokens":100},"expectedUSD":0.0045},
    {"name":"opencode-k2p6-alias","provider":"opencode","model":"kimi-for-coding/k2p6","upstreamProviderID":"kimi-for-coding","usage":{"inputTokens":1000000,"outputTokens":1000000},"expectedUSD":4.95},
    {"name":"opencode-total-only-fallback","provider":"opencode","model":"anthropic/claude-sonnet-4-5","upstreamProviderID":"anthropic","usage":{"inputTokens":0,"outputTokens":0,"sourceTotalTokens":1000},"expectedUSD":0.015},
    {"name":"codex-gpt4-implicit-cache","provider":"codex","model":"gpt-4","usage":{"inputTokens":1000,"cachedInputTokens":400,"outputTokens":0},"expectedUSD":0.03}
  ]
}
```

- [ ] **Step 4: 运行 parity、所有相关定向 suite 与编译验收**

Run:

```bash
xcodebuild -project TokenWatch.xcodeproj -scheme TokenWatch \
  -destination 'platform=macOS' \
  -only-testing:TokenWatchTests/PricingTableTests \
  -only-testing:TokenWatchTests/PricingEngineTests \
  -only-testing:TokenWatchTests/CCUsagePricingParityTests \
  -only-testing:TokenWatchTests/UsageCostResolverTests \
  -only-testing:TokenWatchTests/UsageAggregatorTests \
  -only-testing:TokenWatchTests/ClaudeJSONLParserTests \
  -only-testing:TokenWatchTests/OpenCodeMessageParserTests \
  -only-testing:TokenWatchTests/CodexServiceTierResolverTests \
  -only-testing:TokenWatchTests/CodexModelResolverTests \
  -only-testing:TokenWatchTests/CodexRecordTests \
  -only-testing:TokenWatchTests/CodexRolloutParserTests \
  -skip-testing:TokenWatchUITests \
  -derivedDataPath .build/DerivedData CODE_SIGN_STYLE=Manual DEVELOPMENT_TEAM= CODE_SIGN_IDENTITY=- test
```

Expected: 所有列出的 suite 通过；21 个 fixture case 均在 `1e-9` 内，OpenCode total-only 用例得到 `$0.015`。

Run:

```bash
xcodebuild -project TokenWatch.xcodeproj -scheme TokenWatch \
  -destination 'platform=macOS' \
  -skip-testing:TokenWatchUITests \
  -derivedDataPath .build/DerivedData CODE_SIGN_STYLE=Manual DEVELOPMENT_TEAM= CODE_SIGN_IDENTITY=- build-for-testing
```

Expected: `** TEST BUILD SUCCEEDED **`。

- [ ] **Step 5: 提交固定金额契约**

```bash
git add TokenWatchTests/Pricing/CCUsagePricingParityTests.swift \
  TokenWatchTests/Fixtures/Pricing/ccusage-v20.0.16.json
git commit -m "test(pricing): 锁定 ccusage 离线金额契约"
```

---

## 顺序依赖与后续阶段交接

1. Task 1 → Task 2：查价表依赖 catalog 的 explicit metadata，不能并行落地。
2. **跨计划硬门禁：Task 2 → Provider 数据正确性计划 Task 1。** Task 2 GREEN 后暂停本计划，只执行 Provider Task 1；该 Task 把 `TokenUsage.cacheCreation` 改成 `CacheCreation?`、更新当时已经存在的扁平 fixture，并通过自己的定向测试。此时不得执行 Provider Task 2。
3. **回到本计划：Provider Task 1 → Task 3。** 只有 optional initializer 已存在，Task 3 才能首次加入 `cacheCreation: nil`；long-context rates 与 fast multiplier 也已由 Task 1–2 进入 `ModelPricing`。
4. Task 3 → Task 4：`UsageCostResolver` 依赖新的 `PricingSemantics` overload。
5. Task 3 → Task 5：Codex parser 传播的 `serviceTier` 由 engine 的 `.codex` 分支消费。
6. Task 1–5 → Task 6：金额 fixture 是阶段验收，不替代各任务先前的 RED 回归测试；Task 6 创建 fixture helper 时直接使用 Provider Task 1 已存在的 optional 形状，Claude 构造 breakdown，Codex/OpenCode 传 `nil`。
7. **完成本计划 Task 6 与本文件“阶段完成验证”后，才能回到 Provider 数据正确性计划 Task 2，并顺序执行其 Task 2–7。** 这就是两个计划的唯一交错点，不能解释为“先完整执行任意一个计划”。
8. 后续 Provider Task 3 会给 `ParsedUsageEntry` 增加 `isSidechain`；只需更新本计划新增 fixture helper 的 initializer 参数，不能改变金额期望。
9. 后续增量解析阶段重写 Claude/Codex file cache 时，必须把 Claude `upstreamCost`、Codex `CodexModelState`、pricing speed 与 previous totals 一并纳入可恢复状态；不能退回最终 entry-only cache。
10. 当前 `PricingEngineTests` 的 DeepSeek 产品手写价、`UsageAggregatorTests` 的 known-model local-first、`CodexRolloutParserTests` 的 missing-model skip 都是旧契约，必须按各任务明确替换，不能同时保留互相矛盾的断言。

## 阶段完成验证

- [ ] 运行完整 unit target，避免定向 suite 遮蔽 initializer 或 fixture 回归：

```bash
xcodebuild -project TokenWatch.xcodeproj -scheme TokenWatch -destination 'platform=macOS' \
  -only-testing:TokenWatchTests -skip-testing:TokenWatchUITests \
  -derivedDataPath .build/DerivedData CODE_SIGN_STYLE=Manual DEVELOPMENT_TEAM= CODE_SIGN_IDENTITY=- test
```

- [ ] 构建 Debug、Release、Universal，并运行静态分析：

```bash
xcodebuild -project TokenWatch.xcodeproj -scheme TokenWatch -configuration Debug -derivedDataPath .build/DerivedData CODE_SIGNING_ALLOWED=NO build
xcodebuild -project TokenWatch.xcodeproj -scheme TokenWatch -configuration Release -derivedDataPath .build/DerivedData CODE_SIGNING_ALLOWED=NO build
xcodebuild -project TokenWatch.xcodeproj -scheme TokenWatch -configuration Release ARCHS='arm64 x86_64' ONLY_ACTIVE_ARCH=NO -derivedDataPath .build/DerivedData-Universal CODE_SIGNING_ALLOWED=NO build
xcodebuild -project TokenWatch.xcodeproj -scheme TokenWatch -configuration Debug -destination 'platform=macOS' -derivedDataPath .build/DerivedData CODE_SIGNING_ALLOWED=NO analyze
```

- [ ] 确认 fixture 为 21 个唯一 case，四个 source SHA 与 baseline metadata 一致，然后做范围检查：

```bash
jq '.cases | {count:length, unique:(map(.name) | unique | length)}' TokenWatchTests/Fixtures/Pricing/ccusage-v20.0.16.json
git status --short
git diff --check
```

Expected: unit tests、四条 build/analyze 全部成功；fixture 输出 `count=21, unique=21`；差异仅包含本计划列出的定价、provider 与测试文件，`git diff --check` 无输出。
