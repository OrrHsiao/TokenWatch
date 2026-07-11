import Foundation
import Testing
@testable import TokenWatch

@Suite("CodexRolloutParsingState")
struct CodexRolloutParsingStateTests {
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

    @Test("checkpoint 保留 last-first、cached clamp 与 zero-model 顺序")
    func reducerMatchesPinnedOrdering() throws {
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

        #expect(emitted.count == 2)
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
