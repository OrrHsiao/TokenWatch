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

/// Claude/Codex 共享的递归目录枚举入口；完整枚举失败时必须抛错，不能把部分结果当成功。
protocol JSONLDirectoryListing: Sendable {
    func recursiveFileURLs(in directory: URL) throws -> [URL]
}

/// 目录枚举适配层；测试可确定性模拟“已返回部分 URL 后才失败”。
protocol JSONLDirectoryEnumerating: Sendable {
    func recursiveFileURLs(
        in directory: URL,
        errorHandler: @escaping (URL, Error) -> Bool
    ) -> [URL]?
}

enum JSONLDirectoryListingError: LocalizedError {
    case notDirectory(URL)
    case unableToEnumerate(URL)

    var errorDescription: String? {
        switch self {
        case .notDirectory(let url):
            return "目标不是目录: \(url.path)"
        case .unableToEnumerate(let url):
            return "无法枚举目录: \(url.path)"
        }
    }
}

/// 仅在完整走完 DirectoryEnumerator 后返回结果；任一 EACCES/I/O 错误都会丢弃部分列表并上抛。
struct SystemJSONLDirectoryEnumerator: JSONLDirectoryEnumerating {
    func recursiveFileURLs(
        in directory: URL,
        errorHandler: @escaping (URL, Error) -> Bool
    ) -> [URL]? {
        guard let enumerator = FileManager.default.enumerator(
            at: directory,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles, .skipsPackageDescendants],
            errorHandler: errorHandler
        ) else {
            return nil
        }

        var urls: [URL] = []
        for case let url as URL in enumerator {
            urls.append(url)
        }
        return urls
    }
}

struct SystemJSONLDirectoryLister: JSONLDirectoryListing {
    private let directoryEnumerator: any JSONLDirectoryEnumerating

    init(directoryEnumerator: any JSONLDirectoryEnumerating = SystemJSONLDirectoryEnumerator()) {
        self.directoryEnumerator = directoryEnumerator
    }

    func recursiveFileURLs(in directory: URL) throws -> [URL] {
        do {
            let values = try directory.resourceValues(forKeys: [.isDirectoryKey])
            guard values.isDirectory == true else {
                throw JSONLDirectoryListingError.notDirectory(directory)
            }
        } catch {
            if isMissingDirectoryError(error) {
                return []
            }
            throw error
        }

        var enumerationError: Error?
        guard let urls = directoryEnumerator.recursiveFileURLs(
            in: directory,
            errorHandler: { _, error in
                enumerationError = error
                return false
            }
        ) else {
            throw JSONLDirectoryListingError.unableToEnumerate(directory)
        }

        if let enumerationError {
            throw enumerationError
        }
        return urls
    }

    private func isMissingDirectoryError(_ error: Error) -> Bool {
        let nsError = error as NSError
        return (nsError.domain == NSCocoaErrorDomain
            && nsError.code == CocoaError.fileReadNoSuchFile.rawValue)
            || (nsError.domain == NSPOSIXErrorDomain && nsError.code == Int(ENOENT))
    }
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
