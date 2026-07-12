import Foundation
import Testing
@testable import TokenWatch

@Suite("ParsedUsageEntryDeepSnapshot")
struct ParsedUsageEntryDeepSnapshotTests {
    @Test("upstreamModelID 不同的条目快照不相等")
    func upstreamModelIDParticipatesInEquality() {
        let first = entry(upstreamModelID: "claude-sonnet-4-5")
        let second = entry(upstreamModelID: "claude-opus-4-6")

        #expect(ParsedUsageEntryDeepSnapshot(first) != ParsedUsageEntryDeepSnapshot(second))
    }

    private func entry(upstreamModelID: String) -> ParsedUsageEntry {
        ParsedUsageEntry(
            recordUUID: "record",
            messageId: "message",
            requestId: "request",
            sessionID: "session",
            timestamp: Date(timeIntervalSince1970: 1_800_000_000),
            model: "display-model",
            upstreamModelID: upstreamModelID,
            cwd: "/project",
            agentId: nil,
            usage: usage,
            isSubagent: false,
            provider: .opencode,
            upstreamProviderID: "anthropic",
            upstreamCost: nil
        )
    }

    private var usage: TokenUsage {
        TokenUsage(
            inputTokens: 10,
            cacheCreationInputTokens: 0,
            cacheReadInputTokens: 0,
            outputTokens: 5,
            serverToolUse: ServerToolUse(webSearchRequests: 0, webFetchRequests: 0),
            serviceTier: "standard",
            cacheCreation: nil,
            inferenceGeo: "",
            iterations: [],
            speed: ""
        )
    }
}
