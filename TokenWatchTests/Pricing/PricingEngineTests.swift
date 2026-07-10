import Foundation
import Testing
@testable import TokenWatch

/// 定价引擎测试
/// 验证 ccusage 成本计算公式的正确性
struct PricingEngineTests {

    let engine = PricingEngine()

    // MARK: - 成本计算

    @Test("基础成本计算 - claude-sonnet-4")
    func basicCostCalculation() {
        let usage = TokenUsage(
            inputTokens: 1_000_000,
            cacheCreationInputTokens: 0,
            cacheReadInputTokens: 0,
            outputTokens: 1_000_000,
            serverToolUse: ServerToolUse(webSearchRequests: 0, webFetchRequests: 0),
            serviceTier: "standard",
            cacheCreation: CacheCreation(ephemeral1hInputTokens: 0, ephemeral5mInputTokens: 0),
            inferenceGeo: "",
            iterations: [],
            speed: "standard"
        )

        let pricing = ModelPricing(
            modelID: "claude-sonnet-4",
            displayName: "Claude Sonnet 4",
            inputPrice: 3.0, outputPrice: 15.0,
            cacheReadPrice: 0.30, cacheWritePrice: 3.75
        )

        let cost = engine.calculateCost(usage: usage, pricing: pricing)

        // input: 1M * $3/1M = $3
        // output: 1M * $15/1M = $15
        // total: $18
        #expect(abs(cost - 18.0) < 0.001)
    }

    @Test("缓存读取成本计算")
    func cacheReadCost() {
        let usage = TokenUsage(
            inputTokens: 100_000,
            cacheCreationInputTokens: 0,
            cacheReadInputTokens: 500_000,
            outputTokens: 10_000,
            serverToolUse: ServerToolUse(webSearchRequests: 0, webFetchRequests: 0),
            serviceTier: "standard",
            cacheCreation: CacheCreation(ephemeral1hInputTokens: 0, ephemeral5mInputTokens: 0),
            inferenceGeo: "",
            iterations: [],
            speed: "standard"
        )

        let pricing = ModelPricing(
            modelID: "claude-sonnet-4",
            displayName: "Claude Sonnet 4",
            inputPrice: 3.0, outputPrice: 15.0,
            cacheReadPrice: 0.30, cacheWritePrice: 3.75
        )

        let cost = engine.calculateCost(usage: usage, pricing: pricing)

        // input: 100K * $3/1M = $0.30
        // output: 10K * $15/1M = $0.15
        // cache read: 500K * $0.30/1M = $0.15
        // total: $0.60
        #expect(abs(cost - 0.60) < 0.001)
    }

    @Test("缓存写入成本计算 - 仅扁平字段（视为 5m）")
    func cacheWriteCostFlat() {
        let usage = TokenUsage(
            inputTokens: 100_000,
            cacheCreationInputTokens: 200_000,
            cacheReadInputTokens: 0,
            outputTokens: 10_000,
            serverToolUse: ServerToolUse(webSearchRequests: 0, webFetchRequests: 0),
            serviceTier: "standard",
            cacheCreation: nil,
            inferenceGeo: "",
            iterations: [],
            speed: "standard"
        )

        let pricing = ModelPricing(
            modelID: "claude-opus-4",
            displayName: "Claude Opus 4",
            inputPrice: 15.0, outputPrice: 75.0,
            cacheReadPrice: 1.50, cacheWritePrice: 18.75
        )

        let cost = engine.calculateCost(usage: usage, pricing: pricing)

        // input: 100K * $15/1M = $1.50
        // output: 10K * $75/1M = $0.75
        // 无 ephemeral 细分 → 200K 视为 5m → 200K * $18.75/1M = $3.75
        // total: $6.00
        #expect(abs(cost - 6.00) < 0.001)
    }

