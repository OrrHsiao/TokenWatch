import Foundation
import Testing
@testable import TokenWatch

@Suite("DeepSeekHarnessPricing")
struct DeepSeekHarnessPricingTests {
    @Test("候选键按 route 精确 → 模型名 → 次版本归并排序")
    func candidateOrder() {
        #expect(DeepSeekHarnessPricingCandidateResolver.candidates(
            modelID: "deepseek-v4.1-flash",
            providerID: "opencode-go"
        ) == [
            "opencode-go/deepseek-v4.1-flash",
            "deepseek-v4.1-flash",
            "opencode-go/deepseek-v4-flash",
            "deepseek-v4-flash",
        ])

        // 无 route 时不生成 route 前缀键，且候选去重。
        #expect(DeepSeekHarnessPricingCandidateResolver.candidates(
            modelID: "deepseek-v4-flash",
            providerID: nil
        ) == ["deepseek-v4-flash"])
        #expect(DeepSeekHarnessPricingCandidateResolver.candidates(
            modelID: "  ",
            providerID: "opencode-go"
        ).isEmpty)
    }

    @Test("次版本归并只去掉 .N 片段")
    func minorVersionFolding() {
        #expect(DeepSeekHarnessPricingCandidateResolver.minorVersionFolded("deepseek-v4.1-flash")
            == "deepseek-v4-flash")
        #expect(DeepSeekHarnessPricingCandidateResolver.minorVersionFolded("deepseek-v4.1.2-flash")
            == "deepseek-v4.1-flash")
        #expect(DeepSeekHarnessPricingCandidateResolver.minorVersionFolded("deepseek-v4-flash") == nil)
        #expect(DeepSeekHarnessPricingCandidateResolver.minorVersionFolded("gpt-5.6-luna")
            == "gpt-5-luna")
    }

    @Test("内置价格快照覆盖 DSH 常见的 DeepSeek route×model")
    func builtinSnapshotResolvesKnownModels() {
        let store = DeepSeekHarnessPriceCatalogStore()
        #expect(store.debugBuiltinEntryCount > 0)

        let goFlash = store.pricing(forKey: "opencode-go/deepseek-v4.1-flash")
        #expect(goFlash?.inputPrice == 0.15)
        #expect(goFlash?.outputPrice == 0.6)
        #expect(goFlash?.cacheReadPrice == 0.003)

        // route 未知时回落到模型名兜底价。
        let fallback = store.pricing(forKey: "deepseek-v4.1-flash")
        #expect(fallback?.inputPrice == 0.3)

        #expect(store.pricing(forKey: "unknown-route/unknown-model") == nil)
        #expect(store.pricing(forKey: "") == nil)
    }

    @Test("动态 pi-ai 目录优先于内置快照")
    func dynamicCatalogTakesPrecedenceOverBuiltin() throws {
        let catalogJSON = """
        {"openai-completions":{"deepseek-v4.1-flash":{"id":"deepseek-v4.1-flash",\
        "name":"DeepSeek V4.1 Flash","provider":"opencode-go",\
        "cost":{"input":9.5,"output":19.5,"cacheRead":0.95,"cacheWrite":0}}}}
        """
        let catalog = DeepSeekHarnessPriceCatalog.parse(files: [
            (provider: "opencode-go", data: Data(catalogJSON.utf8)),
        ])
        let store = DeepSeekHarnessPriceCatalogStore()
        store.install(catalog: catalog, rootPath: "/tmp/fake-dsh")

        #expect(store.debugEntryCount == 1)
        #expect(store.pricing(forKey: "opencode-go/deepseek-v4.1-flash")?.inputPrice == 9.5)
        // 动态目录没有的模型仍由内置快照兜底。
        #expect(store.pricing(forKey: "deepseek-v4-flash")?.inputPrice == 0.14)
    }

    @Test("pi-ai 目录解析同时生成 route 键与模型名键")
    func parsesPiAiCatalog() throws {
        let catalogJSON = """
        {"anthropic-messages":{"model-a":{"id":"model-a","name":"Model A","provider":"route-x",\
        "cost":{"input":1,"output":2,"cacheRead":0.1,"cacheWrite":1.25}}},\
        "openai-completions":{"model-a":{"id":"model-a","name":"Model A","provider":"route-y",\
        "cost":{"input":3,"output":4,"cacheRead":0.3,"cacheWrite":0}}}}
        """
        let catalog = DeepSeekHarnessPriceCatalog.parse(files: [
            (provider: "ignored-file-name", data: Data(catalogJSON.utf8)),
        ])

        #expect(catalog.pricing(forKey: "route-x/model-a")?.inputPrice == 1)
        #expect(catalog.pricing(forKey: "route-y/model-a")?.inputPrice == 3)
        // 模型名兜底键在多个 provider 竞争时取确定性结果（字典序最小 route）。
        #expect(catalog.pricing(forKey: "model-a")?.inputPrice == 1)
    }

    @Test("损坏的目录文件被跳过，不影响其它文件")
    func skipsCorruptedCatalogFile() throws {
        let validJSON = """
        {"openai-completions":{"model-b":{"id":"model-b","provider":"route-z",\
        "cost":{"input":5,"output":6,"cacheRead":0.5,"cacheWrite":0}}}}
        """
        let catalog = DeepSeekHarnessPriceCatalog.parse(files: [
            (provider: "broken", data: Data("{ not json".utf8)),
            (provider: "valid", data: Data(validJSON.utf8)),
        ])
        #expect(catalog.pricing(forKey: "route-z/model-b")?.inputPrice == 5)
    }

    @Test("UsageCostResolver 对 DSH 记录使用 route 价格")
    func costResolverUsesRoutePricing() throws {
        let store = DeepSeekHarnessPriceCatalogStore()
        let resolver = UsageCostResolver(deepSeekHarnessPriceCatalog: store)
        let entry = makeEntry(
            model: "deepseek-v4.1-flash",
            route: "opencode-go",
            inputTokens: 1_000_000,
            outputTokens: 1_000_000,
            cacheReadTokens: 1_000_000
        )

        // 0.15 + 0.6 + 0.003
        #expect(abs(resolver.resolvedCost(for: entry) - 0.753) < 1e-9)
    }

    @Test("未收录的模型按 0 计费而不是猜测")
    func unknownModelResolvesToZero() throws {
        let store = DeepSeekHarnessPriceCatalogStore()
        let resolver = UsageCostResolver(deepSeekHarnessPriceCatalog: store)
        let entry = makeEntry(
            model: "totally-unknown-model",
            route: "unknown-route",
            inputTokens: 1_000_000,
            outputTokens: 1_000_000,
            cacheReadTokens: 0
        )
        #expect(resolver.resolvedCost(for: entry) == 0)
    }

    private func makeEntry(
        model: String,
        route: String,
        inputTokens: Int,
        outputTokens: Int,
        cacheReadTokens: Int
    ) -> ParsedUsageEntry {
        ParsedUsageEntry(
            recordUUID: "1:1:0",
            messageId: "msg-1",
            requestId: nil,
            sessionID: "session-1",
            timestamp: Date(timeIntervalSince1970: 1_790_757_477),
            model: model,
            upstreamModelID: model,
            cwd: "/tmp/project",
            agentId: nil,
            usage: TokenUsage(
                inputTokens: inputTokens,
                cacheCreationInputTokens: 0,
                cacheReadInputTokens: cacheReadTokens,
                outputTokens: outputTokens,
                serverToolUse: ServerToolUse(webSearchRequests: 0, webFetchRequests: 0),
                serviceTier: "",
                cacheCreation: nil,
                inferenceGeo: "",
                iterations: [],
                speed: ""
            ),
            isSubagent: false,
            provider: .deepSeekHarness,
            upstreamProviderID: route,
            upstreamCost: nil
        )
    }
}
