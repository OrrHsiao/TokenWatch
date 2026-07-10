import Foundation
import Testing
@testable import TokenWatch

@Suite("ClaudeUsageDeduplicator")
struct ClaudeUsageDeduplicatorTests {
    @Test("两个非 sidechain 且 requestId 不同的父记录都保留")
    func keepsDistinctParentRequests() {
        let first = entry(record: "parent-a", request: "req-a", input: 10)
        let second = entry(record: "parent-b", request: "req-b", input: 20)

        let result = ClaudeUsageDeduplicator.deduplicate([first, second])

        #expect(ParsedUsageEntryDeepSnapshot.sorted(result) ==
            ParsedUsageEntryDeepSnapshot.sorted([first, second]))
    }

    @Test("同 messageId 的 sidechain replay 与父记录合并且父记录优先")
    func parentWinsAcrossSidechainReplay() {
        let sidechain = entry(
            record: "side",
            request: "req-side",
            input: 9_000,
            isSidechain: true
        )
        let parent = entry(record: "parent", request: "req-parent", input: 10)

        let forward = ClaudeUsageDeduplicator.deduplicate([sidechain, parent])
        let reverse = ClaudeUsageDeduplicator.deduplicate([parent, sidechain])

        #expect(ParsedUsageEntryDeepSnapshot.sorted(forward) ==
            ParsedUsageEntryDeepSnapshot.sorted([parent]))
        #expect(ParsedUsageEntryDeepSnapshot.sorted(reverse) ==
            ParsedUsageEntryDeepSnapshot.sorted([parent]))
    }

    @Test("同类 duplicate 依次比较 magnitude、Auto cost 和 speed")
    func sameClassUsesMagnitudeThenCostThenSpeedPresence() {
        let small = entry(record: "small", request: "same", input: 10)
        let large = entry(record: "large", request: "same", input: 20)
        let lowerCost = entry(
            record: "lower-cost",
            request: "cost-tie",
            input: 25,
            upstreamCost: 0.1
        )
        let higherCost = entry(
            record: "higher-cost",
            request: "cost-tie",
            input: 25,
            upstreamCost: 0.2
        )
        let standard = entry(record: "standard", request: "tie", input: 30)
        let fast = entry(record: "fast", request: "tie", input: 30, speed: "fast")

        let result = ClaudeUsageDeduplicator.deduplicate([
            small, large, lowerCost, higherCost, standard, fast,
        ])

        #expect(Set(result.map(\.recordUUID)) == Set(["large", "higher-cost", "fast"]))
    }

    @Test("exact duplicate 中 parent 优先于更大的 sidechain")
    func exactDuplicateStillUsesParentPriority() {
        let sidechain = entry(
            record: "side",
            request: "same",
            input: 1_000,
            isSidechain: true
        )
        let parent = entry(record: "parent", request: "same", input: 1)

        let result = ClaudeUsageDeduplicator.deduplicate([sidechain, parent])

        #expect(result.map(\.recordUUID) == ["parent"])
    }

    @Test("exact key 按字段比较，不被分隔符拼接碰撞")
    func exactKeyIsStructured() {
        let first = entry(
            record: "first",
            message: "a:b",
            request: "c",
            input: 10
        )
        let second = entry(
            record: "second",
            message: "a",
            request: "b:c",
            input: 20
        )

        #expect(ClaudeUsageDeduplicator.deduplicate([first, second]).count == 2)
    }

    @Test("daily 单遍索引保留 pinned replacement 边界")
    func sidechainReplacementDoesNotBackfillNewExactIndex() {
        let sidechain = entry(
            record: "side",
            request: "r1",
            input: 100,
            isSidechain: true
        )
        let parent = entry(record: "parent", request: "r2", input: 10)
        let repeatedParent = entry(record: "parent-repeat", request: "r2", input: 5)

        let result = ClaudeUsageDeduplicator.deduplicate([
            sidechain, parent, repeatedParent,
        ])

        #expect(result.map(\.recordUUID) == ["parent", "parent-repeat"])
    }

    @Test("缺 source message ID 完全绕过 exact 与 message 索引")
    func missingSourceMessageIDBypassesIndexes() {
        let synthetic = "missing-message:/tmp/same.jsonl:0"
        let first = entry(
            record: "missing-a",
            message: synthetic,
            request: "same",
            input: 10,
            hasSourceMessageID: false
        )
        let second = entry(
            record: "missing-b",
            message: synthetic,
            request: "same",
            input: 20,
            isSidechain: true,
            hasSourceMessageID: false
        )
        let real = entry(
            record: "real",
            message: synthetic,
            request: "same",
            input: 30
        )

        let result = ClaudeUsageDeduplicator.deduplicate([first, second, real])

        #expect(result.map(\.recordUUID) == ["missing-a", "missing-b", "real"])
    }

    @Test("极端 token magnitude 使用饱和求和而不溢出")
    func extremeMagnitudeDoesNotOverflow() {
        let smaller = entry(record: "smaller", request: "same", input: Int.max - 10)
        let larger = entry(record: "larger", request: "same", input: Int.max)

        let result = ClaudeUsageDeduplicator.deduplicate([smaller, larger])

        #expect(result.map(\.recordUUID) == ["larger"])
    }

    private func entry(
        record: String,
        message: String = "shared-message",
        request: String,
        input: Int,
        isSidechain: Bool = false,
        hasSourceMessageID: Bool = true,
        speed: String = "",
        upstreamCost: Double? = nil
    ) -> ParsedUsageEntry {
        ParsedUsageEntry(
            recordUUID: record,
            messageId: message,
            requestId: request,
            sessionID: "session",
            timestamp: Date(timeIntervalSince1970: 1_800_000_000),
            model: "claude-sonnet-4-5",
            cwd: "/project",
            agentId: nil,
            usage: TokenUsage(
                inputTokens: input,
                cacheCreationInputTokens: 0,
                cacheReadInputTokens: 0,
                outputTokens: 5,
                serverToolUse: ServerToolUse(webSearchRequests: 0, webFetchRequests: 0),
                serviceTier: "standard",
                cacheCreation: nil,
                inferenceGeo: "",
                iterations: [],
                speed: speed
            ),
            isSubagent: false,
            isSidechain: isSidechain,
            hasSourceMessageID: hasSourceMessageID,
            provider: .claude,
            upstreamProviderID: nil,
            upstreamCost: upstreamCost
        )
    }
}