    @Test("5m / 1h 缓存写入价格区分（1h = inputPrice × 2）")
    func cacheWriteSplit5mAnd1h() {
        // 当存在 ephemeral 细分时，扁平字段 cacheCreationInputTokens 应被忽略（避免 double count）
        let usage = TokenUsage(
            inputTokens: 0,
            cacheCreationInputTokens: 999_999,        // 故意设大值，验证不会被双计
            cacheReadInputTokens: 0,
            outputTokens: 0,
            serverToolUse: ServerToolUse(webSearchRequests: 0, webFetchRequests: 0),
            serviceTier: "standard",
            cacheCreation: CacheCreation(
                ephemeral1hInputTokens: 1_000_000,
                ephemeral5mInputTokens: 1_000_000
            ),
            inferenceGeo: "",
            iterations: [],
            speed: "standard"
        )
        let pricing = ModelPricing(
            modelID: "claude-sonnet-4",
            displayName: "Claude Sonnet 4",
            inputPrice: 3.0, outputPrice: 15.0,
            cacheReadPrice: 0.30, cacheWritePrice: 3.75
        )
        let cost = engine.calculateCost(usage: usage, pricing: pricing)
        // 5m: 1M * $3.75/1M  = $3.75
        // 1h: 1M * (3.0×2)/1M = $6.00
        // total: $9.75（999_999 不参与）
        #expect(abs(cost - 9.75) < 0.001)
    }

    @Test("零用量成本为 0")
    func zeroUsageCost() {
        let usage = TokenUsage(
            inputTokens: 0,
            cacheCreationInputTokens: 0,
            cacheReadInputTokens: 0,
            outputTokens: 0,
            serverToolUse: ServerToolUse(webSearchRequests: 0, webFetchRequests: 0),
            serviceTier: "standard",
            cacheCreation: CacheCreation(ephemeral1hInputTokens: 0, ephemeral5mInputTokens: 0),
            inferenceGeo: "",
            iterations: [],
            speed: "standard"
        )

        let pricing = ModelPricing(
            modelID: "claude-opus-4",
            displayName: "Claude Opus 4",
            inputPrice: 15.0, outputPrice: 75.0,
            cacheReadPrice: 1.50, cacheWritePrice: 18.75
        )

        let cost = engine.calculateCost(usage: usage, pricing: pricing)
        #expect(cost == 0.0)
    }

    // MARK: - 定价表查找

    @Test("精确匹配 - glm-5.1 (ccusage builtin 价位)")
    func exactGLM51Match() {
        let pricing = PricingTable.pricing(for: "glm-5.1")
        #expect(pricing != nil)
        #expect(abs((pricing?.inputPrice ?? 0) - 1.4) < 1e-9)
        #expect(abs((pricing?.outputPrice ?? 0) - 4.4) < 1e-9)
        #expect(abs((pricing?.cacheReadPrice ?? 0) - 0.26) < 1e-9)
    }

    @Test("primary exact 胜过 builtin 日期前缀模糊匹配")
    func primaryExactBeforeBuiltinDateFuzzy() {
        // filtered LiteLLM 含 exact 日期条目，因此应优先于 builtin 短名。
        let pricing = PricingTable.pricing(for: "claude-opus-4-20250514")
        #expect(pricing != nil)
        #expect(pricing?.modelID == "claude-opus-4-20250514")
    }

    @Test("版本号守卫 - sonnet-4-5-20250514 不应误命中 sonnet-4")
    func versionGuardSonnet45() {
        // 关键回归：候选 "claude-sonnet-4" 与 "claude-sonnet-4-5" 都是输入前缀,
        // 必须命中 4-5 而不是 4
        let pricing = PricingTable.pricing(for: "claude-sonnet-4-5-20250514")
        #expect(pricing?.modelID == "claude-sonnet-4-5")
    }

    @Test("版本号守卫 - opus-4-1-... 应命中 4-1 而不是 4")
    func versionGuardOpus41() {
        let pricing = PricingTable.pricing(for: "claude-opus-4-1-20250830")
        #expect(pricing?.modelID == "claude-opus-4-1")
    }

    @Test("版本号守卫 - opus-4-5 即便 4-5 不在表中也不应命中 4")
    func versionGuardBlocksWhenNoExactBaseline() {
        // 临时构造场景：当输入是 "claude-opus-4-9-..."（假设 4-9 不在表中），
        // 长度倒序仍会让 "claude-opus-4-5" 出现在前面被检查；其后缀 "-9-..." 是新版本号 → 跳过
        // "claude-opus-4-1" 也会被守卫拦下；"claude-opus-4" 同理。
        // 因此该未知版本应返回 nil 而非误算成 4 的价格。
        let pricing = PricingTable.pricing(for: "claude-opus-4-9-20990101")
        #expect(pricing == nil)
    }

    @Test("未知模型返回 nil")
    func unknownModelReturnsNil() {
        let pricing = PricingTable.pricing(for: "nonexistent-model-xyz")
        #expect(pricing == nil)
    }

