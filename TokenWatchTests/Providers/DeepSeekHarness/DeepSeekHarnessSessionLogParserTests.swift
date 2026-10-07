import Foundation
import Testing
@testable import TokenWatch

@Suite("DeepSeekHarnessSessionLogParser")
struct DeepSeekHarnessSessionLogParserTests {
    private let parser = DeepSeekHarnessSessionLogParser()

    @Test("多帧 v4 日志按 DSH 口径折叠：同槽位替换、重试累加、attempt 取 stream 末尾用量")
    func foldsMultiFrameV4Log() throws {
        let directory = try DeepSeekHarnessTestSupport.makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = try DeepSeekHarnessTestSupport.writeSessionLog(
            root: directory,
            sessionDirectory: "session-fixture-a",
            fileName: "session.v4.jsonl.zstd",
            contents: DeepSeekHarnessTestFixtures.multiFrameV4Log
        )

        let state = try DeepSeekHarnessTestSupport.buildState(file: file)
        let entries = parser.project(state)
        let totals = DeepSeekHarnessTestSupport.totals(of: entries)
        let expected = DeepSeekHarnessTestFixtures.multiFrameV4Totals

        #expect(state.sessionID == "session-fixture-a")
        #expect(state.cwd == "/tmp/proj")
        #expect(!state.isSubagent)
        #expect(entries.count == expected.recordCount)
        #expect(totals.input == expected.inputTokens)
        #expect(totals.output == expected.outputTokens)
        #expect(totals.cacheRead == expected.cacheReadTokens)
    }

    @Test("同 (turn, step) 的后到样本替换先到样本，不重复计入")
    func replacesSampleWithinSameSlot() throws {
        let directory = try DeepSeekHarnessTestSupport.makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let contents = DeepSeekHarnessTestSupport.logContents([
            DeepSeekHarnessTestSupport.headerLine(id: "session-replace"),
            DeepSeekHarnessTestSupport.assistantMessageLine(
                sequence: 0, time: 1_000, turn: 1, step: 1, messageID: "msg-1",
                inputTokens: 100, outputTokens: 10, cacheReadTokens: 1_000
            ),
            DeepSeekHarnessTestSupport.assistantMessageLine(
                sequence: 1, time: 2_000, turn: 1, step: 1, messageID: "msg-1",
                inputTokens: 200, outputTokens: 20, cacheReadTokens: 2_000
            ),
        ])
        let file = try DeepSeekHarnessTestSupport.writeSessionLog(
            root: directory, sessionDirectory: "session-replace",
            fileName: "session.v4.jsonl", contents: contents
        )

        let entries = parser.project(try DeepSeekHarnessTestSupport.buildState(file: file))
        #expect(entries.count == 1)
        #expect(entries.first?.usage.inputTokens == 200)
        #expect(entries.first?.usage.outputTokens == 20)
        #expect(entries.first?.usage.cacheReadInputTokens == 2_000)
    }

    @Test("完全相同的重复样本按幂等去重")
    func deduplicatesIdenticalSamples() throws {
        let directory = try DeepSeekHarnessTestSupport.makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let contents = DeepSeekHarnessTestSupport.logContents([
            DeepSeekHarnessTestSupport.headerLine(id: "session-duplicate"),
            DeepSeekHarnessTestSupport.assistantMessageLine(
                sequence: 0, time: 1_000, turn: 1, step: 1, messageID: "msg-1",
                inputTokens: 100, outputTokens: 10
            ),
            DeepSeekHarnessTestSupport.assistantMessageLine(
                sequence: 1, time: 2_000, turn: 1, step: 1, messageID: "msg-1",
                inputTokens: 100, outputTokens: 10
            ),
        ])
        let file = try DeepSeekHarnessTestSupport.writeSessionLog(
            root: directory, sessionDirectory: "session-duplicate",
            fileName: "session.v4.jsonl", contents: contents
        )

        let entries = parser.project(try DeepSeekHarnessTestSupport.buildState(file: file))
        #expect(entries.count == 1)
        #expect(entries.first?.usage.inputTokens == 100)
    }

