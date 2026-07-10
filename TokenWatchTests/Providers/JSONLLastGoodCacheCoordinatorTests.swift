import Foundation
import Testing
@testable import TokenWatch

@Suite("JSONLLastGoodCacheCoordinator")
struct JSONLLastGoodCacheCoordinatorTests {
    private struct ListedFile {
        let url: URL
    }

    private enum Scope: Sendable, Equatable {
        case standard
        case fast
    }

    private struct IncrementalCoordinatorState: Sendable, Equatable {
        let revision: Int
        let lines: [String]
    }

    @Test("统一处理 unchanged hit、scope-sensitive last-good、成功替换与 prune")
    func coordinatesCacheLifecycleWithoutKnowingProviderCandidates() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("JSONLCoordinator-\(UUID().uuidString).jsonl")
        try Data("first\n".utf8).write(to: url, options: .atomic)
        defer { try? FileManager.default.removeItem(at: url) }

        let listed = ListedFile(url: url)
        let reader = RecordingJSONLFileReader()
        let coordinator = JSONLLastGoodCacheCoordinator<[String], Scope>(
            fileReader: reader
        )
        var fallbackFlags: [Bool] = []

        func load(_ files: [ListedFile], scope: Scope) -> [String] {
            coordinator.loadListedFiles(
                files,
                scope: scope,
                cacheKey: { $0.url.standardizedFileURL.path },
                urlForFile: \.url,
                build: { _, snapshot, _ in
                    try readLines(from: snapshot.stream)
                },
                project: { $0 },
                onFailure: { _, _, reusedLastGood in
                    fallbackFlags.append(reusedLastGood)
                }
            )
        }

        #expect(load([listed], scope: .standard) == ["first"])
        #expect(coordinator.debugCachedFileCount == 1)

        reader.resetMetrics()
        #expect(load([listed], scope: .standard) == ["first"])
        #expect(reader.openCount == 1)
        #expect(reader.totalBytesRead == 0)
        #expect(reader.closeCount == 1)
        #expect(coordinator.debugCacheHitCount == 1)

        try Data("first\nsecond\n".utf8).write(to: url, options: .atomic)
        reader.failure = .read
        reader.resetMetrics()
        #expect(load([listed], scope: .standard) == ["first"])
        #expect(fallbackFlags.last == true)
        #expect(reader.closeCount == 1)

        #expect(load([listed], scope: .fast).isEmpty)
        #expect(fallbackFlags.last == false)

        reader.failure = .none
        #expect(load([listed], scope: .standard) == ["first", "second"])
        #expect(coordinator.debugCachedFileCount == 1)

