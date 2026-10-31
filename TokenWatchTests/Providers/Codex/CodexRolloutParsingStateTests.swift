import Foundation
import Testing
@testable import TokenWatch

@Suite("CodexRolloutParsingState")
struct CodexRolloutParsingStateTests {
    /// 用明确的累计值、单次值与限额来源构造独立用量事件。
    private func snapshotRecord(
        total: Int,
        last: Int = 10,
        source: String,
        timestamp: Int
    ) throws -> CodexRecord {
        let json = #"{"timestamp":\#(timestamp),"type":"event_msg","payload":{"type":"token_count","info":{"total_token_usage":{"input_tokens":\#(total)},"last_token_usage":{"input_tokens":\#(last)}},"rate_limits":{"limit_id":"\#(source)"}}}"#
        return try JSONDecoder().decode(CodexRecord.self, from: Data(json.utf8))
    }

    @Test("同来源非相邻重发与跨来源相邻重发均跳过")
    func skipsSameSourceStaleAndAdjacentCrossSourceSnapshots() throws {
        var checkpoint = CodexParserCheckpoint.initial(sessionID: "session", replaySecond: nil)
        let events = [
            try snapshotRecord(total: 100, source: "codex", timestamp: 1),
            try snapshotRecord(total: 100, source: "spark", timestamp: 2),
            try snapshotRecord(total: 200, source: "spark", timestamp: 3),
            try snapshotRecord(total: 100, source: "codex", timestamp: 4),
            try snapshotRecord(total: 300, source: "codex", timestamp: 5),
        ]
        let entries = events.enumerated().compactMap { offset, record in
            checkpoint.consume(record, sourceOffset: UInt64(offset), pricingSpeed: .standard)?.entry
        }

        #expect(entries.count == 3)
        #expect(entries.compactMap(\.timestamp) == [1, 3, 5].map { Date(timeIntervalSince1970: Double($0)) })
    }

    @Test("跨来源的旧快照在计数重置后可成为合法新增请求")
    func doesNotGloballyDeduplicateSnapshotsAfterCounterReset() throws {
        var checkpoint = CodexParserCheckpoint.initial(sessionID: "session", replaySecond: nil)
        let events = [
            try snapshotRecord(total: 100, source: "codex", timestamp: 1),
            try snapshotRecord(total: 200, source: "spark", timestamp: 2),
            try snapshotRecord(total: 0, last: 0, source: "spark", timestamp: 3),
            try snapshotRecord(total: 200, source: "codex", timestamp: 4),
        ]
        let entries = events.enumerated().compactMap { offset, record in
            checkpoint.consume(record, sourceOffset: UInt64(offset), pricingSpeed: .standard)?.entry
        }

        #expect(entries.count == 3)
        #expect(entries.last?.timestamp == Date(timeIntervalSince1970: 4))
        #expect(entries.reduce(0) { $0 + $1.usage.aggregateTotalTokens } == 30)
    }

    @Test("total 或 last 任一变化时仍计入新增用量")
    func preservesRequestsWhenOnlyOneSnapshotComponentChanges() throws {
        var checkpoint = CodexParserCheckpoint.initial(sessionID: "session", replaySecond: nil)
        let events = [
            try snapshotRecord(total: 100, last: 10, source: "codex", timestamp: 1),
            try snapshotRecord(total: 100, last: 20, source: "codex", timestamp: 2),
            try snapshotRecord(total: 200, last: 20, source: "codex", timestamp: 3),
        ]
        let entries = events.enumerated().compactMap { offset, record in
            checkpoint.consume(record, sourceOffset: UInt64(offset), pricingSpeed: .standard)?.entry
        }

        #expect(entries.map { $0.usage.inputTokens } == [10, 20, 20])
    }

