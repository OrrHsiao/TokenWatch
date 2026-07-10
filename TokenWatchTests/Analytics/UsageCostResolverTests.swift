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