        #expect(load([], scope: .standard).isEmpty)
        #expect(coordinator.debugCachedFileCount == 0)
    }

    @Test("成功解析的空数组仍是可复用的 last-good")
    func emptySuccessfulCacheIsDistinguishedFromNoLastGood() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("JSONLEmptyLastGood-\(UUID().uuidString).jsonl")
        try Data().write(to: url, options: .atomic)
        defer { try? FileManager.default.removeItem(at: url) }

        let listed = ListedFile(url: url)
        let reader = RecordingJSONLFileReader()
        let coordinator = JSONLLastGoodCacheCoordinator<[String], Scope>(fileReader: reader)
        var fallbackFlags: [Bool] = []

        func load() -> [String] {
            coordinator.loadListedFiles(
                [listed],
                scope: .standard,
                cacheKey: { $0.url.standardizedFileURL.path },
                urlForFile: \.url,
                build: { _, snapshot, _ in
                    try readLines(from: snapshot.stream)
                },
                project: { $0 },
                onFailure: { _, _, reusedLastGood in
                    fallbackFlags.append(reusedLastGood)
                }
            )
        }

        #expect(load().isEmpty)
        #expect(coordinator.debugCachedFileCount == 1)

        try Data("unreadable\n".utf8).write(to: url, options: .atomic)
        reader.failure = .read

        #expect(load().isEmpty)
        #expect(fallbackFlags == [true])
        #expect(coordinator.debugCachedFileCount == 1)
    }

    @Test("identity 缺失时不会命中 unchanged 但成功结果仍可作为 last-good")
    func nilIdentityDisablesUnchangedHitButPreservesLastGood() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("JSONLNilIdentity-\(UUID().uuidString).jsonl")
        try Data("value\n".utf8).write(to: url, options: .atomic)
        defer { try? FileManager.default.removeItem(at: url) }

        let listed = ListedFile(url: url)
        let reader = NilIdentityJSONLFileReader()
        let coordinator = JSONLLastGoodCacheCoordinator<[String], Scope>(fileReader: reader)
        var parseCount = 0
        var reusedLastGood: Bool?

        func load() -> [String] {
            coordinator.loadListedFiles(
                [listed],
                scope: .standard,
                cacheKey: { $0.url.standardizedFileURL.path },
                urlForFile: \.url,
                build: { _, snapshot, _ in
                    parseCount += 1
                    return try readLines(from: snapshot.stream)
                },
                project: { $0 },
                onFailure: { _, _, reused in reusedLastGood = reused }
            )
        }

        #expect(load() == ["value"])
        #expect(load() == ["value"])
        #expect(parseCount == 2)
        #expect(coordinator.debugCacheHitCount == 0)

        reader.shouldFail = true
        #expect(load() == ["value"])
        #expect(reusedLastGood == true)
    }

    @Test("协调器把同 scope previous state 交给 build，并继续唯一处理 hit fallback prune")
    func coordinatorBuildsAndProjectsProviderStateAtomically() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("JSONLIncrementalCoordinator-\(UUID().uuidString).jsonl")
        try Data("first\n".utf8).write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }

        let listed = ListedFile(url: url)
        let key = url.standardizedFileURL.path
        let reader = RecordingJSONLFileReader()
        let coordinator = JSONLLastGoodCacheCoordinator<
            IncrementalCoordinatorState,
            Scope
        >(fileReader: reader)
        var receivedPreviousRevisions: [Int?] = []

        func load(_ files: [ListedFile], scope: Scope) -> [String] {
            coordinator.loadListedFiles(
                files,
                scope: scope,
                cacheKey: { $0.url.standardizedFileURL.path },
                urlForFile: \.url,
                build: { _, snapshot, previous in
                    receivedPreviousRevisions.append(previous?.revision)
                    return IncrementalCoordinatorState(
                        revision: (previous?.revision ?? 0) + 1,
                        lines: try readLines(from: snapshot.stream)
                    )
                },
                project: \.lines,
                onFailure: { _, _, _ in }
            )
        }

        #expect(load([listed], scope: .standard) == ["first"])
        #expect(receivedPreviousRevisions == [nil])

        reader.resetMetrics()
        #expect(load([listed], scope: .standard) == ["first"])
        #expect(reader.totalBytesRead == 0)
        #expect(receivedPreviousRevisions == [nil])

        let handle = try FileHandle(forWritingTo: url)
        try handle.seekToEnd()
        try handle.write(contentsOf: Data("second\n".utf8))
        try handle.close()
        #expect(load([listed], scope: .standard) == ["first", "second"])
        #expect(receivedPreviousRevisions == [nil, 1])
        #expect(coordinator.cachedState(for: key, scope: .standard)?.revision == 2)

        let failingHandle = try FileHandle(forWritingTo: url)
        try failingHandle.seekToEnd()
        try failingHandle.write(contentsOf: Data("third\n".utf8))
        try failingHandle.close()
        reader.failure = .read
        #expect(load([listed], scope: .standard) == ["first", "second"])
        #expect(load([listed], scope: .fast).isEmpty)

        reader.failure = .none
        #expect(load([], scope: .standard).isEmpty)
        #expect(coordinator.debugCachedFileCount == 0)
    }

    private func readLines(from stream: any JSONLByteStream) throws -> [String] {
        try stream.seek(toOffset: 0)
        var data = Data()
        while true {
            let chunk = try stream.read(upToCount: 64)
            if chunk.isEmpty { break }
            data.append(chunk)
        }
        return String(decoding: data, as: UTF8.self)
            .split(whereSeparator: \.isNewline)
            .map(String.init)
    }
}

private final class NilIdentityJSONLFileReader: JSONLFileReading, @unchecked Sendable {
    private let base = SystemJSONLFileReader()
    var shouldFail = false

    func openSnapshot(for url: URL) throws -> JSONLFileSnapshot {
        if shouldFail {
            throw RecordingJSONLReaderError.injectedMetadataFailure
        }
        let snapshot = try base.openSnapshot(for: url)
        return JSONLFileSnapshot(
            metadata: JSONLFileMetadata(
                identity: nil,
                size: snapshot.metadata.size,
                modificationDate: snapshot.metadata.modificationDate
            ),
            stream: snapshot.stream
        )
    }
}
