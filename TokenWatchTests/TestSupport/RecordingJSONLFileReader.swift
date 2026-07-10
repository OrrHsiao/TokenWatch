import Foundation
@testable import TokenWatch

enum RecordingJSONLReaderError: Error {
    case injectedMetadataFailure
    case injectedOpenFailure
    case injectedSeekFailure
    case injectedReadFailure
}

final class RecordingJSONLFileReader: JSONLFileReading, @unchecked Sendable {
    enum Failure: Sendable, Equatable {
        case none
        case metadata
        case open
        case seek
        case read
    }

    private let base: any JSONLFileReading
    private let lock = NSLock()
    private var storedFailure: Failure = .none
    private var storedOpenCount = 0
    private var storedTotalBytesRead = 0
    private var storedSeekOffsets: [UInt64] = []
    private var storedCloseCount = 0
    private var storedLatestMetadata: JSONLFileMetadata?

    init(base: any JSONLFileReading = SystemJSONLFileReader()) {
        self.base = base
    }

    var failure: Failure {
        get {
            lock.lock()
            defer { lock.unlock() }
            return storedFailure
        }
        set {
            lock.lock()
            storedFailure = newValue
            lock.unlock()
        }
    }

    var openCount: Int { withLock { storedOpenCount } }
    var totalBytesRead: Int { withLock { storedTotalBytesRead } }
    var seekOffsets: [UInt64] { withLock { storedSeekOffsets } }
    var closeCount: Int { withLock { storedCloseCount } }
    var latestMetadata: JSONLFileMetadata? { withLock { storedLatestMetadata } }

    func resetMetrics() {
        withLock {
            storedOpenCount = 0
            storedTotalBytesRead = 0
            storedSeekOffsets = []
            storedCloseCount = 0
            storedLatestMetadata = nil
        }
    }

    func openSnapshot(for url: URL) throws -> JSONLFileSnapshot {
        let failure = self.failure
        if failure == .metadata {
            throw RecordingJSONLReaderError.injectedMetadataFailure
        }
        if failure == .open {
            throw RecordingJSONLReaderError.injectedOpenFailure
        }
        let snapshot = try base.openSnapshot(for: url)
        withLock {
            storedOpenCount += 1
            storedLatestMetadata = snapshot.metadata
        }
        let stream = RecordingJSONLByteStream(
            base: snapshot.stream,
            failure: failure,
            recordSeek: { [weak self] offset in
                guard let self else { return }
                self.withLock { self.storedSeekOffsets.append(offset) }
            },
            recordRead: { [weak self] count in
                guard let self else { return }
                self.withLock { self.storedTotalBytesRead += count }
            },
            recordClose: { [weak self] in
                guard let self else { return }
                self.withLock { self.storedCloseCount += 1 }
            }
        )
        return JSONLFileSnapshot(metadata: snapshot.metadata, stream: stream)
    }

    @discardableResult
    private func withLock<T>(_ body: () -> T) -> T {
        lock.lock()
        defer { lock.unlock() }
        return body()
    }
}

private final class RecordingJSONLByteStream: JSONLByteStream, @unchecked Sendable {
    private let base: any JSONLByteStream
    private let failure: RecordingJSONLFileReader.Failure
    private let recordSeek: (UInt64) -> Void
    private let recordRead: (Int) -> Void
    private let recordClose: () -> Void

    init(
        base: any JSONLByteStream,
        failure: RecordingJSONLFileReader.Failure,
        recordSeek: @escaping (UInt64) -> Void,
        recordRead: @escaping (Int) -> Void,
        recordClose: @escaping () -> Void
    ) {
        self.base = base
        self.failure = failure
        self.recordSeek = recordSeek
        self.recordRead = recordRead
        self.recordClose = recordClose
    }

    func seek(toOffset offset: UInt64) throws {
        if failure == .seek {
            throw RecordingJSONLReaderError.injectedSeekFailure
        }
        try base.seek(toOffset: offset)
        recordSeek(offset)
    }

    func read(upToCount count: Int) throws -> Data {
        if failure == .read {
            throw RecordingJSONLReaderError.injectedReadFailure
        }
        let data = try base.read(upToCount: count)
        recordRead(data.count)
        return data
    }

    func close() {
        base.close()
        recordClose()
    }
}