    @Test("provider 前缀剥离 - opencode huoshan-zijie/glm-5.1 应命中 glm-5.1")
    func providerPrefixStrippingGLM() {
        // 回归:opencode 把上游 providerID 拼到 modelID 前(huoshan-zijie/GLM-5.1),
        // 整串既没精确命中也没前缀命中,需要剥掉 "{provider}/" 后用裸 modelID 再查一次,
        // 否则会落到 cost=0 的 fallback,与 ccusage 行为不一致
        let pricing = PricingTable.pricing(for: "huoshan-zijie/GLM-5.1")
        #expect(pricing != nil)
        #expect(pricing?.inputPrice == 1.4)
        #expect(pricing?.outputPrice == 4.4)
    }

    @Test("provider 前缀剥离 - 任意未知 provider 前缀都应回退到裸 modelID")
    func providerPrefixStrippingArbitrary() {
        let pricing = PricingTable.pricing(for: "siliconflow/glm-5.1")
        #expect(pricing?.inputPrice == 1.4)
    }

    @Test("provider 前缀剥离 - 裸 modelID 也未知时仍返回 nil")
    func providerPrefixStrippingStillNil() {
        let pricing = PricingTable.pricing(for: "anyprovider/totally-unknown-model")
        #expect(pricing == nil)
    }

    @Test("模型查找 + 成本计算")
    func modelLookupAndCostCalculation() {
        let usage = TokenUsage(
            inputTokens: 1_000_000,
            cacheCreationInputTokens: 0,
            cacheReadInputTokens: 0,
            outputTokens: 1_000_000,
            serverToolUse: ServerToolUse(webSearchRequests: 0, webFetchRequests: 0),
            serviceTier: "standard",
            cacheCreation: CacheCreation(ephemeral1hInputTokens: 0, ephemeral5mInputTokens: 0),
            inferenceGeo: "",
            iterations: [],
            speed: "standard"
        )

        let (cost, pricing) = engine.calculateCost(usage: usage, model: "claude-haiku-4-5")
        #expect(pricing != nil)
        #expect(abs(cost - 6.0) < 0.001)  // $1 + $5 = $6
    }

    @Test("重复模型查找复用 PricingEngine 进程内缓存")
    func repeatedModelLookupUsesPricingCache() {
        let usage = TokenUsage(
            inputTokens: 1_000,
            cacheCreationInputTokens: 0,
            cacheReadInputTokens: 0,
            outputTokens: 500,
            serverToolUse: ServerToolUse(webSearchRequests: 0, webFetchRequests: 0),
            serviceTier: "standard",
            cacheCreation: CacheCreation(ephemeral1hInputTokens: 0, ephemeral5mInputTokens: 0),
            inferenceGeo: "",
            iterations: [],
            speed: "standard"
        )
        let engine = PricingEngine()

        #expect(engine.debugCachedPricingCount == 0)
        _ = engine.calculateCost(usage: usage, model: "Claude-Sonnet-4-5")
        #expect(engine.debugCachedPricingCount == 1)
        _ = engine.calculateCost(usage: usage, model: "claude-sonnet-4-5")
        #expect(engine.debugCachedPricingCount == 1)
    }

    // MARK: - 200k tier 阶梯定价
    //
    // 参考 ccusage `cost.rs::tiered_cost`：
    //   if let above, tokens > 200_000:
    //       cost = 200_000 × base + (tokens - 200_000) × above
    //   else:
    //       cost = tokens × base
    // 每个 token 类别（input / output / cache_read / cache_create_5m）独立判断阈值。
    // cache_create_1h 不读 LiteLLM 的 1h above 字段，而是 input_above × 2.0。
    // `above` 为 nil 时退化为单价（Opus / Haiku / Fable / 3.7 Sonnet 等无 tier 模型）。

