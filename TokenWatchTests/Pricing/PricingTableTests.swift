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
        #expect(abs(derived.pricing.inputPrice - 2.0) < 1e-9)
        #expect(abs(derived.pricing.cacheWritePrice - 2.5) < 1e-9)
        #expect(abs(derived.pricing.cacheReadPrice - 0.2) < 1e-9)
        #expect(!derived.pricing.cacheReadPriceIsExplicit)
        #expect(derived.explicitFastMultiplier == nil)
        #expect(abs(explicit.pricing.cacheWritePrice - 4.0) < 1e-9)
        #expect(abs(explicit.pricing.cacheReadPrice - 0.4) < 1e-9)
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

        #expect(abs(fallback.inputPrice - 4.0) < 1e-9)
        #expect(abs(fallback.cacheWritePrice - 5.0) < 1e-9)
        #expect(abs(fallback.cacheReadPrice - 0.4) < 1e-9)
        #expect(!fallback.cacheReadPriceIsExplicit)
        #expect(abs(explicit.cacheWritePrice - 6.5) < 1e-9)
        #expect(abs(explicit.cacheReadPrice - 0.7) < 1e-9)
        #expect(explicit.cacheReadPriceIsExplicit)
        #expect(catalog.entries["missing-output"] == nil)
    }
}

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

        #expect(abs((table.pricing(for: "same-key")?.inputPrice ?? 0) - 5.0) < 1e-9)
        #expect(abs((table.pricing(for: "primary-only")?.inputPrice ?? 0) - 3.0) < 1e-9)
        #expect(abs((table.pricing(for: "fallback-only")?.inputPrice ?? 0) - 7.0) < 1e-9)
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

    @Test("空 model 不命中空定价 key")
    func emptyModelDoesNotMatchEmptyPricingKey() {
        let table = PricingTable(
            liteLLMEntries: ["": catalogEntry(id: "empty", input: 1.0)],
            modelsDevEntries: [:],
            builtins: [:]
        )

        #expect(table.pricing(for: "") == nil)
    }

    @Test("空定价 key 不参与非空 model 的模糊匹配")
    func emptyPricingKeyDoesNotFuzzyMatchModel() {
        let table = PricingTable(
            liteLLMEntries: ["": catalogEntry(id: "empty", input: 1.0)],
            modelsDevEntries: [:],
            builtins: [:]
        )

        #expect(table.pricing(for: "claude-sonnet-4-5") == nil)
    }

    @Test("LiteLLM 损坏时仍保留有效 models.dev catalog")
    func corruptLiteLLMKeepsModelsDevCatalog() throws {
        let files = try catalogFiles(
            liteLLM: Data("{".utf8),
            modelsDev: Data(#"{"models-dev-independent":{"cost":{"input":7,"output":28}}}"#.utf8)
        )
        defer { try? FileManager.default.removeItem(at: files.directory) }

        let table = PricingTable.load(
            liteLLMURL: files.liteLLM,
            modelsDevURL: files.modelsDev
        )

        #expect(table.pricing(for: "models-dev-independent")?.inputPrice == 7)
    }

    @Test("models.dev 损坏时仍保留有效 LiteLLM catalog")
    func corruptModelsDevKeepsLiteLLMCatalog() throws {
        let files = try catalogFiles(
            liteLLM: Data(#"{"gpt-independent-loader":{"i":0.000002,"o":0.000008}}"#.utf8),
            modelsDev: Data("{".utf8)
        )
        defer { try? FileManager.default.removeItem(at: files.directory) }

        let table = PricingTable.load(
            liteLLMURL: files.liteLLM,
            modelsDevURL: files.modelsDev
        )

        #expect(table.pricing(for: "gpt-independent-loader")?.inputPrice == 2)
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
        #expect(abs((table.pricing(for: "claude-opus-4.7-20260416")?.inputPrice ?? 0) - 5.0) < 1e-9)
        #expect(abs((table.pricing(for: "provider/glm-5.1")?.inputPrice ?? 0) - 1.4) < 1e-9)
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
        #expect(abs((table.pricing(for: "gpt-5.3-spark")?.inputPrice ?? 0) - 1.75) < 1e-9)
    }

    @Test("exact builtin 覆盖 LiteLLM；fast 显式优先且仅第一方 Anthropic 补缺失")
    func fastOverlayPriority() {
        let conflictingExact = catalogEntry(
            id: "gpt-5.6-sol",
            input: 99.0,
            explicitFast: 3.0
        )
        let providerExplicit = catalogEntry(
            id: "anthropic/claude-opus-5-v1",
            input: 5.0,
            explicitFast: 7.0
        )
        let firstPartyMissing = catalogEntry(
            id: "anthropic/claude-opus-5-v2",
            input: 5.0
        )
        let partnerMissing = catalogEntry(
            id: "amazon/claude-opus-5-v1",
            input: 5.0
        )
        let bedrockMissing = catalogEntry(
            id: "anthropic.claude-opus-5-v1:0",
            input: 5.0
        )
        let table = PricingTable(
            liteLLMEntries: [
                "gpt-5.6-sol": conflictingExact,
                "anthropic/claude-opus-5-v1": providerExplicit,
                "anthropic/claude-opus-5-v2": firstPartyMissing,
                "amazon/claude-opus-5-v1": partnerMissing,
                "anthropic.claude-opus-5-v1:0": bedrockMissing,
            ],
            modelsDevEntries: [:],
            builtins: ["gpt-5.6-sol": pricing(id: "gpt-5.6-sol", input: 4.0, fast: 2.0)]
        )
        #expect(abs((table.pricing(for: "gpt-5.6-sol")?.inputPrice ?? 0) - 4.0) < 1e-9)
        #expect(abs((table.pricing(for: "gpt-5.6-sol")?.fastMultiplier ?? 0) - 2.0) < 1e-9)
        #expect(abs((table.pricing(
            for: "anthropic/claude-opus-5-v1"
        )?.fastMultiplier ?? 0) - 7.0) < 1e-9)
        #expect(abs((table.pricing(
            for: "anthropic/claude-opus-5-v2"
        )?.fastMultiplier ?? 0) - 2.0) < 1e-9)
        #expect(abs((table.pricing(
            for: "amazon/claude-opus-5-v1"
        )?.fastMultiplier ?? 0) - 1.0) < 1e-9)
        #expect(abs((table.pricing(
            for: "anthropic.claude-opus-5-v1:0"
        )?.fastMultiplier ?? 0) - 1.0) < 1e-9)

        let fuzzyFallbackTable = PricingTable(
            liteLLMEntries: [:],
            modelsDevEntries: [:],
            builtins: [
                "claude-opus-5": pricing(id: "claude-opus-5", input: 5.0, fast: 2.0),
            ]
        )
        #expect(fuzzyFallbackTable.pricing(
            for: "anthropic/claude-opus-5-20260820"
        )?.fastMultiplier == 2.0)
        #expect(fuzzyFallbackTable.pricing(
            for: "amazon/claude-opus-5-v1"
        )?.fastMultiplier == 1.0)
        #expect(fuzzyFallbackTable.pricing(
            for: "anthropic.claude-opus-5-v1:0"
        )?.fastMultiplier == 1.0)
    }

    @Test("当前 builtin 模型的 effective fast multiplier 固定")
    func builtinEffectiveFastMultipliers() {
        let expected: [String: Double] = [
            "claude-opus-4-6": 1.0,
            "claude-opus-4-7": 1.0,
            "claude-opus-4-8": 2.0,
            "claude-opus-5": 2.0,
            "gpt-5.3-codex": 2.0,
            "gpt-5.4": 2.0,
            "gpt-5.5": 2.5,
            "gpt-5.6-sol": 2.0,
            "gpt-5.6-terra": 2.0,
            "gpt-5.6-luna": 2.0,
        ]

        for modelID in expected.keys.sorted() {
            #expect(PricingTable.pricing(for: modelID)?.fastMultiplier == expected[modelID])
        }
    }

    @Test("最新模型默认价格、长上下文与 fast 契约固定")
    func updatedAndNewModelPricingContracts() {
        let expected: [PricingExpectation] = [
            .init(
                requestedID: "gpt-5.6", matchedID: "gpt-5.6-sol",
                input: 4, output: 20, cacheRead: 0.4, cacheWrite: 5,
                inputAbove: 8, outputAbove: 30, cacheReadAbove: 0.8,
                cacheWriteAbove: 10, threshold: 272_000, fast: 2
            ),
            .init(
                requestedID: "gpt-5.6-sol", matchedID: "gpt-5.6-sol",
                input: 4, output: 20, cacheRead: 0.4, cacheWrite: 5,
                inputAbove: 8, outputAbove: 30, cacheReadAbove: 0.8,
                cacheWriteAbove: 10, threshold: 272_000, fast: 2
            ),
            .init(
                requestedID: "gpt-5.6-terra", matchedID: "gpt-5.6-terra",
                input: 2, output: 12, cacheRead: 0.2, cacheWrite: 2.5,
                inputAbove: 4, outputAbove: 18, cacheReadAbove: 0.4,
                cacheWriteAbove: 5, threshold: 272_000, fast: 2
            ),
            .init(
                requestedID: "gpt-5.6-luna", matchedID: "gpt-5.6-luna",
                input: 0.2, output: 1.2, cacheRead: 0.02, cacheWrite: 0.25,
                inputAbove: 0.4, outputAbove: 1.8, cacheReadAbove: 0.04,
                cacheWriteAbove: 0.5, threshold: 272_000, fast: 2
            ),
            .init(
                requestedID: "claude-opus-5", matchedID: "claude-opus-5",
                input: 5, output: 25, cacheRead: 0.5, cacheWrite: 6.25,
                fast: 2
            ),
            .init(
                requestedID: "claude-sonnet-5", matchedID: "claude-sonnet-5",
                input: 2, output: 10, cacheRead: 0.2, cacheWrite: 2.5,
                fast: 1
            ),
            .init(
                requestedID: "gemini-3.5-flash", matchedID: "gemini-3.5-flash",
                input: 1.5, output: 9, cacheRead: 0.15, cacheWrite: 1.875,
                cacheReadIsExplicit: true, fast: 1
            ),
            .init(
                requestedID: "gemini-3.5-flash-lite", matchedID: "gemini-3.5-flash-lite",
                input: 0.3, output: 2.5, cacheRead: 0.03, cacheWrite: 0.375,
                cacheReadIsExplicit: true, fast: 1
            ),
            .init(
                requestedID: "gemini-3.6-flash", matchedID: "gemini-3.6-flash",
                input: 0.75, output: 3.75, cacheRead: 0.075, cacheWrite: 0.9375,
                cacheReadIsExplicit: true, fast: 1
            ),
            .init(
                requestedID: "gemini-3.7-flash", matchedID: "gemini-3.7-flash",
                input: 0.75, output: 3.75, cacheRead: 0.075, cacheWrite: 0.9375,
                cacheReadIsExplicit: true, fast: 1
            ),
            .init(
                requestedID: "gemini-3.8-flash", matchedID: "gemini-3.8-flash",
                input: 0.75, output: 3.75, cacheRead: 0.075, cacheWrite: 0.9375,
                cacheReadIsExplicit: true, fast: 1
            ),
            .init(
                requestedID: "gemini-3.8-pro", matchedID: "gemini-3.8-pro",
                input: 2.5, output: 10.0, cacheRead: 0.25, cacheWrite: 3.125,
                cacheReadIsExplicit: true, fast: 1
            ),
            .init(
                requestedID: "grok-4.3", matchedID: "grok-4.3",
                input: 1.25, output: 2.5, cacheRead: 0.2, cacheWrite: 1.5625,
                inputAbove: 2.5, outputAbove: 5, cacheReadAbove: 0.4,
                threshold: 199_999, fast: 1
            ),
            .init(
                requestedID: "grok-4.20-multi-agent-0309",
                matchedID: "grok-4.20-multi-agent-0309",
                input: 1.25, output: 2.5, cacheRead: 0.2, cacheWrite: 1.5625,
                inputAbove: 2.5, outputAbove: 5, cacheReadAbove: 0.4,
                threshold: 199_999, fast: 1
            ),
            .init(
                requestedID: "grok-4.20-0309-reasoning",
                matchedID: "grok-4.20-0309-reasoning",
                input: 1.25, output: 2.5, cacheRead: 0.2, cacheWrite: 1.5625,
                inputAbove: 2.5, outputAbove: 5, cacheReadAbove: 0.4,
                threshold: 199_999, fast: 1
            ),
            .init(
                requestedID: "grok-4.20-0309-non-reasoning",
                matchedID: "grok-4.20-0309-non-reasoning",
                input: 1.25, output: 2.5, cacheRead: 0.2, cacheWrite: 1.5625,
                inputAbove: 2.5, outputAbove: 5, cacheReadAbove: 0.4,
                threshold: 199_999, fast: 1
            ),
            .init(
                requestedID: "grok-4.5", matchedID: "grok-4.5",
                input: 2, output: 6, cacheRead: 0.3, cacheWrite: 2.5,
                inputAbove: 4, outputAbove: 12, cacheReadAbove: 0.6,
                threshold: 199_999, fast: 1
            ),
            .init(
                requestedID: "grok-4.6", matchedID: "grok-4.6",
                input: 2, output: 6, cacheRead: 0.5, cacheWrite: 2.5,
                inputAbove: 4, outputAbove: 12, cacheReadAbove: 1,
                threshold: 199_999, fast: 1
            ),
            .init(
                requestedID: "grok-build-0.1", matchedID: "grok-build-0.1",
                input: 1, output: 2, cacheRead: 0.2, cacheWrite: 1.25,
                inputAbove: 2, outputAbove: 4, cacheReadAbove: 0.4,
                threshold: 199_999, fast: 1
            ),
            .init(
                requestedID: "moonshot/kimi-k3", matchedID: "moonshot/kimi-k3",
                input: 3, output: 15, cacheRead: 0.3, cacheWrite: 3.75,
                fast: 1
            ),
            .init(
                requestedID: "moonshot/kimi-k2.7-code", matchedID: "moonshot/kimi-k2.7-code",
                input: 0.95, output: 4, cacheRead: 0.19, cacheWrite: 1.1875,
                fast: 1
            ),
            .init(
                requestedID: "glm-5.2", matchedID: "glm-5.2",
                input: 1.4, output: 4.4, cacheRead: 0.26, cacheWrite: 0,
                fast: 1
            ),
            .init(
                requestedID: "glm-5.3", matchedID: "glm-5.3",
                input: 1.4, output: 4.4, cacheRead: 0.26, cacheWrite: 0,
                fast: 1
            ),
        ]

        for item in expected {
            let actual = PricingTable.pricing(for: item.requestedID)
            #expect(actual != nil, Comment(rawValue: "missing: \(item.requestedID)"))
            guard let actual else { continue }
            #expect(actual.modelID == item.matchedID, Comment(rawValue: item.requestedID))
            #expect(abs(actual.inputPrice - item.input) < 1e-9, Comment(rawValue: item.requestedID))
            #expect(abs(actual.outputPrice - item.output) < 1e-9, Comment(rawValue: item.requestedID))
            #expect(abs(actual.cacheReadPrice - item.cacheRead) < 1e-9, Comment(rawValue: item.requestedID))
            #expect(abs(actual.cacheWritePrice - item.cacheWrite) < 1e-9, Comment(rawValue: item.requestedID))
            #expect(
                actual.cacheReadPriceIsExplicit == item.cacheReadIsExplicit,
                Comment(rawValue: item.requestedID)
            )
            #expect(optionalPriceMatches(actual.inputPriceAbove200k, item.inputAbove))
            #expect(optionalPriceMatches(actual.outputPriceAbove200k, item.outputAbove))
            #expect(optionalPriceMatches(actual.cacheReadPriceAbove200k, item.cacheReadAbove))
            #expect(optionalPriceMatches(actual.cacheWritePriceAbove200k, item.cacheWriteAbove))
            #expect(actual.longContextThreshold == item.threshold, Comment(rawValue: item.requestedID))
            #expect(abs(actual.fastMultiplier - item.fast) < 1e-9, Comment(rawValue: item.requestedID))
        }
    }

    @Test("GPT-5.6 裸名稳定 alias 到 Sol，Kimi 裸名命中 canonical")
    func latestModelLookupBoundaries() {
        let expectedMatches = [
            (requested: "gpt-5.6", matched: "gpt-5.6-sol"),
            (requested: "openai/gpt-5.6", matched: "gpt-5.6-sol"),
            (requested: "azure:gpt-5.6", matched: "gpt-5.6-sol"),
            (requested: "kimi-k3", matched: "moonshot/kimi-k3"),
            (requested: "kimi-k2.7-code", matched: "moonshot/kimi-k2.7-code"),
        ]

        for item in expectedMatches {
            #expect(
                PricingTable.pricing(for: item.requested)?.modelID == item.matched,
                Comment(rawValue: item.requested)
            )
        }
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
        #expect(abs((gpt54.inputPriceAbove200k ?? 0) - 5.0) < 1e-9)
        #expect(abs((gpt54.outputPriceAbove200k ?? 0) - 22.5) < 1e-9)
        #expect(abs((gpt54.cacheReadPriceAbove200k ?? 0) - 0.5) < 1e-9)
        #expect(abs((gpt55.inputPriceAbove200k ?? 0) - 123.0) < 1e-9)
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

    private struct PricingExpectation {
        let requestedID: String
        let matchedID: String
        let input: Double
        let output: Double
        let cacheRead: Double
        let cacheWrite: Double
        let cacheReadIsExplicit: Bool
        let inputAbove: Double?
        let outputAbove: Double?
        let cacheReadAbove: Double?
        let cacheWriteAbove: Double?
        let threshold: Int?
        let fast: Double

        init(
            requestedID: String,
            matchedID: String,
            input: Double,
            output: Double,
            cacheRead: Double,
            cacheWrite: Double,
            cacheReadIsExplicit: Bool = true,
            inputAbove: Double? = nil,
            outputAbove: Double? = nil,
            cacheReadAbove: Double? = nil,
            cacheWriteAbove: Double? = nil,
            threshold: Int? = nil,
            fast: Double
        ) {
            self.requestedID = requestedID
            self.matchedID = matchedID
            self.input = input
            self.output = output
            self.cacheRead = cacheRead
            self.cacheWrite = cacheWrite
            self.cacheReadIsExplicit = cacheReadIsExplicit
            self.inputAbove = inputAbove
            self.outputAbove = outputAbove
            self.cacheReadAbove = cacheReadAbove
            self.cacheWriteAbove = cacheWriteAbove
            self.threshold = threshold
            self.fast = fast
        }
    }

    private func optionalPriceMatches(_ actual: Double?, _ expected: Double?) -> Bool {
        switch (actual, expected) {
        case (.none, .none):
            return true
        case let (.some(actual), .some(expected)):
            return abs(actual - expected) < 1e-9
        default:
            return false
        }
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

    private func catalogFiles(
        liteLLM: Data,
        modelsDev: Data
    ) throws -> (directory: URL, liteLLM: URL, modelsDev: URL) {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        let liteLLMURL = directory.appendingPathComponent("litellm.json")
        let modelsDevURL = directory.appendingPathComponent("models-dev.json")
        try liteLLM.write(to: liteLLMURL)
        try modelsDev.write(to: modelsDevURL)
        return (directory, liteLLMURL, modelsDevURL)
    }
}
