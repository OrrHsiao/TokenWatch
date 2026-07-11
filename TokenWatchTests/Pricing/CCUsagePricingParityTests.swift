import CryptoKit
import Foundation
import Testing
@testable import TokenWatch

@Suite("ccusage v20.0.17 Pricing Parity")
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
        let liteLLMArtifactSHA256: String
        let modelsDevArtifactSHA256: String
        let fastOverridesSourceSHA256: String
        let autoReviewFallbacksSourceSHA256: String
        let fastOverridesArtifactSHA256: String
        let autoReviewFallbacksArtifactSHA256: String
    }

    private struct Case: Decodable {
        let name: String
        let provider: ProviderID
        let model: String
        let upstreamModelID: String?
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
        #expect(fixture.baseline.ccusageVersion == "v20.0.17")
        #expect(fixture.baseline.ccusageCommit == "88cdfa4fb201c92b163a34d0bbb097b68d3185cf")
        #expect(fixture.baseline.costMode == "auto")
        #expect(fixture.baseline.offline)
        #expect(fixture.baseline.liteLLMRevision == "49ca04d8c3ddea336237ce6f3082dbc26d19e944")
        #expect(fixture.baseline.liteLLMSourceSHA256 == "ae4532ba0c5da03ed694f37fffa050a65e0e250b816dcdb475bee0b7b7b1aa97")
        #expect(fixture.baseline.modelsDevSourceSHA256 == "5d61cc3148100cd670d3289033b5e2fb05c4244cbe32f92888ef7bd2df1abf67")
        #expect(fixture.baseline.fastOverridesSourceSHA256 == "647b3ae8e44349455f32ce9f4633910b5151b08cda1707601a97701927490762")
        #expect(fixture.baseline.autoReviewFallbacksSourceSHA256 == "344d2438312beed608c19e616031d1b194f3c6efdfcbd0925f39f4df9008c037")
        #expect(fixture.cases.count == 21)
        #expect(Set(fixture.cases.map(\.name)).count == fixture.cases.count)

        let resolver = UsageCostResolver()
        for testCase in fixture.cases {
            let actual = resolver.resolvedCost(for: entry(from: testCase))
            #expect(
                abs(actual - testCase.expectedUSD) < 1e-9,
                Comment(rawValue: "\(testCase.name): actual=\(actual), expected=\(testCase.expectedUSD)")
            )
        }
    }

    @Test("实际 bundle 定价资源与固定产物哈希一致")
    func bundledPricingArtifacts() throws {
        let fixture = try loadFixture()

        #expect(try bundledSHA256(resource: "litellm_prices")
            == fixture.baseline.liteLLMArtifactSHA256)
        #expect(try bundledSHA256(resource: "models-dev-pricing")
            == fixture.baseline.modelsDevArtifactSHA256)
    }

    @Test("生产 fast 与 auto-review 映射的规范序列化哈希固定")
    func productionMappingArtifacts() throws {
        let fixture = try loadFixture()

        #expect(sha256(PricingTable.canonicalFastMultiplierOverrides)
            == fixture.baseline.fastOverridesArtifactSHA256)
        #expect(sha256(CodexModelResolver.canonicalAutoReviewFallbacks)
            == fixture.baseline.autoReviewFallbacksArtifactSHA256)
    }

    private func loadFixture() throws -> Fixture {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Fixtures/Pricing/ccusage-v20.0.17.json")
        return try JSONDecoder().decode(Fixture.self, from: Data(contentsOf: url))
    }

    private func bundledSHA256(resource: String) throws -> String {
        let url = try #require(Bundle.main.url(
            forResource: resource,
            withExtension: "json"
        ))
        return sha256(try Data(contentsOf: url))
    }

    private func sha256(_ data: Data) -> String {
        SHA256.hash(data: data)
            .map { String(format: "%02x", $0) }
            .joined()
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
            upstreamModelID: testCase.upstreamModelID,
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