    @Test("重试前的失败尝试与重试后的样本各自计一次")
    func retryCountsFailedAttemptAndRetry() throws {
        let directory = try DeepSeekHarnessTestSupport.makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let contents = DeepSeekHarnessTestSupport.logContents([
            DeepSeekHarnessTestSupport.headerLine(id: "session-retry"),
            DeepSeekHarnessTestSupport.assistantAttemptLine(
                sequence: 0, time: 1_000, turn: 3, step: 2,
                inputTokens: 900, outputTokens: 30
            ),
            DeepSeekHarnessTestSupport.retryStartedLine(sequence: 1, time: 1_100, turn: 3, step: 2),
            DeepSeekHarnessTestSupport.assistantMessageLine(
                sequence: 2, time: 1_200, turn: 3, step: 2, messageID: "msg-retry",
                inputTokens: 120, outputTokens: 12, cacheReadTokens: 1_200
            ),
        ])
        let file = try DeepSeekHarnessTestSupport.writeSessionLog(
            root: directory, sessionDirectory: "session-retry",
            fileName: "session.v4.jsonl", contents: contents
        )

        let entries = parser.project(try DeepSeekHarnessTestSupport.buildState(file: file))
        let totals = DeepSeekHarnessTestSupport.totals(of: entries)

        #expect(entries.count == 2)
        #expect(totals.input == 1_020)
        #expect(totals.output == 42)
        #expect(totals.cacheRead == 1_200)
        // 两条记录的 key 必须不同（attemptIndex 区分），否则会被互相覆盖。
        #expect(Set(entries.map(\.recordUUID)).count == 2)
    }

    @Test("assistant/attempt 取 stream 中最后一个 usage chunk，而不是累加")
    func takesLastStreamUsageChunk() throws {
        let directory = try DeepSeekHarnessTestSupport.makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let contents = DeepSeekHarnessTestSupport.logContents([
            DeepSeekHarnessTestSupport.headerLine(id: "session-stream-tail"),
            DeepSeekHarnessTestSupport.assistantAttemptLine(
                sequence: 0, time: 1_000, turn: 1, step: 1,
                inputTokens: 11, outputTokens: 1,
                trailingChunks: [
                    [
                        "type": "chunk",
                        "time": 1_000,
                        "chunk": [
                            "type": "usage",
                            "usage": ["inputTokens": 22, "outputTokens": 2, "cacheReadTokens": 220],
                        ],
                    ],
                ]
            ),
        ])
        let file = try DeepSeekHarnessTestSupport.writeSessionLog(
            root: directory, sessionDirectory: "session-stream-tail",
            fileName: "session.v4.jsonl", contents: contents
        )

        let entries = parser.project(try DeepSeekHarnessTestSupport.buildState(file: file))
        #expect(entries.count == 1)
        #expect(entries.first?.usage.inputTokens == 22)
        #expect(entries.first?.usage.outputTokens == 2)
        #expect(entries.first?.usage.cacheReadInputTokens == 220)
    }

    @Test("compaction/summary 自带 usage 但不计入（与 DSH 官方投影一致）")
    func ignoresCompactionSummaryUsage() throws {
        let directory = try DeepSeekHarnessTestSupport.makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let compaction = """
        {"type":"compaction/summary","seq":1,"time":2000,"data":{"compactionId":"c1",\
        "shadowedTokenCount":10,"provider":"opencode-go","model":"deepseek-v4.1-flash",\
        "usage":{"inputTokens":5000,"outputTokens":600}}}
        """
        let contents = DeepSeekHarnessTestSupport.logContents([
            DeepSeekHarnessTestSupport.headerLine(id: "session-compaction"),
            DeepSeekHarnessTestSupport.assistantMessageLine(
                sequence: 0, time: 1_000, turn: 1, step: 1, messageID: "msg-1",
                inputTokens: 10, outputTokens: 1
            ),
            compaction,
        ])
        let file = try DeepSeekHarnessTestSupport.writeSessionLog(
            root: directory, sessionDirectory: "session-compaction",
            fileName: "session.v4.jsonl", contents: contents
        )

        let entries = parser.project(try DeepSeekHarnessTestSupport.buildState(file: file))
        #expect(entries.count == 1)
        #expect(entries.first?.usage.inputTokens == 10)
    }

