import Foundation
import Testing
@testable import TokenWatch

/// JSONL 解析器测试
/// 验证 JSONL 解析和 messageId[:requestId] 去重逻辑
struct ClaudeJSONLParserTests {

    let parser = ClaudeJSONLParser()
    private static let advisorLine = #"{"timestamp":"2026-06-13T12:00:00Z","message":{"id":"a","usage":{"input_tokens":1,"output_tokens":1,"iterations":[{"type":"advisor_message","model":"m","input_tokens":2,"output_tokens":1}]}}}"#

    // MARK: - 解析

    @Test("解析包含 usage 的 assistant 记录")
    func parseAssistantWithUsage() throws {
        let jsonl = """
        {"type":"assistant","uuid":"u1","sessionId":"s1","timestamp":"2026-06-13T11:55:26.715Z","requestId":"req-1","message":{"id":"m1","role":"assistant","model":"deepseek-v4-pro","content":[{"type":"text","text":"Hello"}],"stop_reason":"end_turn","usage":{"input_tokens":100,"cache_creation_input_tokens":0,"cache_read_input_tokens":200,"output_tokens":50,"server_tool_use":{"web_search_requests":0,"web_fetch_requests":0},"service_tier":"standard","cache_creation":{"ephemeral_1h_input_tokens":0,"ephemeral_5m_input_tokens":0},"inference_geo":"","iterations":[],"speed":"standard"}}}
        """

        let tmpDir = FileManager.default.temporaryDirectory
        let fileURL = tmpDir.appendingPathComponent("test.jsonl")
        try jsonl.write(to: fileURL, atomically: true, encoding: .utf8)

        let fileInfo = ClaudeJSONLFileInfo(
            url: fileURL,
            sessionID: "s1",
            projectPath: "/test",
            isSubagent: false,
            agentId: nil
        )

        let entries = try parser.parseJSONLFile(fileInfo, claudeDataRoot: tmpDir)

        #expect(entries.count == 1)
        #expect(entries[0].model == "deepseek-v4-pro")
        #expect(entries[0].usage.inputTokens == 100)
        #expect(entries[0].usage.outputTokens == 50)
        #expect(entries[0].sessionID == "s1")
        #expect(entries[0].messageId == "m1")
        #expect(entries[0].requestId == "req-1")
        #expect(entries[0].dedupKey == "m1:req-1")

        try? FileManager.default.removeItem(at: fileURL)
    }

    @Test("跳过不含 usage 的记录")
    func skipNonUsageRecords() throws {
        let jsonl = """
        {"type":"user","uuid":"u2","sessionId":"s1","timestamp":"2026-06-13T12:00:00Z","message":{"id":"m2","role":"user","content":[{"type":"text","text":"Hi"}]}}
        {"type":"system","uuid":"u3","sessionId":"s1","subtype":"hook"}
        {"type":"assistant","uuid":"u4","sessionId":"s1","timestamp":"2026-06-13T12:01:00Z","message":{"id":"m3","role":"assistant","model":"deepseek-v4-pro","content":[{"type":"text","text":"Hello"}],"stop_reason":"end_turn","usage":{"input_tokens":50,"cache_creation_input_tokens":0,"cache_read_input_tokens":0,"output_tokens":25,"server_tool_use":{"web_search_requests":0,"web_fetch_requests":0},"service_tier":"standard","cache_creation":{"ephemeral_1h_input_tokens":0,"ephemeral_5m_input_tokens":0},"inference_geo":"","iterations":[],"speed":"standard"}}}
        """

        let tmpDir = FileManager.default.temporaryDirectory
        let fileURL = tmpDir.appendingPathComponent("test2.jsonl")
        try jsonl.write(to: fileURL, atomically: true, encoding: .utf8)

        let fileInfo = ClaudeJSONLFileInfo(
            url: fileURL,
            sessionID: "s1",
            projectPath: "/test",
            isSubagent: false,
            agentId: nil
        )

        let entries = try parser.parseJSONLFile(fileInfo, claudeDataRoot: tmpDir)

        // 只有 assistant 记录被解析
        #expect(entries.count == 1)
        #expect(entries[0].usage.inputTokens == 50)
        #expect(entries[0].messageId == "m3")
        #expect(entries[0].requestId == nil)
        #expect(entries[0].dedupKey == "m3")

        try? FileManager.default.removeItem(at: fileURL)
    }

    @Test("保留缺失 model 的 usage 记录并映射为空字符串")
    func keepsUsageWithoutModel() throws {
        let jsonl = """
        {"type":"assistant","uuid":"u5","sessionId":"s1","timestamp":"2026-06-13T12:00:00Z","message":{"id":"m4","role":"assistant","content":[{"type":"text","text":"No model"}],"usage":{"input_tokens":10,"cache_creation_input_tokens":0,"cache_read_input_tokens":0,"output_tokens":5,"server_tool_use":{"web_search_requests":0,"web_fetch_requests":0},"service_tier":"standard","cache_creation":{"ephemeral_1h_input_tokens":0,"ephemeral_5m_input_tokens":0},"inference_geo":"","iterations":[],"speed":"standard"}}}
        """

        let tmpDir = FileManager.default.temporaryDirectory
        let fileURL = tmpDir.appendingPathComponent("test3.jsonl")
        try jsonl.write(to: fileURL, atomically: true, encoding: .utf8)

        let fileInfo = ClaudeJSONLFileInfo(
            url: fileURL,
            sessionID: "s1",
            projectPath: "/test",
            isSubagent: false,
            agentId: nil
        )

        let entries = try parser.parseJSONLFile(fileInfo, claudeDataRoot: tmpDir)

        #expect(entries.count == 1)
        #expect(entries.first?.model == "")

        let emptyKeyPricing = ModelPricing(
            modelID: "empty",
            displayName: "empty",
            inputPrice: 1,
            outputPrice: 4,
            cacheReadPrice: 0.1,
            cacheWritePrice: 1.25
        )
        let table = PricingTable(
            liteLLMEntries: [
                "": CatalogPricingEntry(
                    pricing: emptyKeyPricing,
                    explicitFastMultiplier: nil
                ),
            ],
            modelsDevEntries: [:],
            builtins: [:]
        )
        let resolver = UsageCostResolver(
            pricingEngine: PricingEngine(pricingTable: table)
        )
        #expect(resolver.resolvedCost(for: try #require(entries.first)) == 0)

        try? FileManager.default.removeItem(at: fileURL)
    }

