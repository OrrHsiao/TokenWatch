import Foundation
import Testing
@testable import TokenWatch

@Suite("AntigravityMessageParser")
struct AntigravityMessageParserTests {

    let parser = AntigravityMessageParser()

    @Test("正常解析出 ParsedUsageEntry 且包含完整 Reasoning 与 Cache Read 维度")
    func parsesValidGenerationRow() {
        let usageData = makeUsageBlob(prompt: 1000, cached: 400, thoughts: 200, candidates: 300, total: 500, botId: "bot-msg-1")
        let genBlob = makeGenerationBlob(model: "gemini-3.8-flash", reqId: "req-1", trajId: "traj-1", stepIdx: 10, usage: usageData)

        let stepDate = Date(timeIntervalSince1970: 1785300000)
        let scanResult = AntigravityConversationScanResult(
            conversationID: "traj-1",
            databaseURL: URL(fileURLWithPath: "/tmp/traj-1.db"),
            generations: [
                AntigravityRawGenerationRow(trajectoryID: "traj-1", genIdx: 0, dataBlob: genBlob)
            ],
            stepTimestamps: [10: stepDate]
        )

        let entries = parser.parseAll([scanResult])
        try! #require(entries.count == 1)

        let entry = entries[0]
        #expect(entry.messageId == "req-1")
        #expect(entry.sessionID == "traj-1")
        #expect(entry.model == "gemini-3.8-flash")
        #expect(entry.timestamp == stepDate)
        #expect(entry.provider == .antigravity)
        #expect(entry.usage.inputTokens == 1000)
        #expect(entry.usage.cacheReadInputTokens == 400)
        #expect(entry.usage.outputTokens == 500)
        #expect(entry.usage.reasoningTokens == 200)
    }

    @Test("相同 request_id 的重复生成被去重")
    func deduplicatesIdenticalEntries() {
        let usageData = makeUsageBlob(prompt: 100, cached: 0, thoughts: 50, candidates: 50, total: 100, botId: nil)
        let genBlob1 = makeGenerationBlob(model: "gemini-3.8-flash", reqId: "same-req", trajId: "traj-1", stepIdx: 1, usage: usageData)
        let genBlob2 = makeGenerationBlob(model: "gemini-3.8-flash", reqId: "same-req", trajId: "traj-1", stepIdx: 2, usage: usageData)

        let scanResult = AntigravityConversationScanResult(
            conversationID: "traj-1",
            databaseURL: URL(fileURLWithPath: "/tmp/traj-1.db"),
            generations: [
                AntigravityRawGenerationRow(trajectoryID: "traj-1", genIdx: 0, dataBlob: genBlob1),
                AntigravityRawGenerationRow(trajectoryID: "traj-1", genIdx: 1, dataBlob: genBlob2),
            ],
            stepTimestamps: [:]
        )

        let entries = parser.parseAll([scanResult])
        #expect(entries.count == 1)
    }

    @Test("4 维全 0 的生成记录被过滤跳过")
    func skipsAllZeroGenerations() {
        let zeroUsage = makeUsageBlob(prompt: 0, cached: 0, thoughts: 0, candidates: 0, total: 0, botId: nil)
        let genBlob = makeGenerationBlob(model: "gemini-3.8-flash", reqId: "req-zero", trajId: "traj-1", stepIdx: 1, usage: zeroUsage)

        let scanResult = AntigravityConversationScanResult(
            conversationID: "traj-1",
            databaseURL: URL(fileURLWithPath: "/tmp/traj-1.db"),
            generations: [
                AntigravityRawGenerationRow(trajectoryID: "traj-1", genIdx: 0, dataBlob: genBlob)
            ],
            stepTimestamps: [:]
        )

        let entries = parser.parseAll([scanResult])
        #expect(entries.isEmpty)
    }

    @Test("模型 ID 为空时回退到 gemini-3.8-flash 默认值")
    func fallbackModelWhenEmpty() {
        let usageData = makeUsageBlob(prompt: 10, cached: 0, thoughts: 0, candidates: 5, total: 5, botId: nil)
        let genBlob = makeGenerationBlob(model: "", reqId: "req-fallback", trajId: "traj-1", stepIdx: 1, usage: usageData)

        let scanResult = AntigravityConversationScanResult(
            conversationID: "traj-1",
            databaseURL: URL(fileURLWithPath: "/tmp/traj-1.db"),
            generations: [
                AntigravityRawGenerationRow(trajectoryID: "traj-1", genIdx: 0, dataBlob: genBlob)
            ],
            stepTimestamps: [:]
        )

        let entries = parser.parseAll([scanResult])
        try! #require(entries.count == 1)
        #expect(entries[0].model == "gemini-3.8-flash")
    }

    // MARK: - Helpers

    private func makeUsageBlob(prompt: Int, cached: Int, thoughts: Int, candidates: Int, total: Int, botId: String?) -> Data {
        var data = Data()
        if prompt > 0 { data.append(makeVarintField(tag: 2, value: UInt64(prompt))) }
        if cached > 0 { data.append(makeVarintField(tag: 5, value: UInt64(cached))) }
        if thoughts > 0 { data.append(makeVarintField(tag: 9, value: UInt64(thoughts))) }
        if candidates > 0 { data.append(makeVarintField(tag: 10, value: UInt64(candidates))) }
        if total > 0 { data.append(makeVarintField(tag: 3, value: UInt64(total))) }
        if let botId { data.append(makeStringField(tag: 7, value: botId)) }
        return data
    }

    private func makeGenerationBlob(model: String, reqId: String, trajId: String, stepIdx: Int64, usage: Data) -> Data {
        var sub1 = Data()
        if !model.isEmpty {
            sub1.append(makeStringField(tag: 19, value: model))
        }
        let reqKv = makeStringField(tag: 1, value: "request_id") + makeStringField(tag: 2, value: reqId)
        let trajKv = makeStringField(tag: 1, value: "trajectory_id") + makeStringField(tag: 2, value: trajId)
        let stepKv = makeStringField(tag: 1, value: "last_step_index") + makeStringField(tag: 2, value: String(stepIdx))

        sub1.append(makeSubmessage(tag: 20, content: reqKv))
        sub1.append(makeSubmessage(tag: 20, content: trajKv))
        sub1.append(makeSubmessage(tag: 20, content: stepKv))
        sub1.append(makeSubmessage(tag: 4, content: usage))

        return makeSubmessage(tag: 1, content: sub1)
    }

    private func makeVarint(_ value: UInt64) -> Data {
        var data = Data()
        var v = value
        while v >= 0x80 {
            data.append(UInt8((v & 0x7F) | 0x80))
            v >>= 7
        }
        data.append(UInt8(v & 0x7F))
        return data
    }

    private func makeVarintField(tag: Int, value: UInt64) -> Data {
        let key = UInt64(tag << 3 | 0)
        return makeVarint(key) + makeVarint(value)
    }

    private func makeStringField(tag: Int, value: String) -> Data {
        let content = Data(value.utf8)
        let key = UInt64(tag << 3 | 2)
        return makeVarint(key) + makeVarint(UInt64(content.count)) + content
    }

    private func makeSubmessage(tag: Int, content: Data) -> Data {
        let key = UInt64(tag << 3 | 2)
        return makeVarint(key) + makeVarint(UInt64(content.count)) + content
    }
}