    @Test("缺少或空 total 时不能仅凭相同 last 丢弃请求", arguments: ["", #","total_token_usage":{}"#])
    func identicalLastOnlyRequestsArePreserved(totalField: String) throws {
        var checkpoint = CodexParserCheckpoint.initial(sessionID: "session", replaySecond: nil)
        let entries = try [1, 2].compactMap { timestamp in
            let json = #"{"timestamp":\#(timestamp),"type":"event_msg","payload":{"type":"token_count","info":{"last_token_usage":{"input_tokens":10}\#(totalField)}}}"#
            let record = try JSONDecoder().decode(CodexRecord.self, from: Data(json.utf8))
            return checkpoint.consume(record, sourceOffset: UInt64(timestamp), pricingSpeed: .standard)?.entry
        }

        #expect(entries.count == 2)
        #expect(entries.reduce(0) { $0 + $1.usage.aggregateTotalTokens } == 20)
    }

    @Test("checkpoint 跨进程恢复后仍记住各来源和相邻快照")
    func snapshotDeduplicationSurvivesCheckpointRoundTrip() throws {
        var checkpoint = CodexParserCheckpoint.initial(sessionID: "session", replaySecond: nil)
        for (offset, source) in ["codex", "spark"].enumerated() {
            let record = try snapshotRecord(total: (offset + 1) * 100, source: source, timestamp: offset + 1)
            #expect(checkpoint.consume(record, sourceOffset: UInt64(offset), pricingSpeed: .standard) != nil)
        }
        var restored = try JSONDecoder().decode(
            CodexParserCheckpoint.self,
            from: JSONEncoder().encode(checkpoint)
        )
        let adjacent = try snapshotRecord(total: 200, source: "other", timestamp: 3)
        let stale = try snapshotRecord(total: 100, source: "codex", timestamp: 4)

        #expect(restored.consume(adjacent, sourceOffset: 3, pricingSpeed: .standard) == nil)
        #expect(restored.consume(stale, sourceOffset: 4, pricingSpeed: .standard) == nil)
    }

    @Test func checkpointRestoresModelSessionAndPreviousTotals() throws {
        let decoder = JSONDecoder()
        var checkpoint = CodexParserCheckpoint.initial(
            sessionID: "file-session",
            replaySecond: nil
        )
        let pricingSpeed = CodexPricingSpeed.standard
        let lines = [
            #"{"timestamp":"2026-05-04T08:35:44Z","type":"session_meta","payload":{"id":"meta-session","cwd":"/tmp/project","model_provider":"openai"}}"#,
            #"{"timestamp":"2026-05-04T08:35:45Z","type":"turn_context","payload":{"model":"gpt-5.4"}}"#,
            #"{"timestamp":"2026-05-04T08:35:46Z","type":"event_msg","payload":{"type":"token_count","info":{"total_token_usage":{"input_tokens":1000,"cached_input_tokens":300,"output_tokens":200,"reasoning_output_tokens":0,"total_tokens":1200}}}}"#
        ]
        let firstCandidates = try lines.enumerated().compactMap { index, line -> CodexUsageCandidate? in
            let record = try decoder.decode(CodexRecord.self, from: Data(line.utf8))
            return checkpoint.consume(
                record,
                sourceOffset: UInt64(index),
                pricingSpeed: pricingSpeed
            )
        }
        #expect(firstCandidates.count == 1)

        var restored = checkpoint
        let next = #"{"timestamp":"2026-05-04T08:36:00Z","type":"event_msg","payload":{"type":"token_count","info":{"total_token_usage":{"input_tokens":1600,"cached_input_tokens":500,"output_tokens":260,"reasoning_output_tokens":0,"total_tokens":1860}}}}"#
        let record = try decoder.decode(CodexRecord.self, from: Data(next.utf8))
        let entry = try #require(
            restored.consume(
                record,
                sourceOffset: 3,
                pricingSpeed: pricingSpeed
            )?.entry
        )

        #expect(entry.sessionID == "meta-session")
        #expect(entry.cwd == "/tmp/project")
        #expect(entry.model == "gpt-5.4")
        #expect(entry.usage.inputTokens == 400)
        #expect(entry.usage.cacheReadInputTokens == 200)
        #expect(entry.usage.outputTokens == 60)
        #expect(entry.messageId == "meta-session:2026-05-04T08:36:00.000Z")
        #expect(entry.recordUUID == "meta-session:2026-05-04T08:36:00.000Z:3")
    }

    @Test("checkpoint 可跨进程编码并恢复")
    func checkpointRoundTripsThroughCodable() throws {
        let decoder = JSONDecoder()
        var checkpoint = CodexParserCheckpoint.initial(
            sessionID: "file-session",
            replaySecond: "2026-05-04T08:35:46"
        )
        let lines = [
            #"{"timestamp":"2026-05-04T08:35:44Z","type":"session_meta","payload":{"id":"meta-session","cwd":"/tmp/project"}}"#,
            #"{"timestamp":"2026-05-04T08:35:45Z","type":"turn_context","payload":{"model":"gpt-5.4"}}"#,
            #"{"timestamp":"2026-05-04T08:35:46Z","type":"event_msg","payload":{"type":"token_count","info":{"total_token_usage":{"input_tokens":100,"cached_input_tokens":20,"output_tokens":10,"total_tokens":110}}}}"#,
            #"{"timestamp":"2026-05-04T08:35:47Z","type":"event_msg","payload":{"type":"token_count","info":{"total_token_usage":{"input_tokens":150,"cached_input_tokens":30,"output_tokens":20,"total_tokens":170}}}}"#,
        ]
        for (index, line) in lines.enumerated() {
            let record = try decoder.decode(CodexRecord.self, from: Data(line.utf8))
            _ = checkpoint.consume(
                record,
                sourceOffset: UInt64(index),
                pricingSpeed: .standard
            )
        }

        let data = try JSONEncoder().encode(checkpoint)
        let restored = try decoder.decode(CodexParserCheckpoint.self, from: data)

        #expect(restored.currentModel == checkpoint.currentModel)
        #expect(restored.sessionID == checkpoint.sessionID)
        #expect(restored.cwd == checkpoint.cwd)
        #expect(restored.previousTotals == checkpoint.previousTotals)
        #expect(restored.replaySecond == checkpoint.replaySecond)
        #expect(restored.isSkippingReplay == checkpoint.isSkippingReplay)
    }

    @Test("紧凑 candidate 可回读并迁移 v2/v3 完整 entry")
    func compactCandidateRoundTripsAndMigratesLegacyPayload() throws {
        let timestamp = try #require(
            CodexNormalizedTimestamp.parse("2026-05-04T08:35:46.000Z")
        )
        let original = CodexUsageCandidate.make(
            sessionID: "session",
            timestamp: timestamp,
            sourceOffset: 42,
            model: "gpt-5.4",
            cwd: "/tmp/project",
            counts: CodexTokenCounts(
                inputTokens: 1_000,
                cachedInputTokens: 300,
                outputTokens: 200,
                reasoningOutputTokens: 50,
                totalTokens: 1_200
            ),
            pricingSpeed: .fast
        )
        let encoder = JSONEncoder()
        let decoder = JSONDecoder()

        let compactData = try encoder.encode(original)
        let compactJSON = try #require(
            String(data: compactData, encoding: .utf8)
        )
        #expect(!compactJSON.contains(#""entry""#))

