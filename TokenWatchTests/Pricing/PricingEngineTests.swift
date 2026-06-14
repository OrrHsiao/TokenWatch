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

    @Test("缓存写入成本计算")
    func cacheWriteCost() {
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
        // cache write: 200K * $18.75/1M = $3.75
        // total: $6.00
        #expect(abs(cost - 6.00) < 0.001)
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
        // "claude-opus-4-20250514" 应匹配 "claude-opus-4"
        let pricing = PricingTable.pricing(for: "claude-opus-4-20250514")
        #expect(pricing != nil)
        #expect(pricing?.displayName == "Claude Opus 4")
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
