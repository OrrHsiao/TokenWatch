import Foundation

/// 会话日志的物理编码。
///
/// DSH 默认写 `session.vN.jsonl.zstd`（多帧 zstd）；把 profile 配置成
/// `compression: 'none'` 时写纯文本 `session.vN.jsonl`。两者共用同一套解析逻辑。
enum DeepSeekHarnessLogEncoding: Sendable, Equatable {
    case plaintext
    case zstd

    /// 依据扩展名推断编码；`.zstd` 结尾视为压缩。
    static func inferred(from url: URL) -> DeepSeekHarnessLogEncoding {
        url.pathExtension.lowercased() == "zstd" ? .zstd : .plaintext
    }
}

/// 一次增量解码的结果。
struct DeepSeekHarnessDecodedChunk: Sendable, Equatable {
    /// 完整行（不含换行符）。
    let lines: [Data]
    /// 仍未构成完整行的尾部明文，需要与下一批数据拼接。
    let pendingLineBytes: Data
    /// 相对读取起点已消费的压缩字节数；调用方据此推进持久化偏移。
    let consumedByteCount: UInt64
}

enum DeepSeekHarnessSessionLogDecoderError: LocalizedError {
    /// 扩展名声明为 zstd，但内容既不是 zstd 也不是可读文本。
    case unexpectedEncoding(String)

    var errorDescription: String? {
        switch self {
        case .unexpectedEncoding(let detail):
            return "DSH 会话日志编码不符合预期：\(detail)"
        }
    }
}

/// 会话日志的字节读取 + 解压 + 分行。
enum DeepSeekHarnessSessionLogDecoder {
    private static let readChunkByteCount = 1 << 20
    private static let newlineByte: UInt8 = 0x0A

    /// 从指定偏移读取并解码日志。
    /// - Parameters:
    ///   - stream: 已打开的日志字节流。
    ///   - offset: 本次读取的起始（压缩）字节偏移，必须是帧边界。
    ///   - encoding: 物理编码。
    ///   - pendingLineBytes: 上一批次遗留的不完整行明文。
    /// - Returns: 完整行、剩余不完整行与已消费字节数。
    static func decode(
        stream: any JSONLByteStream,
        fromOffset offset: UInt64,
        encoding: DeepSeekHarnessLogEncoding,
        pendingLineBytes: Data
    ) throws -> DeepSeekHarnessDecodedChunk {
        try stream.seek(toOffset: offset)
        let raw = try readAll(from: stream)

        let plaintext: Data
        let consumedByteCount: UInt64
        switch encoding {
        case .plaintext:
            plaintext = raw
            consumedByteCount = UInt64(raw.count)
        case .zstd:
            if DeepSeekHarnessZstdDecoder.startsWithZstdFrame(raw) {
                let result = try DeepSeekHarnessZstdDecoder.decode(raw)
                plaintext = result.plaintext
                consumedByteCount = UInt64(result.consumedByteCount)
            } else if raw.isEmpty {
                plaintext = Data()
                consumedByteCount = 0
            } else {
                // 用户把 root 换成 compression: 'none' 后可能出现纯文本文件；
                // 按文本读取而不是直接失败，保证两种编码都能统计。
                plaintext = raw
                consumedByteCount = UInt64(raw.count)
            }
        }

        var combined = pendingLineBytes
        if !plaintext.isEmpty {
            combined.append(plaintext)
        }
        let (lines, pending) = splitLines(combined)
        return DeepSeekHarnessDecodedChunk(
            lines: lines,
            pendingLineBytes: pending,
            consumedByteCount: consumedByteCount
        )
    }

    /// 循环读取直到 EOF。
    ///
    /// `read(upToCount:)` 在单次调用中可能只返回部分数据（例如管道或大文件），
    /// 必须循环读取，否则会漏掉行。
    private static func readAll(from stream: any JSONLByteStream) throws -> Data {
        var data = Data()
        while true {
            let chunk = try stream.read(upToCount: readChunkByteCount)
            if chunk.isEmpty { break }
            data.append(chunk)
        }
        return data
    }

    /// 按换行切分；最后一段若未被换行结尾则作为待拼接的尾部保留。
    static func splitLines(_ data: Data) -> (lines: [Data], pending: Data) {
        guard !data.isEmpty else { return ([], Data()) }
        guard data.last != newlineByte else {
            return (data.split(separator: newlineByte, omittingEmptySubsequences: true), Data())
        }

        let separatorIndex = data.lastIndex(of: newlineByte)
        guard let separatorIndex else {
            return ([], data)
        }
        let completePart = data[data.startIndex...separatorIndex]
        let pending = Data(data[data.index(after: separatorIndex)...])
        let lines = completePart.split(separator: newlineByte, omittingEmptySubsequences: true)
        return (lines, pending)
    }
}
