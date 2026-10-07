import Foundation
import os.log

/// 多帧 zstd 流的解码结果。
struct DeepSeekHarnessZstdDecodeResult: Sendable, Equatable {
    /// 已解压出的明文字节。
    let plaintext: Data
    /// 输入字节中被「已完整解码的帧」覆盖的数量。
    ///
    /// DSH 每个写入批次是一个独立帧，且「已提交事件不会被重写」，因此调用方可以把该值
    /// 作为下一次增量解压的起始偏移；严格小于输入长度时说明尾部还有未写完的帧。
    let consumedByteCount: Int
    /// 本次输入的总字节数，用于判断尾部是否存在不完整帧。
    let inputByteCount: Int

    /// 尾部是否存在未写完的帧（DSH 崩溃恢复时的正常形态）。
    var hasIncompleteTrailingFrame: Bool {
        consumedByteCount < inputByteCount
    }
}

enum DeepSeekHarnessZstdError: LocalizedError {
    case streamCreationFailed
    case corruptedFrame(String)

    var errorDescription: String? {
        switch self {
        case .streamCreationFailed:
            return "无法创建 zstd 解码上下文"
        case .corruptedFrame(let detail):
            return "zstd 数据帧损坏：\(detail)"
        }
    }
}

/// DSH 会话日志的多帧 zstd 解码器。
///
/// 系统未提供 zstd（macOS SDK 的 Compression/Foundation 均无该算法，也不存在 libzstd），
/// 因此这里封装内置的 zstd 官方单文件解码器（见 `TokenWatch/Vendor/Zstd/README.md`）。
///
/// 关键约束：DSH 日志是**多帧拼接流**（一个 header 帧 + 每个追加批次一帧），
/// 一次性 `ZSTD_decompress()` 只会返回第一帧，必须使用流式 API 逐帧解码。
enum DeepSeekHarnessZstdDecoder {
    /// zstd 标准帧魔数（小端 0xFD2FB528）。
    static let frameMagic: [UInt8] = [0x28, 0xB5, 0x2F, 0xFD]
    /// 可跳过帧魔数区间（小端 0x184D2A50...0x184D2A5F）的首字节。
    private static let skippableFrameMagicPrefixes: ClosedRange<UInt8> = 0x50...0x5F

    private static let logger = Logger(
        subsystem: "com.xiaoao.TokenWatch",
        category: "DeepSeekHarnessZstdDecoder"
    )
    /// 输出缓冲大小：单帧通常是若干行 JSON，64 KiB 可覆盖绝大多数批次。
    private static let outputChunkByteCount = 64 * 1024

    /// 判断数据开头是否为 zstd 帧（含可跳过帧）。
    /// - Parameter data: 待检测数据。
    /// - Returns: 是否以合法 zstd 帧起始。
    static func startsWithZstdFrame(_ data: Data) -> Bool {
        guard data.count >= 4 else { return false }
        let header = [UInt8](data.prefix(4))
        if header == frameMagic { return true }
        // 可跳过帧：0x184D2A5? 的小端编码为 [0x5?, 0x2A, 0x4D, 0x18]
        return skippableFrameMagicPrefixes.contains(header[0])
            && header[1] == 0x2A
            && header[2] == 0x4D
            && header[3] == 0x18
    }

    /// 流式解压多帧 zstd 数据。
    /// - Parameter compressed: 从某一帧边界开始的压缩数据。
    /// - Returns: 明文与已完整消费的压缩字节数；尾部不完整帧会被保留给下次调用。
    /// - Throws: 帧结构损坏时抛出 `DeepSeekHarnessZstdError.corruptedFrame`。
    static func decode(_ compressed: Data) throws -> DeepSeekHarnessZstdDecodeResult {
        guard !compressed.isEmpty else {
            return DeepSeekHarnessZstdDecodeResult(
                plaintext: Data(),
                consumedByteCount: 0,
                inputByteCount: 0
            )
        }
        guard let stream = ZSTD_createDStream() else {
            logger.error("zstd 解码上下文创建失败")
            throw DeepSeekHarnessZstdError.streamCreationFailed
        }
        defer { ZSTD_freeDStream(stream) }
        _ = ZSTD_initDStream(stream)

        var plaintext = Data()
        var committedByteCount = 0
        var failureDescription: String?

        compressed.withUnsafeBytes { (inputRaw: UnsafeRawBufferPointer) in
            guard let inputBase = inputRaw.baseAddress else { return }
            var input = ZSTD_inBuffer(src: inputBase, size: inputRaw.count, pos: 0)
            var chunk = [UInt8](repeating: 0, count: outputChunkByteCount)

            while input.pos < input.size, failureDescription == nil {
                let positionBeforeDecode = input.pos
                var producedByteCount = 0

                chunk.withUnsafeMutableBytes { (outputRaw: UnsafeMutableRawBufferPointer) in
                    var output = ZSTD_outBuffer(
                        dst: outputRaw.baseAddress,
                        size: outputRaw.count,
                        pos: 0
                    )
                    let status = ZSTD_decompressStream(stream, &output, &input)
                    if ZSTD_isError(status) != 0 {
                        failureDescription = String(cString: ZSTD_getErrorName(status))
                        return
                    }
                    // 返回 0 表示「当前帧已完整解码并全部输出」，此时 input.pos 正好落在帧边界。
                    if status == 0 {
                        committedByteCount = input.pos
                    }
                    producedByteCount = output.pos
                    if output.pos > 0 {
                        plaintext.append(contentsOf: outputRaw.prefix(output.pos))
                    }
                }

                if failureDescription != nil { break }
                // 既没有消费输入也没有产出输出：解码器仍在等待更多数据（尾部不完整帧）。
                if producedByteCount == 0, input.pos == positionBeforeDecode { break }
            }
        }

        if let failureDescription {
            logger.error(
                "zstd 解码失败（已完整解出 \(committedByteCount)/\(compressed.count) 字节）: \(failureDescription, privacy: .public)"
            )
            throw DeepSeekHarnessZstdError.corruptedFrame(failureDescription)
        }

        return DeepSeekHarnessZstdDecodeResult(
            plaintext: plaintext,
            consumedByteCount: committedByteCount,
            inputByteCount: compressed.count
        )
    }
}