    @Test("tiered - input 跨 200k 拆段计费 (claude-sonnet-4-5)")
    func tieredInputAboveThreshold() {
        // input 250k → 200k × $3 + 50k × $6 = $0.60 + $0.30 = $0.90
        let usage = TokenUsage(
            inputTokens: 250_000,
            cacheCreationInputTokens: 0,
            cacheReadInputTokens: 0,
            outputTokens: 0,
            serverToolUse: ServerToolUse(webSearchRequests: 0, webFetchRequests: 0),
            serviceTier: "standard",
            cacheCreation: CacheCreation(ephemeral1hInputTokens: 0, ephemeral5mInputTokens: 0),
            inferenceGeo: "",
            iterations: [],
            speed: "standard"
        )
        let pricing = ModelPricing(
            modelID: "claude-sonnet-4-5",
            displayName: "Claude Sonnet 4.5",
            inputPrice: 3.0, outputPrice: 15.0,
            cacheReadPrice: 0.30, cacheWritePrice: 3.75,
            inputPriceAbove200k: 6.0,
            outputPriceAbove200k: 22.5,
            cacheReadPriceAbove200k: 0.60,
            cacheWritePriceAbove200k: 7.50
        )
        let cost = PricingEngine().calculateCost(usage: usage, pricing: pricing)
        #expect(abs(cost - 0.90) < 0.0001)
    }

    @Test("tiered - 恰好 200k 不进入 above 价")
    func tieredAtExactThreshold() {
        // input 200_000 → 全部按 base：200k × $3 = $0.60
        let usage = TokenUsage(
            inputTokens: 200_000,
            cacheCreationInputTokens: 0,
            cacheReadInputTokens: 0,
            outputTokens: 0,
            serverToolUse: ServerToolUse(webSearchRequests: 0, webFetchRequests: 0),
            serviceTier: "standard",
            cacheCreation: CacheCreation(ephemeral1hInputTokens: 0, ephemeral5mInputTokens: 0),
            inferenceGeo: "",
            iterations: [],
            speed: "standard"
        )
        let pricing = ModelPricing(
            modelID: "claude-sonnet-4-5",
            displayName: "Claude Sonnet 4.5",
            inputPrice: 3.0, outputPrice: 15.0,
            cacheReadPrice: 0.30, cacheWritePrice: 3.75,
            inputPriceAbove200k: 6.0,
            outputPriceAbove200k: 22.5,
            cacheReadPriceAbove200k: 0.60,
            cacheWritePriceAbove200k: 7.50
        )
        let cost = PricingEngine().calculateCost(usage: usage, pricing: pricing)
        #expect(abs(cost - 0.60) < 0.0001)
    }

    @Test("tiered - 每类独立判断阈值 (output 跨, input 不跨)")
    func tieredCategoriesAreIndependent() {
        // input 100k (不跨) + output 300k (跨)
        // input:  100k × $3   = $0.30
        // output: 200k × $15 + 100k × $22.5 = $3.00 + $2.25 = $5.25
        // total: $5.55
        let usage = TokenUsage(
            inputTokens: 100_000,
            cacheCreationInputTokens: 0,
            cacheReadInputTokens: 0,
            outputTokens: 300_000,
            serverToolUse: ServerToolUse(webSearchRequests: 0, webFetchRequests: 0),
            serviceTier: "standard",
            cacheCreation: CacheCreation(ephemeral1hInputTokens: 0, ephemeral5mInputTokens: 0),
            inferenceGeo: "",
            iterations: [],
            speed: "standard"
        )
        let pricing = ModelPricing(
            modelID: "claude-sonnet-4-5",
            displayName: "Claude Sonnet 4.5",
            inputPrice: 3.0, outputPrice: 15.0,
            cacheReadPrice: 0.30, cacheWritePrice: 3.75,
            inputPriceAbove200k: 6.0,
            outputPriceAbove200k: 22.5,
            cacheReadPriceAbove200k: 0.60,
            cacheWritePriceAbove200k: 7.50
        )
        let cost = PricingEngine().calculateCost(usage: usage, pricing: pricing)
        #expect(abs(cost - 5.55) < 0.0001)
    }

    @Test("tiered - cache_read 与 cache_create_5m 也跨 200k")
    func tieredCacheCategories() {
        // cache_read 250k → 200k × $0.30 + 50k × $0.60 = $0.06 + $0.03 = $0.09
        // cache_create_5m 250k → 200k × $3.75 + 50k × $7.50 = $0.75 + $0.375 = $1.125
        // total: $1.215
        let usage = TokenUsage(
            inputTokens: 0,
            cacheCreationInputTokens: 250_000,           // 无 ephemeral 细分 → 视为 5m
            cacheReadInputTokens: 250_000,
            outputTokens: 0,
            serverToolUse: ServerToolUse(webSearchRequests: 0, webFetchRequests: 0),
            serviceTier: "standard",
            cacheCreation: nil,
            inferenceGeo: "",
            iterations: [],
            speed: "standard"
        )
        let pricing = ModelPricing(
            modelID: "claude-sonnet-4-5",
            displayName: "Claude Sonnet 4.5",
            inputPrice: 3.0, outputPrice: 15.0,
            cacheReadPrice: 0.30, cacheWritePrice: 3.75,
            inputPriceAbove200k: 6.0,
            outputPriceAbove200k: 22.5,
            cacheReadPriceAbove200k: 0.60,
            cacheWritePriceAbove200k: 7.50
        )
        let cost = PricingEngine().calculateCost(usage: usage, pricing: pricing)
        #expect(abs(cost - 1.215) < 0.0001)
    }

