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
        #expect(abs((table.pricing(for: "gpt-5.5")?.inputPrice ?? 0) - 5.0) < 1e-9)
        #expect(abs((table.pricing(for: "gpt-5.5")?.fastMultiplier ?? 0) - 2.5) < 1e-9)
        #expect(abs((table.pricing(
            for: "anthropic/claude-opus-4-6-v1"
        )?.fastMultiplier ?? 0) - 7.0) < 1e-9)
        #expect(abs((table.pricing(
            for: "amazon/claude-opus-4-6-v1"
        )?.fastMultiplier ?? 0) - 6.0) < 1e-9)
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