    @Test("v0 日志没有 stream 字段时直接读 data.usage")
    func readsV0UsageWithoutStream() throws {
        let directory = try DeepSeekHarnessTestSupport.makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let contents = DeepSeekHarnessTestSupport.logContents([
            DeepSeekHarnessTestSupport.headerLine(id: "session-v0", version: 0),
            DeepSeekHarnessTestSupport.assistantMessageLine(
                sequence: 0, time: 1_000, turn: 1, step: 1, messageID: "msg-v0",
                inputTokens: 60, outputTokens: 6, cacheReadTokens: 600,
                includesStreamUsage: false
            ),
        ])
        let file = try DeepSeekHarnessTestSupport.writeSessionLog(
            root: directory, sessionDirectory: "session-v0",
            fileName: "session.jsonl", contents: contents
        )

        let entries = parser.project(try DeepSeekHarnessTestSupport.buildState(file: file))
        #expect(entries.count == 1)
        #expect(entries.first?.usage.inputTokens == 60)
        #expect(entries.first?.usage.cacheReadInputTokens == 600)
    }

    @Test("fork 子代理会话跳过继承前缀，只统计标记之后的用量")
    func skipsInheritedPrefixForSeededSession() throws {
        let directory = try DeepSeekHarnessTestSupport.makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = try DeepSeekHarnessTestSupport.writeSessionLog(
            root: directory,
            sessionDirectory: "sub-fixture-c",
            fileName: "session.v4.jsonl.zstd",
            contents: DeepSeekHarnessTestFixtures.seededForkLog
        )

        let state = try DeepSeekHarnessTestSupport.buildState(file: file)
        let entries = parser.project(state)
        let totals = DeepSeekHarnessTestSupport.totals(of: entries)
        let expected = DeepSeekHarnessTestFixtures.seededForkTotals

        #expect(state.isSeeded)
        #expect(state.isSubagent)
        #expect(state.inheritedEventCount == 1)
        #expect(entries.count == expected.recordCount)
        #expect(totals.input == expected.inputTokens)
        #expect(totals.output == expected.outputTokens)
        #expect(entries.first?.isSubagent == true)
    }

    @Test("未压缩（compression: none）日志与压缩日志走同一套解析")
    func parsesUncompressedLog() throws {
        let directory = try DeepSeekHarnessTestSupport.makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let contents = DeepSeekHarnessTestSupport.logContents([
            DeepSeekHarnessTestSupport.headerLine(id: "session-plain"),
            DeepSeekHarnessTestSupport.assistantMessageLine(
                sequence: 0, time: 1_000, turn: 1, step: 1, messageID: "msg-plain",
                inputTokens: 42, outputTokens: 4
            ),
        ])
        let file = try DeepSeekHarnessTestSupport.writeSessionLog(
            root: directory, sessionDirectory: "session-plain",
            fileName: "session.v4.jsonl", contents: contents
        )

        let entries = parser.project(try DeepSeekHarnessTestSupport.buildState(file: file))
        #expect(entries.count == 1)
        #expect(entries.first?.usage.inputTokens == 42)
    }