    @Test("tiered - cache_create_1h above = input_above × 2")
    func tieredCache1hUsesInputAboveTimesTwo() {
        // 1h cache 250k：base = $3 × 2 = $6，above = $6 × 2 = $12
        // 200k × $6 + 50k × $12 = $1.20 + $0.60 = $1.80
        let usage = TokenUsage(
            inputTokens: 0,
            cacheCreationInputTokens: 0,
            cacheReadInputTokens: 0,
            outputTokens: 0,
            serverToolUse: ServerToolUse(webSearchRequests: 0, webFetchRequests: 0),
            serviceTier: "standard",
            cacheCreation: CacheCreation(ephemeral1hInputTokens: 250_000, ephemeral5mInputTokens: 0),
            inferenceGeo: "",
            iterations: [],
            speed: "standard"
        )
        let pricing = ModelPricing(
            modelID: "claude-sonnet-4-5",
            displayName: "Claude Sonnet 4.5",
            inputPrice: 3.0, outputPrice: 15.0,
            cacheReadPrice: 0.30, cacheWritePrice: 3.75,
            inputPriceAbove200k: 6.0,
            outputPriceAbove200k: 22.5,
            cacheReadPriceAbove200k: 0.60,
            cacheWritePriceAbove200k: 7.50
        )
        let cost = PricingEngine().calculateCost(usage: usage, pricing: pricing)
        #expect(abs(cost - 1.80) < 0.0001)
    }

    @Test("tiered - above 价为 nil 时按 base 单价 (Opus 不分级)")
    func tieredFallsBackToBaseWhenAboveNil() {
        // Opus 没有 above_200k，input 1M 全部按 $15 → $15
        let usage = TokenUsage(
            inputTokens: 1_000_000,
            cacheCreationInputTokens: 0,
            cacheReadInputTokens: 0,
            outputTokens: 0,
            serverToolUse: ServerToolUse(webSearchRequests: 0, webFetchRequests: 0),
            serviceTier: "standard",
            cacheCreation: CacheCreation(ephemeral1hInputTokens: 0, ephemeral5mInputTokens: 0),
            inferenceGeo: "",
            iterations: [],
            speed: "standard"
        )
        let pricing = ModelPricing(
            modelID: "claude-opus-4",
            displayName: "Claude Opus 4",
            inputPrice: 15.0, outputPrice: 75.0,
            cacheReadPrice: 1.50, cacheWritePrice: 18.75
        )
        let cost = PricingEngine().calculateCost(usage: usage, pricing: pricing)
        #expect(abs(cost - 15.0) < 0.0001)
    }

    @Test("tiered - PricingTable 中 sonnet-4-5 已带 above_200k")
    func tieredSonnet45HasAbovePrices() {
        let pricing = PricingTable.pricing(for: "claude-sonnet-4-5")
        #expect(pricing?.inputPriceAbove200k == 6.0)
        #expect(pricing?.outputPriceAbove200k == 22.5)
        #expect(pricing?.cacheReadPriceAbove200k == 0.60)
        #expect(pricing?.cacheWritePriceAbove200k == 7.50)
    }

    @Test("tiered - PricingTable 中 sonnet-4 已带 above_200k")
    func tieredSonnet4HasAbovePrices() {
        let pricing = PricingTable.pricing(for: "claude-sonnet-4")
        #expect(pricing?.inputPriceAbove200k == 6.0)
        #expect(pricing?.outputPriceAbove200k == 22.5)
    }

