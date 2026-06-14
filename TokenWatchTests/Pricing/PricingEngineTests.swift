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

    @Test("精确匹配模型定价")
    func exactModelMatch() {
        let pricing = PricingTable.pricing(for: "deepseek-v4-pro")
        #expect(pricing != nil)
        #expect(pricing?.displayName == "DeepSeek V4 Pro")
        #expect(pricing?.inputPrice == 3.0)
        #expect(pricing?.outputPrice == 15.0)
    }

    @Test("前缀模糊匹配 - 带日期后缀")
    func prefixFuzzyMatch() {
        // "claude-opus-4-20250514" 应匹配 "claude-opus-4"（8 位日期后缀允许）
        let pricing = PricingTable.pricing(for: "claude-opus-4-20250514")
        #expect(pricing != nil)
        #expect(pricing?.displayName == "Claude Opus 4")
    }

    @Test("版本号守卫 - sonnet-4-5-20250514 不应误命中 sonnet-4")
    func versionGuardSonnet45() {
        // 关键回归：候选 "claude-sonnet-4" 与 "claude-sonnet-4-5" 都是输入前缀,
        // 必须命中 4-5 而不是 4
        let pricing = PricingTable.pricing(for: "claude-sonnet-4-5-20250514")
        #expect(pricing?.displayName == "Claude Sonnet 4.5")
    }

    @Test("版本号守卫 - opus-4-1-... 应命中 4-1 而不是 4")
    func versionGuardOpus41() {
        let pricing = PricingTable.pricing(for: "claude-opus-4-1-20250830")
        #expect(pricing?.displayName == "Claude Opus 4.1")
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
        // LiteLLM 上 claude-3-5-sonnet 的 output above_200k = 3e-05 = $30/1M
        let pricing = PricingTable.pricing(for: "claude-3.5-sonnet")
        #expect(pricing?.outputPriceAbove200k == 30.0)
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
}