    @Test("增量续读与整体重解析结果一致，且只读取新增字节")
    func incrementalAppendMatchesFullReparse() throws {
        let directory = try DeepSeekHarnessTestSupport.makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let firstBatch = DeepSeekHarnessTestSupport.logContents([
            DeepSeekHarnessTestSupport.headerLine(id: "session-incremental"),
            DeepSeekHarnessTestSupport.assistantMessageLine(
                sequence: 0, time: 1_000, turn: 1, step: 1, messageID: "msg-1",
                inputTokens: 100, outputTokens: 10
            ),
        ])
        let file = try DeepSeekHarnessTestSupport.writeSessionLog(
            root: directory, sessionDirectory: "session-incremental",
            fileName: "session.v4.jsonl", contents: firstBatch
        )

        let reader = RecordingJSONLFileReader()
        let firstState = try DeepSeekHarnessTestSupport.buildState(file: file, fileReader: reader)
        #expect(parser.project(firstState).count == 1)

        let secondBatch = DeepSeekHarnessTestSupport.logContents([
            DeepSeekHarnessTestSupport.assistantMessageLine(
                sequence: 1, time: 2_000, turn: 2, step: 1, messageID: "msg-2",
                inputTokens: 200, outputTokens: 20
            ),
        ])
        let handle = try FileHandle(forWritingTo: file.url)
        try handle.seekToEnd()
        try handle.write(contentsOf: secondBatch)
        try handle.close()

        reader.resetMetrics()
        let incrementalState = try DeepSeekHarnessTestSupport.buildState(
            file: file,
            previous: firstState,
            fileReader: reader
        )
        let fullState = try DeepSeekHarnessTestSupport.buildState(file: file)

        let incrementalEntries = parser.project(incrementalState)
        let fullEntries = parser.project(fullState)
        #expect(incrementalEntries.count == 2)
        #expect(DeepSeekHarnessTestSupport.totals(of: incrementalEntries).input
            == DeepSeekHarnessTestSupport.totals(of: fullEntries).input)
        // 增量续读必须从上次已提交的压缩偏移开始，而不是从头。
        #expect(reader.seekOffsets == [UInt64(firstBatch.count)])
    }

    @Test("未知事件类型与损坏行被跳过，不影响其余统计")
    func skipsUnknownAndMalformedLines() throws {
        let directory = try DeepSeekHarnessTestSupport.makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let contents = DeepSeekHarnessTestSupport.logContents([
            DeepSeekHarnessTestSupport.headerLine(id: "session-mixed"),
            #"{"type":"future/event","seq":0,"time":1000,"data":{"unknown":true}}"#,
            "{ this is not json",
            #"{"type":"assistant/message","seq":2,"time":2000,"data":{"turn":1,"step":1,"message":{"id":"m","source":{"provider":"p","model":"m"}},"usage":{"inputTokens":5,"outputTokens":1}}}"#,
        ])
        let file = try DeepSeekHarnessTestSupport.writeSessionLog(
            root: directory, sessionDirectory: "session-mixed",
            fileName: "session.v4.jsonl", contents: contents
        )

        let entries = parser.project(try DeepSeekHarnessTestSupport.buildState(file: file))
        #expect(entries.count == 1)
        #expect(entries.first?.usage.inputTokens == 5)
    }

    @Test("未来格式版本仍按已知契约解析而不是丢弃整个会话")
    func toleratesFutureFormatVersion() throws {
        let directory = try DeepSeekHarnessTestSupport.makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let contents = DeepSeekHarnessTestSupport.logContents([
            DeepSeekHarnessTestSupport.headerLine(id: "session-future", version: 99),
            DeepSeekHarnessTestSupport.assistantMessageLine(
                sequence: 0, time: 1_000, turn: 1, step: 1, messageID: "msg-future",
                inputTokens: 9, outputTokens: 1
            ),
        ])
        let file = try DeepSeekHarnessTestSupport.writeSessionLog(
            root: directory, sessionDirectory: "session-future",
            fileName: "session.v99.jsonl", contents: contents
        )

        let entries = parser.project(try DeepSeekHarnessTestSupport.buildState(file: file))
        #expect(entries.count == 1)
        #expect(entries.first?.usage.inputTokens == 9)
    }

    @Test("缓存写入与思考维度按 DSH 语义映射")
    func mapsCacheWriteAndReasoningDimensions() throws {
        let directory = try DeepSeekHarnessTestSupport.makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let contents = DeepSeekHarnessTestSupport.logContents([
            DeepSeekHarnessTestSupport.headerLine(id: "session-dimensions"),
            DeepSeekHarnessTestSupport.assistantMessageLine(
                sequence: 0, time: 1_000, turn: 1, step: 1, messageID: "msg-dim",
                inputTokens: 10, outputTokens: 20, cacheReadTokens: 30,
                cacheWriteTokens: 40, reasoningTokens: 7
            ),
        ])
        let file = try DeepSeekHarnessTestSupport.writeSessionLog(
            root: directory, sessionDirectory: "session-dimensions",
            fileName: "session.v4.jsonl", contents: contents
        )

        let entry = try #require(parser.project(try DeepSeekHarnessTestSupport.buildState(file: file)).first)
        #expect(entry.usage.cacheCreationInputTokens == 40)
        #expect(entry.usage.totalCacheCreationTokens == 40)
        #expect(entry.usage.reasoningTokens == 7)
        // reasoning 已包含在 output 内，不能二次计入总量。
        #expect(entry.usage.aggregateTotalTokens == 10 + 20 + 30 + 40)
        #expect(entry.upstreamProviderID == "opencode-go")
        #expect(entry.upstreamModelID == "deepseek-v4.1-flash")
        #expect(entry.provider == .deepSeekHarness)
    }
}