    @Test("Claude 顶层 costUSD 正数和显式零原样传播")
    func propagatesCostUSDIncludingZero() throws {
        let lines = [
            #"{"type":"assistant","uuid":"u1","sessionId":"s1","timestamp":"2026-06-13T12:00:00Z","costUSD":0.123,"message":{"id":"m1","role":"assistant","model":"claude-sonnet-4-5","usage":{"input_tokens":1,"output_tokens":1}}}"#,
            #"{"type":"assistant","uuid":"u2","sessionId":"s1","timestamp":"2026-06-13T12:01:00Z","costUSD":0,"message":{"id":"m2","role":"assistant","model":"claude-sonnet-4-5","usage":{"input_tokens":1,"output_tokens":1}}}"#,
        ]
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("ClaudeCostUSD-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let url = dir.appendingPathComponent("cost.jsonl")
        try (lines.joined(separator: "\n") + "\n").write(
            to: url,
            atomically: true,
            encoding: .utf8
        )
        let info = ClaudeJSONLFileInfo(
            url: url,
            sessionID: "s1",
            projectPath: "/tmp",
            isSubagent: false,
            agentId: nil
        )

        let entries = try ClaudeJSONLParser()
            .parseJSONLFile(info, claudeDataRoot: dir)
            .sorted { $0.messageId < $1.messageId }

        #expect(entries.map(\.upstreamCost) == [0.123, 0])
    }

    @Test("direct 与 AgentProgress usage 按 daily.rs 归一化")
    func directAndAgentProgressUsageAreBothCounted() throws {
        let direct = #"{"timestamp":"2026-06-13T12:00:00Z","costUSD":0.125,"message":{"usage":{"input_tokens":10,"output_tokens":2}}}"#
        let agentProgress = #"{"data":{"message":{"timestamp":"2026-06-13T12:00:01Z","requestId":"req-agent","isSidechain":true,"costUSD":0.25,"message":{"id":"agent-message","model":"claude-sonnet-4-5","usage":{"input_tokens":20,"output_tokens":3}}}}}"#
        let (file, root, cleanup) = try makeClaudeJSONL([direct, agentProgress])
        defer { cleanup() }

        let entries = try ClaudeJSONLParser().parseJSONLFile(file, claudeDataRoot: root)
            .sorted { ($0.timestamp ?? .distantPast) < ($1.timestamp ?? .distantPast) }

        #expect(entries.count == 2)
        #expect(entries[0].messageId.hasPrefix("missing-message:"))
        #expect(!entries[0].hasSourceMessageID)
        #expect(entries[0].model == "")
        #expect(entries[0].upstreamCost == 0.125)
        #expect(entries[1].messageId == "agent-message")
        #expect(entries[1].requestId == "req-agent")
        #expect(entries[1].isSidechain)
        #expect(entries[1].upstreamCost == 0.25)
    }

    @Test("direct 保留顶层 metadata，AgentProgress 只保留内层字段")
    func envelopeMetadataPropagationMatchesDailyAdapter() throws {
        let direct = #"{"uuid":"direct-record","sessionId":"direct-session","cwd":"/direct","version":"1.2.3","timestamp":"2026-06-13T12:00:00Z","requestId":"direct-request","isSidechain":true,"costUSD":0.1,"message":{"id":"direct-message","model":"claude-sonnet-4-5","usage":{"input_tokens":1,"output_tokens":1}}}"#
        let agentProgress = #"{"uuid":"outer-record","sessionId":"outer-session","cwd":"/outer","version":"dev-build","requestId":"outer-request","isSidechain":false,"costUSD":9,"data":{"message":{"timestamp":"2026-06-13T12:00:01Z","requestId":"inner-request","isSidechain":true,"costUSD":0.2,"message":{"id":"inner-message","model":"claude-sonnet-4-5","usage":{"input_tokens":2,"output_tokens":1}}}}}"#
        let (file, root, cleanup) = try makeClaudeJSONL([direct, agentProgress])
        defer { cleanup() }

        let entries = try ClaudeJSONLParser().parseJSONLFile(file, claudeDataRoot: root)
            .sorted { $0.messageId < $1.messageId }

        #expect(entries.count == 2)
        #expect(entries[0].recordUUID == "direct-record")
        #expect(entries[0].sessionID == "direct-session")
        #expect(entries[0].cwd == "/direct")
        #expect(entries[0].requestId == "direct-request")
        #expect(entries[0].isSidechain)
        #expect(entries[0].upstreamCost == 0.1)
        #expect(entries[1].recordUUID.hasPrefix("missing-record:"))
        #expect(entries[1].sessionID == file.sessionID)
        #expect(entries[1].cwd == nil)
        #expect(entries[1].requestId == "inner-request")
        #expect(entries[1].isSidechain)
        #expect(entries[1].upstreamCost == 0.2)
    }

    @Test("Claude advisor 展开为独立 entry 并按自身模型计价")
    func expandsAdvisorUsageWithInheritedMetadataAndLocalCost() throws {
        let line = #"{"type":"assistant","uuid":"main-record","sessionId":"main-session","timestamp":"2026-06-13T12:00:00.000Z","requestId":"main-request","isSidechain":true,"cwd":"/main-project","costUSD":1.23,"message":{"id":"main-message","model":"claude-sonnet-4-5","usage":{"input_tokens":1,"output_tokens":1,"iterations":[{"type":"tool_result","model":"ignored","input_tokens":99,"output_tokens":99},{"type":"advisor_message","model":"claude-3-5-haiku-20241022","input_tokens":10,"output_tokens":2},{"type":"advisor_message","model":"","input_tokens":50,"output_tokens":5}]}}}"#
        let (file, root, cleanup) = try makeClaudeJSONL([line])
        defer { cleanup() }

        let entries = try ClaudeJSONLParser().parseJSONLFile(file, claudeDataRoot: root)
        let main = try #require(entries.first { $0.messageId == "main-message" })
        let advisor = try #require(entries.first {
            $0.messageId == "main-message:advisor:0"
        })