    @Test("tiered - 3.5 Sonnet 的 output above 是 ×2 (非 ×1.5)")
    func tieredSonnet35OutputAboveIsDouble() {
        // 该 exact LiteLLM provider 条目的 output above_200k = 3e-05 = $30/1M。
        let pricing = PricingTable.pricing(
            for: "anthropic.claude-3-5-sonnet-20240620-v1:0"
        )
        #expect(abs((pricing?.outputPriceAbove200k ?? 0) - 30.0) < 1e-9)
    }

    @Test("tiered - Opus / Haiku / Fable / 3.7 Sonnet 没有 above 价")
    func tieredNonSonnet4FamilyHasNoAbove() {
        #expect(PricingTable.pricing(for: "claude-opus-4")?.inputPriceAbove200k == nil)
        #expect(PricingTable.pricing(for: "claude-opus-4-5")?.inputPriceAbove200k == nil)
        #expect(PricingTable.pricing(for: "claude-haiku-4-5")?.inputPriceAbove200k == nil)
        #expect(PricingTable.pricing(for: "claude-fable-5")?.inputPriceAbove200k == nil)
        #expect(PricingTable.pricing(for: "claude-3.7-sonnet")?.inputPriceAbove200k == nil)
    }

    @Test("未知模型成本为 0")
    func unknownModelCostIsZero() {
        let usage = TokenUsage(
            inputTokens: 1_000_000,
            cacheCreationInputTokens: 0,
            cacheReadInputTokens: 0,
            outputTokens: 1_000_000,
            serverToolUse: ServerToolUse(webSearchRequests: 0, webFetchRequests: 0),
            serviceTier: "standard",
            cacheCreation: CacheCreation(ephemeral1hInputTokens: 0, ephemeral5mInputTokens: 0),
            inferenceGeo: "",
            iterations: [],
            speed: "standard"
        )

        let (cost, pricing) = engine.calculateCost(usage: usage, model: "unknown-model")
        #expect(pricing == nil)
        #expect(cost == 0.0)
    }

    @Test("未知模型日志同一标准化模型只放行一次")
    func missingPricingLogGateAllowsEachNormalizedModelOnce() {
        let gate = MissingPricingLogOnceGate()

        #expect(gate.shouldLogMiss(for: "Private-Unknown-Model"))
        #expect(!gate.shouldLogMiss(for: "private-unknown-model"))
        #expect(gate.shouldLogMiss(for: "another-unknown-model"))
    }

    // MARK: - Speed::Fast multiplier
    //
    // 参考 ccusage `cost.rs::calculate_cost_from_tokens`:
    //   let multiplier = if matches!(usage.speed, Some(Speed::Fast)) {
    //       pricing.fast_multiplier
    //   } else {
    //       1.0
    //   };
    //   (sum_of_all_tiered_costs) * multiplier
    //
    // - 仅 JSONL 中 `speed == "fast"` (lowercase) 触发
    // - multiplier 应用在所有 tiered_cost 之和上(末尾整体乘一次)
    // - LiteLLM 上仅 Claude Opus 4.6 / 4.7 / 4.8 配置了 fast(6.0 / 6.0 / 2.0)
    // - speed 缺失或 "standard" → multiplier = 1.0

    @Test("fast - speed=fast 且模型有 fastMultiplier 时整体乘倍")
    func fastSpeedAppliesMultiplier() {
        // Opus 4.8 fast=2.0;1M input + 1M output → ($5 + $25) × 2.0 = $60
        let usage = TokenUsage(
            inputTokens: 1_000_000,
            cacheCreationInputTokens: 0,
            cacheReadInputTokens: 0,
            outputTokens: 1_000_000,
            serverToolUse: ServerToolUse(webSearchRequests: 0, webFetchRequests: 0),
            serviceTier: "standard",
            cacheCreation: CacheCreation(ephemeral1hInputTokens: 0, ephemeral5mInputTokens: 0),
            inferenceGeo: "",
            iterations: [],
            speed: "fast"
        )
        let (cost, pricing) = engine.calculateCost(usage: usage, model: "claude-opus-4-8")
        #expect(pricing?.fastMultiplier == 2.0)
        #expect(abs(cost - 60.0) < 0.0001)
    }