        let roundTripped = try decoder.decode(
            CodexUsageCandidate.self,
            from: compactData
        )
        let legacyData = try encoder.encode(
            LegacyCodexUsageCandidateFixture(
                entry: original.entry,
                dedupKey: original.dedupKey
            )
        )
        let migrated = try decoder.decode(
            CodexUsageCandidate.self,
            from: legacyData
        )

        for candidate in [roundTripped, migrated] {
            let entry = candidate.entry
            #expect(candidate.dedupKey == original.dedupKey)
            #expect(entry.recordUUID == "session:2026-05-04T08:35:46.000Z:42")
            #expect(entry.messageId == "session:2026-05-04T08:35:46.000Z")
            #expect(entry.sessionID == "session")
            #expect(entry.timestamp == timestamp.date)
            #expect(entry.model == "gpt-5.4")
            #expect(entry.cwd == "/tmp/project")
            #expect(entry.usage.inputTokens == 700)
            #expect(entry.usage.cacheReadInputTokens == 300)
            #expect(entry.usage.outputTokens == 200)
            #expect(entry.usage.reasoningTokens == 50)
            #expect(entry.usage.serviceTier == "fast")
        }
    }

    @Test("checkpoint 保留 last-first、cached clamp 与 zero-model 顺序")
    func reducerPreservesLastUsageClampingAndZeroModelOrdering() throws {
        let decoder = JSONDecoder()
        var checkpoint = CodexParserCheckpoint.initial(
            sessionID: "session",
            replaySecond: nil
        )
        let turn = #"{"timestamp":"2026-05-04T08:35:44.000Z","type":"turn_context","payload":{"model":"gpt-5"}}"#
        let zero = #"{"timestamp":"2026-05-04T08:35:45.000Z","type":"event_msg","payload":{"type":"token_count","model":"gpt-5.5","info":{"last_token_usage":{"input_tokens":0,"cached_input_tokens":0,"output_tokens":0,"reasoning_output_tokens":0,"total_tokens":0}}}}"#
        let first = #"{"timestamp":"2026-05-04T08:35:46.000Z","type":"event_msg","payload":{"type":"token_count","info":{"total_token_usage":{"input_tokens":100,"cached_input_tokens":150,"output_tokens":1,"reasoning_output_tokens":0,"total_tokens":101},"last_token_usage":{"input_tokens":100,"cached_input_tokens":150,"output_tokens":1,"reasoning_output_tokens":0,"total_tokens":101}}}}"#
        let repeated = first.replacingOccurrences(
            of: "08:35:46.000Z",
            with: "08:35:47.000Z"
        )
        for (offset, line) in [turn, zero].enumerated() {
            let record = try decoder.decode(CodexRecord.self, from: Data(line.utf8))
            let candidate = checkpoint.consume(
                record,
                sourceOffset: UInt64(offset),
                pricingSpeed: .standard
            )
            #expect(candidate?.entry == nil)
        }
        let firstRecord = try decoder.decode(CodexRecord.self, from: Data(first.utf8))
        let repeatedRecord = try decoder.decode(CodexRecord.self, from: Data(repeated.utf8))
        let emitted = [
            checkpoint.consume(firstRecord, sourceOffset: 2, pricingSpeed: .standard),
            checkpoint.consume(repeatedRecord, sourceOffset: 3, pricingSpeed: .standard),
        ].compactMap { $0?.entry }

        #expect(emitted.count == 1)
        #expect(emitted.allSatisfy { $0.model == "gpt-5" })
        #expect(emitted.allSatisfy { $0.usage.inputTokens == 0 })
        #expect(emitted.allSatisfy { $0.usage.cacheReadInputTokens == 100 })
    }

    @Test("Codex fast 只写 serviceTier，不污染 Claude usage.speed")
    func pricingSpeedMapsOnlyToServiceTier() throws {
        let decoder = JSONDecoder()
        var checkpoint = CodexParserCheckpoint.initial(
            sessionID: "session",
            replaySecond: nil
        )
        let turn = #"{"timestamp":"2026-05-04T08:35:44.000Z","type":"turn_context","payload":{"model":"gpt-5.4"}}"#
        let event = #"{"timestamp":"2026-05-04T08:35:46.000Z","type":"event_msg","payload":{"type":"token_count","info":{"last_token_usage":{"input_tokens":100,"cached_input_tokens":20,"output_tokens":1,"reasoning_output_tokens":0,"total_tokens":101}}}}"#
        let turnRecord = try decoder.decode(CodexRecord.self, from: Data(turn.utf8))
        let eventRecord = try decoder.decode(CodexRecord.self, from: Data(event.utf8))
        _ = checkpoint.consume(
            turnRecord,
            sourceOffset: 0,
            pricingSpeed: .fast
        )
        let entry = try #require(checkpoint.consume(
            eventRecord,
            sourceOffset: 1,
            pricingSpeed: .fast
        )?.entry)

        #expect(entry.usage.serviceTier == "fast")
        #expect(entry.usage.speed.isEmpty)
    }

    @Test("session token_count 缺 timestamp 不使用 offset 计费")
    func missingTimestampIsSkipped() throws {
        let decoder = JSONDecoder()
        var checkpoint = CodexParserCheckpoint.initial(
            sessionID: "session",
            replaySecond: nil
        )
        let line = #"{"type":"event_msg","payload":{"type":"token_count","model":"gpt-5","info":{"last_token_usage":{"input_tokens":10,"output_tokens":1}}}}"#
        let record = try decoder.decode(CodexRecord.self, from: Data(line.utf8))

        #expect(checkpoint.consume(
            record,
            sourceOffset: 99,
            pricingSpeed: .standard
        )?.entry == nil)
    }

    @Test("坏 timestamp 仍推进 total baseline，且不更新模型")
    func invalidTimestampAdvancesTotalBaselineWithoutUpdatingModel() throws {
        let decoder = JSONDecoder()

        func finalEntry(
            invalidTotal: Int,
            finalTotal: Int
        ) throws -> ParsedUsageEntry {
            var checkpoint = CodexParserCheckpoint.initial(
                sessionID: "session",
                replaySecond: nil
            )
            let lines = [
                #"{"timestamp":"2026-05-04T08:35:46Z","type":"event_msg","payload":{"type":"token_count","model":"gpt-5.4","info":{"total_token_usage":{"input_tokens":100,"total_tokens":100}}}}"#,
                #"{"timestamp":"not-a-date","type":"event_msg","payload":{"type":"token_count","model":"gpt-5.5","info":{"total_token_usage":{"input_tokens":\#(invalidTotal),"total_tokens":\#(invalidTotal)}}}}"#,
                #"{"timestamp":"2026-05-04T08:35:48Z","type":"event_msg","payload":{"type":"token_count","info":{"total_token_usage":{"input_tokens":\#(finalTotal),"total_tokens":\#(finalTotal)}}}}"#,
            ]
            let candidates = try lines.enumerated().compactMap { index, line in
                let record = try decoder.decode(CodexRecord.self, from: Data(line.utf8))
                return checkpoint.consume(
                    record,
                    sourceOffset: UInt64(index),
                    pricingSpeed: .standard
                )?.entry
            }

            #expect(candidates.count == 2)
            return try #require(candidates.last)
        }

        let increasing = try finalEntry(invalidTotal: 200, finalTotal: 250)
        #expect(increasing.usage.inputTokens == 50)
        #expect(increasing.model == "gpt-5.4")

        let reset = try finalEntry(invalidTotal: 20, finalTotal: 50)
        #expect(reset.usage.inputTokens == 30)
        #expect(reset.model == "gpt-5.4")
    }
}

private struct LegacyCodexUsageCandidateFixture: Encodable {
    let entry: ParsedUsageEntry
    let dedupKey: CodexEventDedupKey
}
