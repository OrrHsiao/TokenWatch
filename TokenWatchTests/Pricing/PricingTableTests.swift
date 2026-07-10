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
