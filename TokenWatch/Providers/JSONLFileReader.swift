import Darwin
import Foundation

/// 文件系统身份；device + inode 可区分同路径替换。
struct JSONLFileIdentity: Equatable, Sendable {
    let deviceID: UInt64
    let fileID: UInt64
}

/// 从已打开 descriptor 的 `fstat` 得到的文件快照元数据。
struct JSONLFileMetadata: Equatable, Sendable {
    let identity: JSONLFileIdentity?
    let size: UInt64
    let modificationDate: Date
}

/// 可 seek 的 JSONL 字节流；测试可在每个 I/O 边界确定性失败。
protocol JSONLByteStream: AnyObject, Sendable {
    func seek(toOffset offset: UInt64) throws
    func read(upToCount count: Int) throws -> Data
    func close()
}

/// 同一个已打开 descriptor 产生的 metadata 与 stream，避免 stat/open TOCTOU。
struct JSONLFileSnapshot: Sendable {
    let metadata: JSONLFileMetadata
    let stream: any JSONLByteStream
}

/// Claude/Codex 共享的 descriptor snapshot 入口。
protocol JSONLFileReading: Sendable {
    func openSnapshot(for url: URL) throws -> JSONLFileSnapshot
}

/// 使用 `FileHandle` 打开生产 JSONL 文件，并从同一 descriptor 读取 metadata。
struct SystemJSONLFileReader: JSONLFileReading {
    /// 先打开文件再对同一 descriptor 执行 `fstat`，返回一致的 metadata 与 stream。
    /// - Parameter url: 要读取的 JSONL 文件 URL。
    /// - Returns: 调用方负责关闭 stream 的文件快照。
    func openSnapshot(for url: URL) throws -> JSONLFileSnapshot {
        let handle = try FileHandle(forReadingFrom: url)
        do {
            var info = stat()
            guard fstat(handle.fileDescriptor, &info) == 0 else {
                throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
            }

            let nanoseconds = Double(info.st_mtimespec.tv_nsec) / 1_000_000_000
            let metadata = JSONLFileMetadata(
                identity: JSONLFileIdentity(
                    deviceID: UInt64(info.st_dev),
                    fileID: UInt64(info.st_ino)
                ),
                size: UInt64(max(0, info.st_size)),
                modificationDate: Date(
                    timeIntervalSince1970: Double(info.st_mtimespec.tv_sec) + nanoseconds
                )
            )
            return JSONLFileSnapshot(
                metadata: metadata,
                stream: FileHandleJSONLByteStream(handle: handle)
            )
        } catch {
            try? handle.close()
            throw error
        }
    }
}

private final class FileHandleJSONLByteStream: JSONLByteStream, @unchecked Sendable {
    private let handle: FileHandle

    init(handle: FileHandle) {
        self.handle = handle
    }

    func seek(toOffset offset: UInt64) throws {
        try handle.seek(toOffset: offset)
    }

    func read(upToCount count: Int) throws -> Data {
        try handle.read(upToCount: count) ?? Data()
    }

    func close() {
        try? handle.close()
    }
}
