import Foundation
import Testing
@testable import TokenWatch

@Suite("DeepSeekHarnessZstdDecoder")
struct DeepSeekHarnessZstdDecoderTests {
    @Test("多帧 zstd 必须解出全部帧而不是只解第一帧")
    func decodesEveryFrame() throws {
        let fixture = DeepSeekHarnessTestFixtures.multiFrameV4Log
        let result = try DeepSeekHarnessZstdDecoder.decode(fixture)

        #expect(result.consumedByteCount == fixture.count)
        #expect(!result.hasIncompleteTrailingFrame)

        let plaintext = try #require(String(data: result.plaintext, encoding: .utf8))
        let lines = plaintext.split(separator: "\n")
        // header + 10 条事件，分布在 4 个独立帧中
        #expect(lines.count == 11)
        #expect(lines.first?.hasPrefix("{\"type\":\"session\"") == true)
        #expect(plaintext.contains("assistant/attempt"))
        #expect(plaintext.contains("compaction/summary"))
    }

    @Test("尾部未写完的帧只保留最后一个完整帧")
    func keepsOnlyCompleteFrames() throws {
        let fixture = DeepSeekHarnessTestFixtures.multiFrameV4Log
        let full = try DeepSeekHarnessZstdDecoder.decode(fixture)

        // 去掉尾部若干字节：最后一帧不再完整，前面的帧仍应全部解出。
        let truncated = fixture.prefix(fixture.count - 8)
        let partial = try DeepSeekHarnessZstdDecoder.decode(Data(truncated))

        #expect(partial.hasIncompleteTrailingFrame)
        #expect(partial.consumedByteCount < truncated.count)
        #expect(partial.plaintext.count < full.plaintext.count)
        // 已解出的内容必须是完整解析结果的前缀（不重复、不乱序）。
        #expect(full.plaintext.starts(with: partial.plaintext))
    }

    @Test("损坏的帧必须抛错而不是静默截断")
    func corruptedFrameThrows() {
        var corrupted = DeepSeekHarnessTestFixtures.multiFrameV4Log
        // 破坏帧头之后的第一个字节，使其无法构成合法帧。
        corrupted[6] = 0xFF
        corrupted[7] = 0xFF
        #expect(throws: DeepSeekHarnessZstdError.self) {
            _ = try DeepSeekHarnessZstdDecoder.decode(corrupted)
        }
    }

    @Test("空输入返回空结果")
    func emptyInput() throws {
        let result = try DeepSeekHarnessZstdDecoder.decode(Data())
        #expect(result.plaintext.isEmpty)
        #expect(result.consumedByteCount == 0)
        #expect(!result.hasIncompleteTrailingFrame)
    }

    @Test("帧魔数识别")
    func frameMagicDetection() {
        #expect(DeepSeekHarnessZstdDecoder.startsWithZstdFrame(
            DeepSeekHarnessTestFixtures.multiFrameV4Log
        ))
        #expect(!DeepSeekHarnessZstdDecoder.startsWithZstdFrame(Data("{\"type\":".utf8)))
        #expect(!DeepSeekHarnessZstdDecoder.startsWithZstdFrame(Data()))
    }

    @Test("未压缩日志按文本解码并可跨批次拼接不完整行")
    func decodesPlaintextLog() throws {
        let directory = try DeepSeekHarnessTestSupport.makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("session.v4.jsonl")
        try Data("{\"a\":1}\n{\"b\":".utf8).write(to: url)

        let reader = SystemJSONLFileReader()
        let snapshot = try reader.openSnapshot(for: url)
        defer { snapshot.stream.close() }
        let chunk = try DeepSeekHarnessSessionLogDecoder.decode(
            stream: snapshot.stream,
            fromOffset: 0,
            encoding: .plaintext,
            pendingLineBytes: Data()
        )

        #expect(chunk.lines.count == 1)
        #expect(chunk.lines.first == Data("{\"a\":1}".utf8))
        #expect(chunk.pendingLineBytes == Data("{\"b\":".utf8))
        #expect(chunk.consumedByteCount == UInt64(snapshot.metadata.size))
    }
}
