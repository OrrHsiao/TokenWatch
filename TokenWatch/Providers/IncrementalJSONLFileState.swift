import Foundation

struct IncrementalJSONLFileState<
    Candidate: Codable & Sendable,
    Checkpoint: Codable & Sendable
>: Codable, Sendable {
    let metadata: JSONLFileMetadata
    let committedOffset: UInt64
    let stableCandidates: [Candidate]
    let provisionalTail: Data
    let provisionalCandidates: [Candidate]
    let continuityAnchor: JSONLContinuityAnchor
    let checkpointAtCommittedOffset: Checkpoint

    var returnedCandidates: [Candidate] {
        stableCandidates + provisionalCandidates
    }
}

struct JSONLContinuityAnchor: Codable, Sendable, Equatable {
    // 1 KiB 仍保持追加校验为常量级读取，同时覆盖常见单行日志的可变字段，
    // 降低 truncate-and-grow 恰好复用短尾部而被误判为 append 的概率。
    static let maximumByteCount = 1_024

    let offset: UInt64
    let bytes: Data

    static let empty = JSONLContinuityAnchor(offset: 0, bytes: Data())

    /// 将新提交字节并入前一个锚点，并只保留 committed offset 前的固定长度尾部。
    static func make(
        previous: JSONLContinuityAnchor,
        newlyCommittedBytes: Data,
        committedOffset: UInt64
    ) -> JSONLContinuityAnchor {
        let combined = previous.bytes + newlyCommittedBytes
        let retainedCount = Int(min(
            UInt64(min(maximumByteCount, combined.count)),
            committedOffset
        ))
        let bytes = Data(combined.suffix(retainedCount))
        return JSONLContinuityAnchor(
            offset: committedOffset - UInt64(bytes.count),
            bytes: bytes
        )
    }

    /// 从已打开 stream 校验锚点字节，确认 append 候选仍延续同一内容。
    func matches(in stream: any JSONLByteStream) throws -> Bool {
        guard !bytes.isEmpty else { return true }
        try stream.seek(toOffset: offset)
        var actual = Data()
        while actual.count < bytes.count {
            let chunk = try stream.read(upToCount: bytes.count - actual.count)
            guard !chunk.isEmpty else { return false }
            actual.append(chunk)
        }
        return actual == bytes
    }
}

struct StatelessJSONLCheckpoint: Codable, Sendable, Equatable {}

enum IncrementalJSONLReadError: Error, Equatable {
    case unexpectedEOF
}

enum IncrementalJSONLTransition: Sendable, Equatable {
    case reuse
    case append(fromOffset: UInt64)
    case rebuild

    /// 根据同一 descriptor snapshot 的 identity、size 与 mtime 决定迁移候选。
    static func decide<Candidate, Checkpoint>(
        previous: IncrementalJSONLFileState<Candidate, Checkpoint>,
        newMetadata: JSONLFileMetadata
    ) -> IncrementalJSONLTransition
    where Candidate: Codable & Sendable, Checkpoint: Codable & Sendable {
        guard let oldIdentity = previous.metadata.identity,
              let newIdentity = newMetadata.identity,
              oldIdentity == newIdentity
        else {
            return .rebuild
        }
        if newMetadata.size == previous.metadata.size,
           newMetadata.modificationDate == previous.metadata.modificationDate {
            return .reuse
        }
        if newMetadata.size > previous.metadata.size {
            return .append(fromOffset: previous.committedOffset)
        }
        return .rebuild
    }
}