    @Test("fast - speed=standard 时不乘 multiplier")
    func standardSpeedDoesNotApplyMultiplier() {
        // 同样 Opus 4.8,但 speed=standard → 仅 $30
        let usage = TokenUsage(
            inputTokens: 1_000_000,
            cacheCreationInputTokens: 0,
            cacheReadInputTokens: 0,
            outputTokens: 1_000_000,
            serverToolUse: ServerToolUse(webSearchRequests: 0, webFetchRequests: 0),
            serviceTier: "standard",
            cacheCreation: CacheCreation(ephemeral1hInputTokens: 0, ephemeral5mInputTokens: 0),
            inferenceGeo: "",
            iterations: [],
            speed: "standard"
        )
        let (cost, _) = engine.calculateCost(usage: usage, model: "claude-opus-4-8")
        #expect(abs(cost - 30.0) < 0.0001)
    }

    @Test("fast - speed 字段缺失(空串)等同 standard")
    func absentSpeedIsStandard() {
        let usage = TokenUsage(
            inputTokens: 1_000_000,
            cacheCreationInputTokens: 0,
            cacheReadInputTokens: 0,
            outputTokens: 0,
            serverToolUse: ServerToolUse(webSearchRequests: 0, webFetchRequests: 0),
            serviceTier: "standard",
            cacheCreation: CacheCreation(ephemeral1hInputTokens: 0, ephemeral5mInputTokens: 0),
            inferenceGeo: "",
            iterations: [],
            speed: ""
        )
        let (cost, _) = engine.calculateCost(usage: usage, model: "claude-opus-4-8")
        // 1M × $5 = $5(无乘倍)
        #expect(abs(cost - 5.0) < 0.0001)
    }

    @Test("fast - 未知 speed 字符串不应触发乘倍")
    func unknownSpeedStringIsTreatedAsStandard() {
        // 仅小写 "fast" 触发,任何其他值(包括 "Fast"/"FAST"/"turbo")退化为 standard
        let usage = TokenUsage(
            inputTokens: 1_000_000,
            cacheCreationInputTokens: 0,
            cacheReadInputTokens: 0,
            outputTokens: 0,
            serverToolUse: ServerToolUse(webSearchRequests: 0, webFetchRequests: 0),
            serviceTier: "standard",
            cacheCreation: CacheCreation(ephemeral1hInputTokens: 0, ephemeral5mInputTokens: 0),
            inferenceGeo: "",
            iterations: [],
            speed: "Fast"
        )
        let (cost, _) = engine.calculateCost(usage: usage, model: "claude-opus-4-8")
        #expect(abs(cost - 5.0) < 0.0001)
    }

    @Test("fast - 模型无 fastMultiplier(默认 1.0)时即便 speed=fast 也不变")
    func fastSpeedOnModelWithoutMultiplierIsNoOp() {
        // Haiku 4.5 既无 above_200k 也无 fastMultiplier → 1M 各端就是 $1 + $5 = $6
        let usage = TokenUsage(
            inputTokens: 1_000_000,
            cacheCreationInputTokens: 0,
            cacheReadInputTokens: 0,
            outputTokens: 1_000_000,
            serverToolUse: ServerToolUse(webSearchRequests: 0, webFetchRequests: 0),
            serviceTier: "standard",
            cacheCreation: CacheCreation(ephemeral1hInputTokens: 0, ephemeral5mInputTokens: 0),
            inferenceGeo: "",
            iterations: [],
            speed: "fast"
        )
        let (cost, pricing) = engine.calculateCost(usage: usage, model: "claude-haiku-4-5")
        #expect(pricing?.fastMultiplier == 1.0)
        #expect(abs(cost - 6.0) < 0.0001)  // 无 above 也无 fast,$1 + $5 = $6
    }

    @Test("fast - 与 200k tier 的乘法顺序:整体一次性乘")
    func fastInteractsWithTier() {
        // 假设场景:claude-opus-4-8 input 250k, speed=fast
        // 注:Opus 4.8 在 LiteLLM 上没有 above_200k,实际 above 价为 nil → 不会跨阈
        // 但若有 above,则:tiered(input) × multiplier
        // 这里换用 Sonnet 4.5(有 above)+ 手工 fastMultiplier,验证乘法顺序
        let usage = TokenUsage(
            inputTokens: 250_000,
            cacheCreationInputTokens: 0,
            cacheReadInputTokens: 0,
            outputTokens: 0,
            serverToolUse: ServerToolUse(webSearchRequests: 0, webFetchRequests: 0),
            serviceTier: "standard",
            cacheCreation: CacheCreation(ephemeral1hInputTokens: 0, ephemeral5mInputTokens: 0),
            inferenceGeo: "",
            iterations: [],
            speed: "fast"
        )
        let pricing = ModelPricing(
            modelID: "test-tiered-fast",
            displayName: "Test",
            inputPrice: 3.0, outputPrice: 15.0,
            cacheReadPrice: 0.30, cacheWritePrice: 3.75,
            inputPriceAbove200k: 6.0,
            outputPriceAbove200k: 22.5,
            cacheReadPriceAbove200k: 0.60,
            cacheWritePriceAbove200k: 7.50,
            fastMultiplier: 2.5
        )
        let cost = engine.calculateCost(usage: usage, pricing: pricing)
        // tiered(input 250k) = 200k×3 + 50k×6 = $0.60 + $0.30 = $0.90
        // × 2.5 = $2.25
        #expect(abs(cost - 2.25) < 0.0001)
    }

