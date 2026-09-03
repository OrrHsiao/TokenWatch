import Foundation
import Testing
@testable import TokenWatch

@Suite("AntigravityProtoReader")
struct AntigravityProtoReaderTests {

    // MARK: - Varint 解码测试

    @Test("单字节与多字节 Varint 能正确解码")
    func decodesVarintsCorrectly() {
        // 1 字节：0
        var offset = 0
        let data0 = Data([0x00])
        #expect(AntigravityProtoReader.decodeVarint(from: data0, offset: &offset) == 0)
        #expect(offset == 1)

        // 1 字节：1
        offset = 0
        let data1 = Data([0x01])
        #expect(AntigravityProtoReader.decodeVarint(from: data1, offset: &offset) == 1)

        // 2 字节：300 (0xAC, 0x02 -> (0x2C) | (2 << 7) = 44 + 256 = 300)
        offset = 0
        let data300 = Data([0xAC, 0x02])
        #expect(AntigravityProtoReader.decodeVarint(from: data300, offset: &offset) == 300)
        #expect(offset == 2)

        // 3 字节：20361
        offset = 0
        let data20361 = makeVarint(20361)
        #expect(AntigravityProtoReader.decodeVarint(from: data20361, offset: &offset) == 20361)
    }

    @Test("截断数据或过长 Varint 返回 nil")
    func truncatedOrOverflowVarintReturnsNil() {
        var offset = 0
        // MSB 一直为 1 但数据结束
        let truncated = Data([0x80, 0x80])
        #expect(AntigravityProtoReader.decodeVarint(from: truncated, offset: &offset) == nil)

        // 超过 10 字节的超长非法 varint
        offset = 0
        let overflow = Data(repeating: 0x80, count: 12)
        #expect(AntigravityProtoReader.decodeVarint(from: overflow, offset: &offset) == nil)
    }

    // MARK: - Step 时间戳解码测试

    @Test("Timestamp 能够正确解码秒与纳秒")
    func decodesStepTimestamp() {
        // 构造 Timestamp: Tag 1 (seconds = 1785305564), Tag 2 (nanos = 500_000_000)
        let tsProto = makeSubmessage(tag: 1, content:
            makeVarintField(tag: 1, value: 1785305564) +
            makeVarintField(tag: 2, value: 500_000_000)
        )

        let date = AntigravityProtoReader.decodeStepTimestamp(from: tsProto)
        try! #require(date != nil)
        #expect(date?.timeIntervalSince1970 == 1785305564.5)
    }

    // MARK: - UsageMetadata 解码测试

    @Test("UsageMetadata 提取各维 Token 与 botMessageId")
    func decodesUsageMetadata() {
        // Tag 2: prompt=1200, Tag 5: cached=300, Tag 9: thoughts=150, Tag 10: candidates=250, Tag 3: total=400, Tag 7: botId="bot-123"
        var data = Data()
        data.append(makeVarintField(tag: 2, value: 1200))
        data.append(makeVarintField(tag: 5, value: 300))
        data.append(makeVarintField(tag: 9, value: 150))
        data.append(makeVarintField(tag: 10, value: 250))
        data.append(makeVarintField(tag: 3, value: 400))
        data.append(makeStringField(tag: 7, value: "bot-123"))

        let usage = AntigravityProtoReader.decodeUsageMetadata(from: data)
        #expect(usage.promptTokens == 1200)
        #expect(usage.cachedContentTokens == 300)
        #expect(usage.thoughtsTokens == 150)
        #expect(usage.candidatesTokens == 250)
        #expect(usage.totalTokens == 400)
        #expect(usage.botMessageId == "bot-123")
    }

    // MARK: - GenerationPayload 解码测试

    @Test("GenerationPayload 提取模型名称、元数据 Key-Value 与用量")
    func decodesGenerationPayload() {
        // Tag 4: UsageMetadata
        let usageData = makeVarintField(tag: 2, value: 500) + makeVarintField(tag: 3, value: 100)

        // Tag 20: kv request_id
        let reqIdKv = makeStringField(tag: 1, value: "request_id") + makeStringField(tag: 2, value: "req-999")
        // Tag 20: kv trajectory_id
        let trajIdKv = makeStringField(tag: 1, value: "trajectory_id") + makeStringField(tag: 2, value: "traj-888")
        // Tag 20: kv last_step_index
        let stepIdxKv = makeStringField(tag: 1, value: "last_step_index") + makeStringField(tag: 2, value: "42")

        var sub1 = Data()
        sub1.append(makeStringField(tag: 19, value: "gemini-3.8-flash"))
        sub1.append(makeStringField(tag: 21, value: "Gemini 3.8 Flash (High)"))
        sub1.append(makeSubmessage(tag: 20, content: reqIdKv))
        sub1.append(makeSubmessage(tag: 20, content: trajIdKv))
        sub1.append(makeSubmessage(tag: 20, content: stepIdxKv))
        sub1.append(makeSubmessage(tag: 4, content: usageData))

        // 外层包装 Tag 1
        let topData = makeSubmessage(tag: 1, content: sub1)

        let payload = AntigravityProtoReader.decodeGenerationPayload(from: topData)
        try! #require(payload != nil)
        #expect(payload?.modelID == "gemini-3.8-flash")
        #expect(payload?.modelDisplayName == "Gemini 3.8 Flash (High)")
        #expect(payload?.requestId == "req-999")
        #expect(payload?.trajectoryId == "traj-888")
        #expect(payload?.lastStepIndex == 42)
        #expect(payload?.usage?.promptTokens == 500)
        #expect(payload?.usage?.totalTokens == 100)
    }

    // MARK: - Workspace 路径解码测试

    @Test("WorkspacePath 能正确从 trajectory_metadata_blob 解码并转换 URI 为本地路径")
    func decodesWorkspacePathCorrectly() {
        // 构造 WorkspaceInfo: Tag 1 -> Tag 1 (file URI)
        let sub1 = makeStringField(tag: 1, value: "file:///Users/orrhsiao/Desktop/Code/TokenWatch")
        let top1 = makeSubmessage(tag: 1, content: sub1)

        let path = AntigravityProtoReader.decodeWorkspacePath(from: top1)
        #expect(path == "/Users/orrhsiao/Desktop/Code/TokenWatch")

        // 构造 Tag 7 兜底 (file URI)
        let top7 = makeStringField(tag: 7, value: "file:///Users/orrhsiao/Projects/MyProject")
        let path7 = AntigravityProtoReader.decodeWorkspacePath(from: top7)
        #expect(path7 == "/Users/orrhsiao/Projects/MyProject")
    }

    // MARK: - Helpers

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