        #expect(entries.count == 2)
        #expect(main.recordUUID == "main-record")
        #expect(main.upstreamCost == 1.23)
        #expect(advisor.recordUUID == "main-record:advisor:0")
        #expect(advisor.model == "claude-3-5-haiku-20241022")
        #expect(advisor.usage.inputTokens == 10)
        #expect(advisor.usage.outputTokens == 2)
        #expect(advisor.sessionID == "main-session")
        #expect(advisor.requestId == "main-request")
        #expect(advisor.timestamp == main.timestamp)
        #expect(advisor.cwd == "/main-project")
        #expect(advisor.isSidechain)
        #expect(advisor.hasSourceMessageID)
        #expect(advisor.upstreamCost == nil)
        #expect(abs(UsageCostResolver().resolvedCost(for: advisor) - 0.000016) < 1e-12)
    }

    @Test("损坏 advisor envelope 只丢 advisors 不丢合法主记录")
    func malformedAdvisorDoesNotRejectMainUsage() throws {
        let valid = #"{"uuid":"valid-record","timestamp":"2026-06-13T12:00:00.000Z","message":{"id":"valid-main","model":"claude-sonnet-4-5","usage":{"input_tokens":1,"output_tokens":1,"iterations":[{"type":"advisor_message","model":"claude-3-5-haiku-20241022","input_tokens":10,"output_tokens":2}]}}}"#
        let malformed = #"{"uuid":"malformed-record","timestamp":"2026-06-13T12:01:00.000Z","message":{"id":"malformed-main","model":"claude-sonnet-4-5","usage":{"input_tokens":3,"output_tokens":1,"iterations":[{"type":"advisor_message","model":"claude-3-5-haiku-20241022","input_tokens":5,"output_tokens":1},{"type":"advisor_message","model":"claude-3-5-haiku-20241022","input_tokens":10,"output_tokens":"bad"}]}}}"#
        let (file, root, cleanup) = try makeClaudeJSONL([valid, malformed])
        defer { cleanup() }

        let entries = try ClaudeJSONLParser().parseJSONLFile(file, claudeDataRoot: root)

        #expect(entries.count == 3)
        #expect(Set(entries.map(\.messageId)) == [
            "valid-main",
            "valid-main:advisor:0",
            "malformed-main",
        ])
        #expect(entries.first { $0.messageId == "malformed-main" }?.usage.inputTokens == 3)
    }

    @Test("advisor 内 unsupported compact null 仍触发 pinned raw guard")
    func advisorCompactNullPreservesWholeLineGuard() throws {
        let line = #"{"timestamp":"2026-06-13T12:02:00.000Z","message":{"id":"guarded-main","model":"claude-sonnet-4-5","usage":{"input_tokens":7,"output_tokens":1,"iterations":[{"type":"advisor_message","model":"claude-3-5-haiku-20241022","input_tokens":5,"output_tokens":1,"cache_read_input_tokens":null}]}}}"#
        let (file, root, cleanup) = try makeClaudeJSONL([line])
        defer { cleanup() }

        #expect(try ClaudeJSONLParser()
            .parseJSONLFile(file, claudeDataRoot: root)
            .isEmpty)
    }

    @Test("iteration 缺 type 使整份 advisor envelope 失效但保留 main")
    func missingIterationTypeRejectsAllAdvisorsOnly() throws {
        let line = #"{"timestamp":"2026-06-13T12:03:00.000Z","message":{"id":"missing-type-main","model":"claude-sonnet-4-5","usage":{"input_tokens":1,"output_tokens":1,"iterations":[{"type":"advisor_message","model":"m","input_tokens":2,"output_tokens":1},{"model":"m","input_tokens":3,"output_tokens":1}]}}}"#
        let (file, root, cleanup) = try makeClaudeJSONL([line])
        defer { cleanup() }

        let entries = try ClaudeJSONLParser().parseJSONLFile(file, claudeDataRoot: root)

        #expect(entries.map(\.messageId) == ["missing-type-main"])
    }

    @Test("普通 iteration 坏 token 也使整份 advisor envelope 失效")
    func malformedNonAdvisorIterationRejectsAllAdvisorsOnly() throws {
        let line = #"{"timestamp":"2026-06-13T12:04:00.000Z","message":{"id":"bad-normal-main","model":"claude-sonnet-4-5","usage":{"input_tokens":1,"output_tokens":1,"iterations":[{"type":"tool_result","model":"ignored","input_tokens":99,"output_tokens":"bad"},{"type":"advisor_message","model":"m","input_tokens":2,"output_tokens":1}]}}}"#
        let (file, root, cleanup) = try makeClaudeJSONL([line])
        defer { cleanup() }

        let entries = try ClaudeJSONLParser().parseJSONLFile(file, claudeDataRoot: root)

        #expect(entries.map(\.messageId) == ["bad-normal-main"])
    }

    @Test("重复 Claude 文件中的 main 与 advisor 都只保留一次")
    func duplicateFilesDeduplicateMainAndAdvisor() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("ClaudeAdvisorDuplicate-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let firstURL = root.appendingPathComponent("first.jsonl")
        let secondURL = root.appendingPathComponent("second.jsonl")
        try (Self.advisorLine + "\n").write(to: firstURL, atomically: true, encoding: .utf8)
        try (Self.advisorLine + "\n").write(to: secondURL, atomically: true, encoding: .utf8)
        let files = [firstURL, secondURL].map {
            ClaudeJSONLFileInfo(
                url: $0,
                sessionID: "file-session",
                projectPath: "/project",
                isSubagent: false,
                agentId: nil
            )
        }

        let entries = try ClaudeJSONLParser().parseAllFiles(files, claudeDataRoot: root)

        #expect(entries.map(\.messageId).sorted() == [
            "a",
            "a:advisor:0",
        ])
    }

    @Test("sidechain parent replacement 同时替换 main 与 advisor")
    func sidechainParentReplacesAdvisorPair() throws {
        let sidechain = #"{"uuid":"side-record","timestamp":"2026-06-13T12:00:00Z","requestId":"side","isSidechain":true,"message":{"id":"shared","usage":{"input_tokens":10,"output_tokens":1,"iterations":[{"type":"advisor_message","model":"m","input_tokens":20,"output_tokens":1}]}}}"#
        let parent = #"{"uuid":"parent-record","timestamp":"2026-06-13T12:00:01Z","requestId":"parent","isSidechain":false,"message":{"id":"shared","usage":{"input_tokens":1,"output_tokens":1,"iterations":[{"type":"advisor_message","model":"m","input_tokens":2,"output_tokens":1}]}}}"#
        let (file, root, cleanup) = try makeClaudeJSONL([sidechain, parent])
        defer { cleanup() }

        let entries = try ClaudeJSONLParser().parseAllFiles([file], claudeDataRoot: root)
        let main = try #require(entries.first { $0.messageId == "shared" })
        let advisor = try #require(entries.first {
            $0.messageId == "shared:advisor:0"
        })

        #expect(entries.count == 2)
        #expect(main.requestId == "parent")
        #expect(main.usage.inputTokens == 1)
        #expect(!main.isSidechain)
        #expect(advisor.requestId == "parent")
        #expect(advisor.usage.inputTokens == 2)
        #expect(!advisor.isSidechain)
    }

    @Test("advisor provisional、committed 与 fresh 解析深度一致")
    func advisorIncrementalLifecycleMatchesFreshParse() throws {
        let fixture = try makeClaudeFixture()
        defer { fixture.cleanup() }
        let reader = RecordingJSONLFileReader()
        let parser = ClaudeJSONLParser(fileReader: reader)
        try Self.advisorLine.write(
            to: fixture.file.url,
            atomically: false,
            encoding: .utf8
        )

        let provisional = try parser.parseAllFiles([fixture.file], claudeDataRoot: fixture.root)
        try appendUTF8("\n", to: fixture.file.url)
        let committed = try parser.parseAllFiles([fixture.file], claudeDataRoot: fixture.root)
        let committedOffset = UInt64((Self.advisorLine + "\n").utf8.count)
        #expect(committedOffset <= UInt64(JSONLContinuityAnchor.maximumByteCount))
        let next = Self.minimalAssistantLine(messageId: "after-advisor", inputTokens: 3)
        try appendUTF8(next + "\n", to: fixture.file.url)
        reader.resetMetrics()
        let incremental = try parser.parseAllFiles([fixture.file], claudeDataRoot: fixture.root)
        let fresh = try ClaudeJSONLParser().parseAllFiles(
            [fixture.file],
            claudeDataRoot: fixture.root
        )

        #expect(provisional.count == 2)
        #expect(ParsedUsageEntryDeepSnapshot.sorted(provisional)
                == ParsedUsageEntryDeepSnapshot.sorted(committed))
        #expect(incremental.count == 3)
        #expect(reader.seekOffsets == [0, committedOffset])
        #expect(ParsedUsageEntryDeepSnapshot.sorted(incremental)
                == ParsedUsageEntryDeepSnapshot.sorted(fresh))
    }

    @Test("optional 缺失可接受，显式空值与非 semver version 被过滤")
    func dailyPresenceValidationMatchesCCUsage() throws {
        let missingOptional = #"{"timestamp":"2026-06-13T12:00:00Z","message":{"usage":{"input_tokens":1,"output_tokens":1}}}"#
        let semverPrefix = #"{"timestamp":"2026-06-13T12:00:00Z","version":"1.2.3-dev","message":{"id":"valid-version","model":"claude-sonnet-4-5","usage":{"input_tokens":2,"output_tokens":1}}}"#
        let emptySession = #"{"timestamp":"2026-06-13T12:00:01Z","sessionId":"","message":{"id":"session","model":"claude-sonnet-4-5","usage":{"input_tokens":3,"output_tokens":1}}}"#
        let emptyRequest = #"{"timestamp":"2026-06-13T12:00:02Z","requestId":"","message":{"id":"request","model":"claude-sonnet-4-5","usage":{"input_tokens":4,"output_tokens":1}}}"#
        let emptyMessage = #"{"timestamp":"2026-06-13T12:00:03Z","message":{"id":"","model":"claude-sonnet-4-5","usage":{"input_tokens":5,"output_tokens":1}}}"#
        let emptyModel = #"{"timestamp":"2026-06-13T12:00:04Z","message":{"id":"model","model":"","usage":{"input_tokens":6,"output_tokens":1}}}"#
        let badVersion = #"{"timestamp":"2026-06-13T12:00:05Z","version":"dev-build","message":{"id":"version","model":"claude-sonnet-4-5","usage":{"input_tokens":7,"output_tokens":1}}}"#
        let (file, root, cleanup) = try makeClaudeJSONL([
            missingOptional, semverPrefix, emptySession, emptyRequest,
            emptyMessage, emptyModel, badVersion,
        ])
        defer { cleanup() }

        let entries = try ClaudeJSONLParser().parseJSONLFile(file, claudeDataRoot: root)

        #expect(entries.map(\.usage.inputTokens) == [1, 2])
        #expect(entries.first?.sessionID == file.sessionID)
        #expect(entries.first?.model == "")
        #expect(entries.first?.hasSourceMessageID == false)
    }

    @Test("daily raw prefilter 精确复制 usage marker 与 compact null guard")
    func dailyRawPrefilterMatchesCCUsage() throws {
        let compact = #"{"timestamp":"2026-06-13T12:00:00Z","message":{"id":"kept","model":"claude-sonnet-4-5","usage":{"input_tokens":1,"output_tokens":1}}}"#
        let spacedMarker = #"{"timestamp":"2026-06-13T12:00:01Z","costUSD":1,"message":{"id":"spaced","model":"claude-sonnet-4-5","usage": {"input_tokens":2,"output_tokens":1}}}"#
        let guardedNull = #"{"timestamp":"2026-06-13T12:00:02Z","costUSD":null,"message":{"id":"null","model":"claude-sonnet-4-5","usage":{"input_tokens":3,"output_tokens":1}}}"#
        let whitespaceNull = #"{"timestamp":"2026-06-13T12:00:03Z","costUSD": null,"message":{"id":"whitespace-null","model":"claude-sonnet-4-5","usage":{"input_tokens":4,"output_tokens":1}}}"#
        let (file, root, cleanup) = try makeClaudeJSONL([
            compact, spacedMarker, guardedNull, whitespaceNull,
        ])
        defer { cleanup() }

        let entries = try ClaudeJSONLParser().parseJSONLFile(file, claudeDataRoot: root)

        #expect(entries.map(\.messageId) == ["kept", "whitespace-null"])
    }

    @Test("daily billing DTO 严格限制 token 和 speed，忽略无关字段")
    func dailyBillingShapeIsStrictButNarrow() throws {
        let unrelatedGarbage = #"{"timestamp":"2026-06-13T12:00:00.000Z","message":{"id":"kept","model":"claude-sonnet-4-5","role":{"bad":true},"content":42,"usage":{"input_tokens":1,"output_tokens":1,"speed":"fast"}}}"#
        let standard = #"{"timestamp":"2026-06-13T12:00:01.000Z","message":{"id":"standard","model":"claude-sonnet-4-5","usage":{"input_tokens":1,"output_tokens":1,"speed":"standard"}}}"#
        let missingSpeed = #"{"timestamp":"2026-06-13T12:00:02.000Z","message":{"id":"missing-speed","model":"claude-sonnet-4-5","usage":{"input_tokens":1,"output_tokens":1}}}"#
        let negative = #"{"timestamp":"2026-06-13T12:00:03.000Z","message":{"id":"negative","model":"claude-sonnet-4-5","usage":{"input_tokens":-1,"output_tokens":1}}}"#
        let fractional = #"{"timestamp":"2026-06-13T12:00:04.000Z","message":{"id":"fractional","model":"claude-sonnet-4-5","usage":{"input_tokens":1.5,"output_tokens":1}}}"#
        let badSpeed = #"{"timestamp":"2026-06-13T12:00:05.000Z","message":{"id":"speed","model":"claude-sonnet-4-5","usage":{"input_tokens":1,"output_tokens":1,"speed":"turbo"}}}"#
        let (file, root, cleanup) = try makeClaudeJSONL([
            unrelatedGarbage, standard, missingSpeed, negative, fractional, badSpeed,
        ])
        defer { cleanup() }

        let entries = try ClaudeJSONLParser().parseJSONLFile(file, claudeDataRoot: root)

        #expect(entries.map(\.messageId) == ["kept", "standard", "missing-speed"])
        #expect(entries.map(\.usage.speed) == ["fast", "standard", ""])
    }

    @Test("daily timestamp 仅接受无小数或三位毫秒及 Z/offset")
    func dailyTimestampShapeMatchesCCUsage() throws {
        let accepted = [
            #"{"timestamp":"2026-06-13T12:00:00Z","message":{"id":"z-seconds","usage":{"input_tokens":1,"output_tokens":1}}}"#,
            #"{"timestamp":"2026-06-13T12:00:00.123Z","message":{"id":"z-millis","usage":{"input_tokens":1,"output_tokens":1}}}"#,
            #"{"timestamp":"2026-06-13T12:00:00+08:00","message":{"id":"offset-seconds","usage":{"input_tokens":1,"output_tokens":1}}}"#,
            #"{"timestamp":"2026-06-13T12:00:00.123-07:30","message":{"id":"offset-millis","usage":{"input_tokens":1,"output_tokens":1}}}"#,
            #"{"timestamp":"2026-06-13T12:00:00+23:59","message":{"id":"positive-max-offset","usage":{"input_tokens":1,"output_tokens":1}}}"#,
            #"{"timestamp":"2026-06-13T12:00:00-23:59","message":{"id":"negative-max-offset","usage":{"input_tokens":1,"output_tokens":1}}}"#,
            #"{"timestamp":"2026-06-13T12:00:00-00:00","message":{"id":"negative-zero-offset","usage":{"input_tokens":1,"output_tokens":1}}}"#,
        ]
        let rejected = [
            #"{"timestamp":"2026-06-13T12:00:00.1Z","message":{"id":"one-digit","usage":{"input_tokens":1,"output_tokens":1}}}"#,
            #"{"timestamp":"2026-06-13T12:00:00.123456Z","message":{"id":"six-digits","usage":{"input_tokens":1,"output_tokens":1}}}"#,
            #"{"timestamp":"2026-06-13T12:00:00+0800","message":{"id":"compact-offset","usage":{"input_tokens":1,"output_tokens":1}}}"#,
            #"{"timestamp":"2026-06-13T12:00:00+24:00","message":{"id":"positive-hour-overflow","usage":{"input_tokens":1,"output_tokens":1}}}"#,
            #"{"timestamp":"2026-06-13T12:00:00-24:00","message":{"id":"negative-hour-overflow","usage":{"input_tokens":1,"output_tokens":1}}}"#,
            #"{"timestamp":"2026-06-13T12:00:00+00:60","message":{"id":"positive-minute-overflow","usage":{"input_tokens":1,"output_tokens":1}}}"#,
            #"{"timestamp":"2026-06-13T12:00:00-00:60","message":{"id":"negative-minute-overflow","usage":{"input_tokens":1,"output_tokens":1}}}"#,
        ]
        let (file, root, cleanup) = try makeClaudeJSONL(accepted + rejected)
        defer { cleanup() }

        let entries = try ClaudeJSONLParser().parseJSONLFile(file, claudeDataRoot: root)

        #expect(Set(entries.map(\.messageId)) == Set([
            "z-seconds", "z-millis", "offset-seconds", "offset-millis",
            "positive-max-offset", "negative-max-offset", "negative-zero-offset",
        ]))

        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        func expectedDate(
            year: Int = 2026,
            month: Int = 6,
            day: Int,
            hour: Int,
            minute: Int,
            nanosecond: Int = 0
        ) throws -> Date {
            try #require(calendar.date(from: DateComponents(
                year: year,
                month: month,
                day: day,
                hour: hour,
                minute: minute,
                second: 0,
                nanosecond: nanosecond
            )))
        }
        func timestamp(for id: String) throws -> Date {
            try #require(entries.first { $0.messageId == id }?.timestamp)
        }

        #expect(abs(try timestamp(for: "offset-seconds").timeIntervalSince(
            expectedDate(day: 13, hour: 4, minute: 0)
        )) < 0.000_001)
        #expect(abs(try timestamp(for: "offset-millis").timeIntervalSince(
            expectedDate(day: 13, hour: 19, minute: 30, nanosecond: 123_000_000)
        )) < 0.000_001)
        #expect(abs(try timestamp(for: "positive-max-offset").timeIntervalSince(
            expectedDate(day: 12, hour: 12, minute: 1)
        )) < 0.000_001)
        #expect(abs(try timestamp(for: "negative-max-offset").timeIntervalSince(
            expectedDate(day: 14, hour: 11, minute: 59)
        )) < 0.000_001)
        #expect(abs(try timestamp(for: "negative-zero-offset").timeIntervalSince(
            expectedDate(day: 13, hour: 12, minute: 0)
        )) < 0.000_001)
    }

    @Test("cache breakdown 子字段缺失按零，显式 null 或负数使行失败")
    func cacheBreakdownPresenceMatchesTokenUsageRaw() throws {
        let flat = #"{"timestamp":"2026-06-13T12:00:00Z","message":{"id":"flat","usage":{"input_tokens":1,"output_tokens":1,"cache_creation_input_tokens":7}}}"#
        let partial = #"{"timestamp":"2026-06-13T12:00:01Z","message":{"id":"partial","usage":{"input_tokens":1,"output_tokens":1,"cache_creation_input_tokens":99,"cache_creation":{"ephemeral_5m_input_tokens":5}}}}"#
        let nullBreakdown = #"{"timestamp":"2026-06-13T12:00:02Z","message":{"id":"null-breakdown","usage":{"input_tokens":1,"output_tokens":1,"cache_creation_input_tokens":8,"cache_creation":null}}}"#
        let nullChild = #"{"timestamp":"2026-06-13T12:00:03Z","message":{"id":"null-child","usage":{"input_tokens":1,"output_tokens":1,"cache_creation":{"ephemeral_5m_input_tokens":null}}}}"#
        let negativeChild = #"{"timestamp":"2026-06-13T12:00:04Z","message":{"id":"negative-child","usage":{"input_tokens":1,"output_tokens":1,"cache_creation":{"ephemeral_1h_input_tokens":-1}}}}"#
        let (file, root, cleanup) = try makeClaudeJSONL([
            flat, partial, nullBreakdown, nullChild, negativeChild,
        ])
        defer { cleanup() }

        let entries = try ClaudeJSONLParser().parseJSONLFile(file, claudeDataRoot: root)

        #expect(entries.map(\.messageId) == ["flat", "partial", "null-breakdown"])
        #expect(entries[0].usage.cacheCreation == nil)
        #expect(entries[0].usage.totalCacheCreationTokens == 7)
        #expect(entries[1].usage.cacheCreation?.ephemeral5mInputTokens == 5)
        #expect(entries[1].usage.cacheCreation?.ephemeral1hInputTokens == 0)
        #expect(entries[1].usage.totalCacheCreationTokens == 5)
        #expect(entries[2].usage.cacheCreation == nil)
        #expect(entries[2].usage.totalCacheCreationTokens == 8)
    }

    @Test("synthetic record/message ID 使用 standardized path 与绝对字节 offset")
    func syntheticIDsAreStableAndOffsetBased() throws {
        let prefix = #"{"note":"é"}"#
        let usage = #"{"timestamp":"2026-06-13T12:00:00Z","message":{"usage":{"input_tokens":1,"output_tokens":1}}}"#
        let (file, root, cleanup) = try makeClaudeJSONL([prefix, usage])
        defer { cleanup() }
        let expectedOffset = (prefix + "\n").utf8.count
        let fileKey = file.url.standardizedFileURL.path

        let first = try ClaudeJSONLParser().parseJSONLFile(file, claudeDataRoot: root)
        let second = try ClaudeJSONLParser().parseJSONLFile(file, claudeDataRoot: root)

        #expect(first.count == 1)
        #expect(first[0].recordUUID == "missing-record:\(fileKey):\(expectedOffset)")
        #expect(first[0].messageId == "missing-message:\(fileKey):\(expectedOffset)")
        #expect(!first[0].hasSourceMessageID)
        #expect(ParsedUsageEntryDeepSnapshot.sorted(first) == ParsedUsageEntryDeepSnapshot.sorted(second))
    }

    // MARK: - 去重

    @Test("Set 去重 - 相同 messageId 只保留一条")
    func dedupWithSet() {
        let usage = TokenUsage(
            inputTokens: 100,
            cacheCreationInputTokens: 0,
            cacheReadInputTokens: 0,
            outputTokens: 50,
            serverToolUse: ServerToolUse(webSearchRequests: 0, webFetchRequests: 0),
            serviceTier: "standard",
            cacheCreation: CacheCreation(ephemeral1hInputTokens: 0, ephemeral5mInputTokens: 0),
            inferenceGeo: "",
            iterations: [],
            speed: "standard"
        )

        let entry1 = ParsedUsageEntry(
            recordUUID: "uuid-1", messageId: "msg-A", requestId: "req-1",
            sessionID: "s1", timestamp: Date(), model: "deepseek-v4-pro",
            cwd: "/test", agentId: nil, usage: usage, isSubagent: false,
            provider: .claude,
            upstreamProviderID: nil, upstreamCost: nil
        )
        let entry2 = ParsedUsageEntry(
            recordUUID: "uuid-2", messageId: "msg-A", requestId: "req-1",
            sessionID: "s1", timestamp: Date(), model: "deepseek-v4-pro",
            cwd: "/test", agentId: nil, usage: usage, isSubagent: false,
            provider: .claude,
            upstreamProviderID: nil, upstreamCost: nil
        )

        let unique = Array(Set([entry1, entry2]))
        #expect(unique.count == 1)
    }

    @Test("Set 不去重不同 messageId")
    func noDedupDifferentMessageIds() {
        let usage = TokenUsage(
            inputTokens: 100, cacheCreationInputTokens: 0, cacheReadInputTokens: 0,
            outputTokens: 50,
            serverToolUse: ServerToolUse(webSearchRequests: 0, webFetchRequests: 0),
            serviceTier: "standard",
            cacheCreation: CacheCreation(ephemeral1hInputTokens: 0, ephemeral5mInputTokens: 0),
            inferenceGeo: "", iterations: [], speed: "standard"
        )

        let entry1 = ParsedUsageEntry(
            recordUUID: "u1", messageId: "msg-A", requestId: nil,
            sessionID: "s1", timestamp: Date(), model: "deepseek-v4-pro",
            cwd: "/test", agentId: nil, usage: usage, isSubagent: false,
            provider: .claude,
            upstreamProviderID: nil, upstreamCost: nil
        )
        let entry2 = ParsedUsageEntry(
            recordUUID: "u2", messageId: "msg-B", requestId: nil,
            sessionID: "s1", timestamp: Date(), model: "deepseek-v4-pro",
            cwd: "/test", agentId: nil, usage: usage, isSubagent: false,
            provider: .claude,
            upstreamProviderID: nil, upstreamCost: nil
        )

        let unique = Array(Set([entry1, entry2]))
        #expect(unique.count == 2)
    }

    @Test("跨文件去重 - 同 messageId 在多个 JSONL 中只计一次")
    func dedupAcrossFiles() throws {
        // 模拟同一 message 因 sub-agent / resume 被写入两个 JSONL 的场景
        let line = """
        {"type":"assistant","uuid":"u1","sessionId":"s1","timestamp":"2026-06-13T11:55:26.715Z","message":{"id":"shared-msg","role":"assistant","model":"deepseek-v4-pro","content":[{"type":"text","text":"hi"}],"stop_reason":"end_turn","usage":{"input_tokens":100,"cache_creation_input_tokens":0,"cache_read_input_tokens":0,"output_tokens":50,"server_tool_use":{"web_search_requests":0,"web_fetch_requests":0},"service_tier":"standard","cache_creation":{"ephemeral_1h_input_tokens":0,"ephemeral_5m_input_tokens":0},"inference_geo":"","iterations":[],"speed":"standard"}}}
        """
        let tmpDir = FileManager.default.temporaryDirectory
        let f1 = tmpDir.appendingPathComponent("dup-a.jsonl")
        let f2 = tmpDir.appendingPathComponent("dup-b.jsonl")
        try line.write(to: f1, atomically: true, encoding: .utf8)
        try line.write(to: f2, atomically: true, encoding: .utf8)

        let infos = [
            ClaudeJSONLFileInfo(url: f1, sessionID: "s1", projectPath: "/p", isSubagent: false, agentId: nil),
            ClaudeJSONLFileInfo(url: f2, sessionID: "s1", projectPath: "/p", isSubagent: true,  agentId: "agent-1"),
        ]
        let entries = try parser.parseAllFiles(infos, claudeDataRoot: tmpDir)
        #expect(entries.count == 1)
        #expect(entries[0].messageId == "shared-msg")

        try? FileManager.default.removeItem(at: f1)
        try? FileManager.default.removeItem(at: f2)
    }

    @Test("文件级 subagent 不能替代记录级 sidechain")
    func subagentFileWithoutSidechainKeepsDistinctRequest() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("ClaudeSidechain-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let parentURL = dir.appendingPathComponent("parent.jsonl")
        let subagentURL = dir.appendingPathComponent("agent.jsonl")
        let parentLine = #"{"type":"assistant","uuid":"parent","sessionId":"s","timestamp":"2026-06-13T11:55:26.715Z","requestId":"req-parent","isSidechain":false,"message":{"id":"shared","role":"assistant","model":"claude-sonnet-4-5","usage":{"input_tokens":10,"output_tokens":5}}}"#
        let subagentLine = #"{"type":"assistant","uuid":"subagent","sessionId":"s","timestamp":"2026-06-13T11:55:27.715Z","requestId":"req-subagent","isSidechain":false,"message":{"id":"shared","role":"assistant","model":"claude-sonnet-4-5","usage":{"input_tokens":20,"output_tokens":5}}}"#
        try (parentLine + "\n").write(to: parentURL, atomically: true, encoding: .utf8)
        try (subagentLine + "\n").write(to: subagentURL, atomically: true, encoding: .utf8)
        let files = [
            ClaudeJSONLFileInfo(
                url: parentURL,
                sessionID: "s",
                projectPath: "/project",
                isSubagent: false,
                agentId: nil
            ),
            ClaudeJSONLFileInfo(
                url: subagentURL,
                sessionID: "s",
                projectPath: "/project",
                isSubagent: true,
                agentId: "agent"
            ),
        ]

        let entries = try ClaudeJSONLParser().parseAllFiles(files, claudeDataRoot: dir)

        #expect(entries.count == 2)
        #expect(entries.allSatisfy { !$0.isSidechain })
        #expect(entries.contains { $0.isSubagent })
    }

    @Test("记录级 sidechain replay 被父记录替换")
    func recordSidechainReplayIsReplacedByParent() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("ClaudeReplay-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let parentURL = dir.appendingPathComponent("parent.jsonl")
        let sidechainURL = dir.appendingPathComponent("sidechain.jsonl")
        let parentLine = #"{"type":"assistant","uuid":"parent","sessionId":"s","timestamp":"2026-06-13T11:55:26.715Z","requestId":"req-parent","isSidechain":false,"message":{"id":"shared","role":"assistant","model":"claude-sonnet-4-5","usage":{"input_tokens":10,"output_tokens":5}}}"#
        let sidechainLine = #"{"type":"assistant","uuid":"sidechain","sessionId":"s","timestamp":"2026-06-13T11:55:28.715Z","requestId":"req-sidechain","isSidechain":true,"message":{"id":"shared","role":"assistant","model":"claude-sonnet-4-5","usage":{"input_tokens":999,"output_tokens":5}}}"#
        try (parentLine + "\n").write(to: parentURL, atomically: true, encoding: .utf8)
        try (sidechainLine + "\n").write(to: sidechainURL, atomically: true, encoding: .utf8)
        let files = [
            ClaudeJSONLFileInfo(
                url: sidechainURL,
                sessionID: "s",
                projectPath: "/project",
                isSubagent: true,
                agentId: "agent"
            ),
            ClaudeJSONLFileInfo(
                url: parentURL,
                sessionID: "s",
                projectPath: "/project",
                isSubagent: false,
                agentId: nil
            ),
        ]

        let entries = try ClaudeJSONLParser().parseAllFiles(files, claudeDataRoot: dir)

        #expect(entries.count == 1)
        #expect(entries.first?.recordUUID == "parent")
        #expect(entries.first?.isSidechain == false)
    }

    @Test("per-file cache 保留 candidates 并在每次批量返回前执行单遍全局去重")
    func cachedFilesPreserveSinglePassReplacementBoundary() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("ClaudeCandidateCache-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let specifications = [
            ("1-side.jsonl", "side", "r1", 100, true),
            ("2-parent.jsonl", "parent", "r2", 10, false),
            ("3-repeat.jsonl", "parent-repeat", "r2", 5, false),
        ]
        let files = try specifications.map { name, record, request, input, sidechain in
            let url = dir.appendingPathComponent(name)
            let line = #"{"uuid":"\#(record)","sessionId":"s","timestamp":"2026-06-13T12:00:00Z","requestId":"\#(request)","isSidechain":\#(sidechain),"message":{"id":"shared","model":"claude-sonnet-4-5","usage":{"input_tokens":\#(input),"output_tokens":5}}}"#
            try (line + "\n").write(to: url, atomically: true, encoding: .utf8)
            return ClaudeJSONLFileInfo(
                url: url,
                sessionID: "s",
                projectPath: "/project",
                isSubagent: sidechain,
                agentId: sidechain ? "agent" : nil
            )
        }
        let parser = ClaudeJSONLParser()

        let first = try parser.parseAllFiles(files, claudeDataRoot: dir)
        let second = try parser.parseAllFiles(files, claudeDataRoot: dir)

        #expect(first.map(\.recordUUID) == ["parent", "parent-repeat"])
        #expect(ParsedUsageEntryDeepSnapshot.sorted(second) == ParsedUsageEntryDeepSnapshot.sorted(first))
        #expect(parser.debugCacheHitCount == files.count)
    }

    @Test("批量解析跳过单个失败文件")
    func parseAllFilesSkipsFailedFile() throws {
        let line = """
        {"type":"assistant","uuid":"u1","sessionId":"s1","timestamp":"2026-06-13T11:55:26.715Z","message":{"id":"ok-msg","role":"assistant","model":"deepseek-v4-pro","content":[{"type":"text","text":"hi"}],"stop_reason":"end_turn","usage":{"input_tokens":100,"cache_creation_input_tokens":0,"cache_read_input_tokens":0,"output_tokens":50,"server_tool_use":{"web_search_requests":0,"web_fetch_requests":0},"service_tier":"standard","cache_creation":{"ephemeral_1h_input_tokens":0,"ephemeral_5m_input_tokens":0},"inference_geo":"","iterations":[],"speed":"standard"}}}
        """
        let tmpDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("ClaudeJSONLParserTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tmpDir) }

        let validFile = tmpDir.appendingPathComponent("valid.jsonl")
        try line.write(to: validFile, atomically: true, encoding: .utf8)

        let missingSubagentFile = tmpDir
            .appendingPathComponent("subagents", isDirectory: true)
            .appendingPathComponent("agent-no-access.jsonl")
        let infos = [
            ClaudeJSONLFileInfo(url: validFile, sessionID: "s1", projectPath: "/p", isSubagent: false, agentId: nil),
            ClaudeJSONLFileInfo(url: missingSubagentFile, sessionID: "agent-no-access", projectPath: "/p", isSubagent: true, agentId: "no-access"),
        ]

        let entries = try parser.parseAllFiles(infos, claudeDataRoot: tmpDir)

        #expect(entries.count == 1)
        #expect(entries.first?.messageId == "ok-msg")
    }

    @Test("已成功文件的 stat open seek read 失败均复用 last-good，scanner 删除后 prune")
    func transientReaderFailuresReuseLastGoodUntilScannerOmitsFile() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("ClaudeLastGood-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        let url = dir.appendingPathComponent("session.jsonl")
        let first = Self.assistantLine(messageId: "first", inputTokens: 10)
        let second = Self.assistantLine(messageId: "second", inputTokens: 20)
        try (first + "\n").write(to: url, atomically: true, encoding: .utf8)
        let info = ClaudeJSONLFileInfo(
            url: url,
            sessionID: "session",
            projectPath: "/project",
            isSubagent: false,
            agentId: nil
        )
        let reader = RecordingJSONLFileReader()
        let parser = ClaudeJSONLParser(fileReader: reader)

        let initial = try parser.parseAllFiles([info], claudeDataRoot: dir)
        #expect(initial.map(\.messageId) == ["first"])

        try (first + "\n" + second + "\n").write(
            to: url,
            atomically: true,
            encoding: .utf8
        )
        for failure in [
            RecordingJSONLFileReader.Failure.metadata,
            .open,
            .seek,
            .read,
        ] {
            reader.failure = failure
            let fallback = try parser.parseAllFiles([info], claudeDataRoot: dir)
            #expect(fallback.map(\.messageId) == ["first"], Comment("failure=\(failure)"))
            #expect(parser.debugCachedFileCount == 1)
        }

        reader.failure = .none
        let deleted = try parser.parseAllFiles([], claudeDataRoot: dir)
        #expect(deleted.isEmpty)
        #expect(parser.debugCachedFileCount == 0)
    }

    @Test("从未成功的文件 metadata 失败时继续跳过")
    func firstMetadataFailureHasNoLastGoodResult() throws {
        let dir = FileManager.default.temporaryDirectory
        let url = dir.appendingPathComponent("never-read-\(UUID().uuidString).jsonl")
        let info = ClaudeJSONLFileInfo(
            url: url,
            sessionID: "missing",
            projectPath: "/project",
            isSubagent: false,
            agentId: nil
        )
        let reader = RecordingJSONLFileReader()
        reader.failure = .metadata
        let parser = ClaudeJSONLParser(fileReader: reader)

        let entries = try parser.parseAllFiles([info], claudeDataRoot: dir)

        #expect(entries.isEmpty)
        #expect(parser.debugCachedFileCount == 0)
    }

    @Test("公开单文件入口使用注入 reader 且读取错误上抛")
    func singleFileEntryUsesInjectedReaderAndPropagatesFailure() throws {
        let (file, root, cleanup) = try makeClaudeJSONL([
            Self.assistantLine(messageId: "single", inputTokens: 10),
        ])
        defer { cleanup() }
        let reader = RecordingJSONLFileReader()
        let parser = ClaudeJSONLParser(fileReader: reader)

        let entries = try parser.parseJSONLFile(file, claudeDataRoot: root)

        #expect(entries.map(\.messageId) == ["single"])
        #expect(reader.openCount == 1)
        #expect(reader.seekOffsets == [0])
        #expect(reader.closeCount == 1)

        reader.failure = .read
        do {
            _ = try parser.parseJSONLFile(file, claudeDataRoot: root)
            Issue.record("注入 read failure 后单文件入口没有抛错")
        } catch RecordingJSONLReaderError.injectedReadFailure {
            // Expected: the public single-file API must not swallow reader failures.
        } catch {
            Issue.record("收到非预期错误: \(error)")
        }
        #expect(reader.closeCount == 2)
    }

    @Test("跳过显式空字符串 message.id 的记录")
    func skipRecordsWithEmptyMessageId() throws {
        // optional 字段缺失可保留，但存在且为空字符串必须按 daily.rs 过滤。
        let jsonl = """
        {"type":"assistant","uuid":"u9","sessionId":"s1","timestamp":"2026-06-13T12:00:00Z","message":{"id":"","role":"assistant","model":"deepseek-v4-pro","usage":{"input_tokens":1,"cache_creation_input_tokens":0,"cache_read_input_tokens":0,"output_tokens":1,"server_tool_use":{"web_search_requests":0,"web_fetch_requests":0},"service_tier":"standard","cache_creation":{"ephemeral_1h_input_tokens":0,"ephemeral_5m_input_tokens":0},"inference_geo":"","iterations":[],"speed":"standard"}}}
        """
        let tmpDir = FileManager.default.temporaryDirectory
        let fileURL = tmpDir.appendingPathComponent("no-msg-id.jsonl")
        try jsonl.write(to: fileURL, atomically: true, encoding: .utf8)
        let info = ClaudeJSONLFileInfo(url: fileURL, sessionID: "s1", projectPath: "/p", isSubagent: false, agentId: nil)

        let entries = try parser.parseJSONLFile(info, claudeDataRoot: tmpDir)
        #expect(entries.isEmpty)

        try? FileManager.default.removeItem(at: fileURL)
    }

    @Test("同 messageId 多 chunk 去重 - 应保留携带真实 usage 的那条")
    func dedupKeepsRecordWithRealUsage() throws {
        // Claude Code JSONL 中,同一 message.id 会出现多条记录:
        // streaming 过程中的中间 chunk usage 全为 0;最终一条才携带真实 usage。
        // 之前用 Set.insert 保留首条,会丢掉真实 usage,导致今日 token 偏低。
        // 修复后:同 messageId 应保留 token 总量最大的一条(最完整)。
        let zeroUsageLine = """
        {"type":"assistant","uuid":"u-chunk","sessionId":"s1","timestamp":"2026-06-14T10:00:00Z","message":{"id":"shared-msg","role":"assistant","model":"deepseek-v4-pro","content":[],"stop_reason":null,"usage":{"input_tokens":0,"cache_creation_input_tokens":0,"cache_read_input_tokens":0,"output_tokens":0,"server_tool_use":{"web_search_requests":0,"web_fetch_requests":0},"service_tier":"standard","cache_creation":{"ephemeral_1h_input_tokens":0,"ephemeral_5m_input_tokens":0},"inference_geo":"","iterations":[],"speed":"standard"}}}
        """
        let realUsageLine = """
        {"type":"assistant","uuid":"u-final","sessionId":"s1","timestamp":"2026-06-14T10:00:01Z","message":{"id":"shared-msg","role":"assistant","model":"deepseek-v4-pro","content":[{"type":"text","text":"hi"}],"stop_reason":"end_turn","usage":{"input_tokens":1234,"cache_creation_input_tokens":0,"cache_read_input_tokens":5678,"output_tokens":234,"server_tool_use":{"web_search_requests":0,"web_fetch_requests":0},"service_tier":"standard","cache_creation":{"ephemeral_1h_input_tokens":0,"ephemeral_5m_input_tokens":0},"inference_geo":"","iterations":[],"speed":"standard"}}}
        """

        let tmpDir = FileManager.default.temporaryDirectory
        let fileURL = tmpDir.appendingPathComponent("multi-chunk-\(UUID().uuidString).jsonl")
        // 故意让 (0,0,0) chunk 排在前面 — 模拟真实日志写入顺序
        try (zeroUsageLine + "\n" + realUsageLine).write(to: fileURL, atomically: true, encoding: .utf8)
        let info = ClaudeJSONLFileInfo(url: fileURL, sessionID: "s1", projectPath: "/p", isSubagent: false, agentId: nil)

        let entries = try parser.parseAllFiles([info], claudeDataRoot: tmpDir)

        #expect(entries.count == 1)
        #expect(entries.first?.messageId == "shared-msg")
        // 关键:必须取到带真实 usage 的那条,而不是 (0,0,0) 的 chunk
        #expect(entries.first?.usage.inputTokens == 1234)
        #expect(entries.first?.usage.outputTokens == 234)
        #expect(entries.first?.usage.cacheReadInputTokens == 5678)

        try? FileManager.default.removeItem(at: fileURL)
    }

    @Test("批量解析复用未变化文件缓存,文件变化后失效")
    func parseAllFilesCachesUnchangedFiles() throws {
        let tmpDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("ClaudeJSONLParserCacheTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tmpDir) }

        let fileURL = tmpDir.appendingPathComponent("cached.jsonl")
        let firstLine = Self.assistantLine(messageId: "cached-1", inputTokens: 10)
        try (firstLine + "\n").write(to: fileURL, atomically: true, encoding: .utf8)

        let info = ClaudeJSONLFileInfo(
            url: fileURL,
            sessionID: "s1",
            projectPath: "/p",
            isSubagent: false,
            agentId: nil
        )
        let parser = ClaudeJSONLParser()

        let firstEntries = try parser.parseAllFiles([info], claudeDataRoot: tmpDir)
        #expect(firstEntries.count == 1)
        #expect(parser.debugCachedFileCount == 1)

        let hitCountBeforeSecondParse = parser.debugCacheHitCount
        let secondEntries = try parser.parseAllFiles([info], claudeDataRoot: tmpDir)
        #expect(secondEntries.count == 1)
        #expect(parser.debugCacheHitCount == hitCountBeforeSecondParse + 1)

        let secondLine = Self.assistantLine(messageId: "cached-2", inputTokens: 20)
        try (firstLine + "\n" + secondLine + "\n").write(to: fileURL, atomically: true, encoding: .utf8)

        let hitCountBeforeChangedParse = parser.debugCacheHitCount
        let changedEntries = try parser.parseAllFiles([info], claudeDataRoot: tmpDir)
        #expect(changedEntries.count == 2)
        #expect(parser.debugCacheHitCount == hitCountBeforeChangedParse)
    }

    @Test("Claude 未变化文件零读取，追加从 committed offset 开始")
    func appendReadsOnlySuffix() throws {
        let fixture = try makeClaudeFixture()
        defer { fixture.cleanup() }
        let reader = RecordingJSONLFileReader()
        let parser = ClaudeJSONLParser(fileReader: reader)
        // 仅当 continuity anchor 覆盖全部 committed prefix 时才验证增量追加。
        let firstLine = Self.minimalAssistantLine(
            messageId: "m1",
            inputTokens: 10
        )
        try (firstLine + "\n").write(
            to: fixture.file.url,
            atomically: false,
            encoding: .utf8
        )

        let first = try parser.parseAllFiles(
            [fixture.file],
            claudeDataRoot: fixture.root
        )
        let committedOffset = UInt64((firstLine + "\n").utf8.count)
        #expect(first.count == 1)
        #expect(
            committedOffset <= UInt64(JSONLContinuityAnchor.maximumByteCount)
        )

        reader.resetMetrics()
        _ = try parser.parseAllFiles(
            [fixture.file],
            claudeDataRoot: fixture.root
        )
        #expect(reader.openCount == 1)
        #expect(reader.totalBytesRead == 0)
        #expect(reader.seekOffsets.isEmpty)

        let secondLine = Self.minimalAssistantLine(
            messageId: "m2",
            inputTokens: 20
        )
        let anchor = try #require(
            parser.debugContinuityAnchor(for: fixture.file.url)
        )
        try appendUTF8(secondLine + "\n", to: fixture.file.url)
        reader.resetMetrics()
        let appended = try parser.parseAllFiles(
            [fixture.file],
            claudeDataRoot: fixture.root
        )

        #expect(appended.map(\.messageId).sorted() == ["m1", "m2"])
        #expect(reader.seekOffsets == [anchor.offset, committedOffset])
        #expect(
            reader.totalBytesRead
                == anchor.bytes.count + (secondLine + "\n").utf8.count
        )
    }

    @Test("Claude provisional 尾行重读后不重复")
    func provisionalTailIsReplacedWhenNewlineArrives() throws {
        let fixture = try makeClaudeFixture()
        defer { fixture.cleanup() }
        let reader = RecordingJSONLFileReader()
        let parser = ClaudeJSONLParser(fileReader: reader)
        let line = Self.assistantLine(messageId: "tail", inputTokens: 42)
        try line.write(
            to: fixture.file.url,
            atomically: false,
            encoding: .utf8
        )

        let provisional = try parser.parseAllFiles(
            [fixture.file],
            claudeDataRoot: fixture.root
        )
        #expect(provisional.count == 1)
        #expect(parser.debugCommittedOffset(for: fixture.file.url) == 0)

        reader.resetMetrics()
        try appendUTF8("\n", to: fixture.file.url)
        let committed = try parser.parseAllFiles(
            [fixture.file],
            claudeDataRoot: fixture.root
        )
        #expect(committed.count == 1)
        #expect(committed.first?.messageId == "tail")
        #expect(
            parser.debugCommittedOffset(for: fixture.file.url)
                == UInt64((line + "\n").utf8.count)
        )
        #expect(reader.seekOffsets == [0])
        #expect(reader.totalBytesRead == (line + "\n").utf8.count)
    }

    @Test("Claude 追加 parent 可替换 stable sidechain")
    func appendedParentReplacesStableSidechain() throws {
        let fixture = try makeClaudeFixture()
        defer { fixture.cleanup() }
        let parser = ClaudeJSONLParser()
        let sidechain = Self.assistantLine(
            messageId: "shared",
            requestId: "side",
            inputTokens: 500,
            isSidechain: true
        )
        let parent = Self.assistantLine(
            messageId: "shared",
            requestId: "parent",
            inputTokens: 5,
            isSidechain: false
        )
        try (sidechain + "\n").write(
            to: fixture.file.url,
            atomically: false,
            encoding: .utf8
        )
        _ = try parser.parseAllFiles(
            [fixture.file],
            claudeDataRoot: fixture.root
        )
        try appendUTF8(parent + "\n", to: fixture.file.url)

        let result = try parser.parseAllFiles(
            [fixture.file],
            claudeDataRoot: fixture.root
        )
        #expect(result.count == 1)
        #expect(result.first?.requestId == "parent")
        #expect(result.first?.usage.inputTokens == 5)
    }

    @Test("Claude 缺 source message ID 的绝对 offset 在 provisional/commit/append 中稳定")
    func missingMessageIDUsesStableAbsoluteOffset() throws {
        let fixture = try makeClaudeFixture()
        defer { fixture.cleanup() }
        let parser = ClaudeJSONLParser()
        let first = #"{"timestamp":"2026-06-13T12:00:00.000Z","message":{"model":"claude-sonnet-4-5","usage":{"input_tokens":1,"output_tokens":1}}}"#
        let second = #"{"timestamp":"2026-06-13T12:00:01.000Z","message":{"model":"claude-sonnet-4-5","usage":{"input_tokens":2,"output_tokens":1}}}"#
        try first.write(
            to: fixture.file.url,
            atomically: false,
            encoding: .utf8
        )
        let provisional = try parser.parseAllFiles(
            [fixture.file],
            claudeDataRoot: fixture.root
        )
        try appendUTF8("\n" + second + "\n", to: fixture.file.url)
        let incremental = try parser.parseAllFiles(
            [fixture.file],
            claudeDataRoot: fixture.root
        )
        let fresh = try ClaudeJSONLParser().parseAllFiles(
            [fixture.file],
            claudeDataRoot: fixture.root
        )

        #expect(provisional.first?.messageId == incremental.first?.messageId)
        #expect(Set(incremental.map(\.messageId)).count == 2)
        #expect(incremental.allSatisfy { !$0.hasSourceMessageID })
        #expect(
            ParsedUsageEntryDeepSnapshot.sorted(incremental)
                == ParsedUsageEntryDeepSnapshot.sorted(fresh)
        )
    }

    @Test("Claude 半行续写只在完整后返回")
    func incompleteTailWaitsForCompletion() throws {
        let fixture = try makeClaudeFixture()
        defer { fixture.cleanup() }
        let parser = ClaudeJSONLParser()
        let line = Self.assistantLine(messageId: "partial", inputTokens: 9)
        let split = line.utf8.index(
            line.utf8.startIndex,
            offsetBy: line.utf8.count / 2
        )
        let firstHalf = String(decoding: line.utf8[..<split], as: UTF8.self)
        let secondHalf = String(decoding: line.utf8[split...], as: UTF8.self)
        try firstHalf.write(
            to: fixture.file.url,
            atomically: false,
            encoding: .utf8
        )
        #expect(try parser.parseAllFiles(
            [fixture.file],
            claudeDataRoot: fixture.root
        ).isEmpty)
        try appendUTF8(secondHalf + "\n", to: fixture.file.url)
        #expect(try parser.parseAllFiles(
            [fixture.file],
            claudeDataRoot: fixture.root
        ).map(\.messageId) == ["partial"])
    }

    @Test(arguments: ["truncate", "truncate-grow", "replace", "touch"])
    func rebuildTransitionsReadFromZero(kind: String) throws {
        let fixture = try makeClaudeFixture()
        defer { fixture.cleanup() }
        let reader = RecordingJSONLFileReader()
        let parser = ClaudeJSONLParser(fileReader: reader)
        let original = Self.assistantLine(messageId: "old", inputTokens: 10) + "\n"
        try original.write(
            to: fixture.file.url,
            atomically: false,
            encoding: .utf8
        )
        _ = try parser.parseAllFiles(
            [fixture.file],
            claudeDataRoot: fixture.root
        )

        let replacement = Self.assistantLine(
            messageId: "new",
            inputTokens: 20
        ) + "\n"
        switch kind {
        case "truncate":
            let handle = try FileHandle(forWritingTo: fixture.file.url)
            try handle.truncate(atOffset: 0)
            try handle.close()
        case "truncate-grow":
            let handle = try FileHandle(forWritingTo: fixture.file.url)
            try handle.truncate(atOffset: 0)
            try handle.write(contentsOf: Data((replacement + replacement).utf8))
            try handle.close()
        case "replace":
            try replacement.write(
                to: fixture.file.url,
                atomically: true,
                encoding: .utf8
            )
        case "touch":
            try FileManager.default.setAttributes(
                [.modificationDate: Date().addingTimeInterval(5)],
                ofItemAtPath: fixture.file.url.path
            )
        default:
            Issue.record("unexpected transition kind")
        }

        reader.resetMetrics()
        let incremental = try parser.parseAllFiles(
            [fixture.file],
            claudeDataRoot: fixture.root
        )
        let fresh = try ClaudeJSONLParser().parseAllFiles(
            [fixture.file],
            claudeDataRoot: fixture.root
        )
        #expect(reader.seekOffsets.contains(0))
        #expect(
            ParsedUsageEntryDeepSnapshot.sorted(incremental)
                == ParsedUsageEntryDeepSnapshot.sorted(fresh)
        )
    }

    private static func assistantLine(
        messageId: String,
        requestId: String? = nil,
        inputTokens: Int,
        isSidechain: Bool = false
    ) -> String {
        let requestField = requestId.map { ",\"requestId\":\"\($0)\"" } ?? ""
        return """
        {"type":"assistant","uuid":"\(messageId)-uuid","sessionId":"s1","timestamp":"2026-06-13T11:55:26.715Z"\(requestField),"isSidechain":\(isSidechain),"message":{"id":"\(messageId)","role":"assistant","model":"deepseek-v4-pro","content":[{"type":"text","text":"hi"}],"stop_reason":"end_turn","usage":{"input_tokens":\(inputTokens),"cache_creation_input_tokens":0,"cache_read_input_tokens":0,"output_tokens":5,"server_tool_use":{"web_search_requests":0,"web_fetch_requests":0},"service_tier":"standard","cache_creation":{"ephemeral_1h_input_tokens":0,"ephemeral_5m_input_tokens":0},"inference_geo":"","iterations":[],"speed":"standard"}}}
        """
    }

    private static func minimalAssistantLine(
        messageId: String,
        inputTokens: Int
    ) -> String {
        #"{"timestamp":"2026-06-13T12:00:00.000Z","message":{"id":"\#(messageId)","model":"m","usage":{"input_tokens":\#(inputTokens),"output_tokens":1}}}"#
    }

    private func appendUTF8(_ text: String, to url: URL) throws {
        let handle = try FileHandle(forWritingTo: url)
        defer { try? handle.close() }
        try handle.seekToEnd()
        try handle.write(contentsOf: Data(text.utf8))
    }

    private struct ClaudeFixture {
        let root: URL
        let file: ClaudeJSONLFileInfo
        let cleanup: () -> Void
    }

    private func makeClaudeFixture() throws -> ClaudeFixture {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(
                "ClaudeIncremental-\(UUID().uuidString)",
                isDirectory: true
            )
        try FileManager.default.createDirectory(
            at: root,
            withIntermediateDirectories: true
        )
        let url = root.appendingPathComponent("session.jsonl")
        try Data().write(to: url)
        return ClaudeFixture(
            root: root,
            file: ClaudeJSONLFileInfo(
                url: url,
                sessionID: "session",
                projectPath: "/project",
                isSubagent: false,
                agentId: nil
            ),
            cleanup: { try? FileManager.default.removeItem(at: root) }
        )
    }

    private func makeClaudeJSONL(
        _ lines: [String],
        fileName: String = "usage.jsonl"
    ) throws -> (ClaudeJSONLFileInfo, URL, () -> Void) {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("ClaudeDaily-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let url = dir.appendingPathComponent(fileName)
        try (lines.joined(separator: "\n") + "\n").write(
            to: url,
            atomically: true,
            encoding: .utf8
        )
        let file = ClaudeJSONLFileInfo(
            url: url,
            sessionID: "file-session",
            projectPath: "/project",
            isSubagent: false,
            agentId: nil
        )
        return (file, dir, { try? FileManager.default.removeItem(at: dir) })
    }
}