    @Test("fast - PricingTable 中 Opus 4.6/4.7/4.8 已带 fastMultiplier")
    func fastPricingTableEntries() {
        #expect(PricingTable.pricing(for: "claude-opus-4-6")?.fastMultiplier == 6.0)
        #expect(PricingTable.pricing(for: "claude-opus-4-7")?.fastMultiplier == 6.0)
        #expect(PricingTable.pricing(for: "claude-opus-4-8")?.fastMultiplier == 2.0)
    }

    @Test("fast - 其他模型 fastMultiplier 默认 1.0")
    func fastDefaultIsOne() {
        #expect(PricingTable.pricing(for: "claude-opus-4")?.fastMultiplier == 1.0)
        #expect(PricingTable.pricing(for: "claude-opus-4-5")?.fastMultiplier == 1.0)
        #expect(PricingTable.pricing(for: "claude-sonnet-4-5")?.fastMultiplier == 1.0)
        #expect(PricingTable.pricing(for: "claude-haiku-4-5")?.fastMultiplier == 1.0)
    }

    @Test("fast - 带日期后缀的 Opus 4.8 也命中 fast=2.0")
    func fastDateSuffixMatch() {
        // claude-opus-4-8-20260101 → 前缀匹配 claude-opus-4-8 → fast=2.0
        let pricing = PricingTable.pricing(for: "claude-opus-4-8-20260101")
        #expect(pricing?.modelID == "claude-opus-4-8")
        #expect(pricing?.fastMultiplier == 2.0)
    }

    // MARK: - 离线 catalog 来源
    //
    // PricingTable 使用 filtered LiteLLM primary + 独立 models.dev fallback。
    // 这里只做存在性 + 价格量级的回归检查，具体单价以固定离线快照为准。

    @Test("filtered LiteLLM primary - Bedrock anthropic.* 别名能命中")
    func liteLLMBedrockPrimary() {
        // builtin 中没有这个 key，由 filtered LiteLLM primary 命中。
        let pricing = PricingTable.pricing(for: "anthropic.claude-opus-4-5-20251101-v1:0")
        #expect(pricing != nil)
        #expect(abs((pricing?.inputPrice ?? 0) - 5.0) < 1e-9)
        #expect(abs((pricing?.outputPrice ?? 0) - 25.0) < 1e-9)
    }

    @Test("builtin exact 在 primary 组装后仍可查询")
    func builtinExactRemainsAvailable() {
        let pricing = PricingTable.pricing(for: "claude-opus-4-5")
        #expect(pricing?.modelID == "claude-opus-4-5")
        #expect(abs((pricing?.inputPrice ?? 0) - 5.0) < 1e-9)
    }

    @Test("primary 与 models.dev fallback 都无法识别时返回 nil")
    func offlineCatalogsReturnNilForUnknown() {
        // 两个离线来源都 miss，最终返回 nil → 上层 logger.warning + cost=0。
        let pricing = PricingTable.pricing(for: "this-model-definitely-does-not-exist-anywhere-xyzzy")
        #expect(pricing == nil)
    }

    @Test("GPT-5 系列命中并计费 — Codex Provider 用")
    func gpt5Pricing() {
        #expect(PricingTable.pricing(for: "gpt-5")?.inputPrice == 1.25)
        #expect(PricingTable.pricing(for: "gpt-5.5")?.outputPrice == 30.0)
        #expect(PricingTable.pricing(for: "gpt-5.4-mini")?.cacheReadPrice == 0.075)
        // 前缀匹配:实际 Codex 不会拼日期后缀,但确保行为不破坏
        #expect(PricingTable.pricing(for: "gpt-5") != nil)
    }
}

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
