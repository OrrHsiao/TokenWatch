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

    private struct IncrementalCoordinatorState: Codable, Sendable, Equatable {
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

    @Test("磁盘持久化缓存可跨 Coordinator 实例实现冷启动命中")
    func diskCacheHitAcrossCoordinatorInstances() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("JSONLDiskCoordinator-\(UUID().uuidString)")
        let cacheFileURL = tempDir.appendingPathComponent("diskCache.json")
        let logURL = tempDir.appendingPathComponent("test.jsonl")

        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        try Data("line1\nline2\n".utf8).write(to: logURL)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let listed = ListedFile(url: logURL)
        let store1 = SystemJSONLDiskCacheStore<[String]>(fileURL: cacheFileURL)
        let reader1 = RecordingJSONLFileReader()
        let coordinator1 = JSONLLastGoodCacheCoordinator<[String], Scope>(fileReader: reader1)

        let result1 = coordinator1.loadListedFiles(
            [listed],
            scope: .standard,
            diskStore: store1,
            cacheKey: { $0.url.standardizedFileURL.path },
            urlForFile: \.url,
            build: { _, snapshot, _ in try readLines(from: snapshot.stream) },
            project: { $0 },
            onFailure: { _, _, _ in }
        )
        #expect(result1 == ["line1", "line2"])

        // 模拟全新的冷启动进程：创建全新的 Reader、DiskStore 与 Coordinator
        let store2 = SystemJSONLDiskCacheStore<[String]>(fileURL: cacheFileURL)
        let reader2 = RecordingJSONLFileReader()
        let coordinator2 = JSONLLastGoodCacheCoordinator<[String], Scope>(fileReader: reader2)

        let result2 = coordinator2.loadListedFiles(
            [listed],
            scope: .standard,
            diskStore: store2,
            cacheKey: { $0.url.standardizedFileURL.path },
            urlForFile: \.url,
            build: { _, snapshot, _ in
                Issue.record("磁盘缓存命中的文件不应重新触发 build")
                return []
            },
            project: { $0 },
            onFailure: { _, _, _ in }
        )

        #expect(result2 == ["line1", "line2"])
        #expect(coordinator2.debugCacheHitCount == 1)
        #expect(reader2.totalBytesRead == 0)
    }

    @Test("冷启动文件变化时把磁盘完整 state 作为 previous")
    func changedFileRestoresPreviousStateAcrossCoordinatorInstances() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("JSONLDiskPrevious-\(UUID().uuidString)")
        let cacheFileURL = tempDir.appendingPathComponent("diskCache.json")
        let logURL = tempDir.appendingPathComponent("test.jsonl")
        try FileManager.default.createDirectory(
            at: tempDir,
            withIntermediateDirectories: true
        )
        try Data("first\n".utf8).write(to: logURL)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let listed = ListedFile(url: logURL)
        let firstCoordinator = JSONLLastGoodCacheCoordinator<
            IncrementalCoordinatorState,
            Scope
        >(fileReader: RecordingJSONLFileReader())
        let firstStore = SystemJSONLDiskCacheStore<IncrementalCoordinatorState>(
            fileURL: cacheFileURL
        )
        _ = firstCoordinator.loadListedFiles(
            [listed],
            scope: .standard,
            diskStore: firstStore,
            cacheKey: { $0.url.standardizedFileURL.path },
            urlForFile: \.url,
            build: { _, snapshot, _ in
                IncrementalCoordinatorState(
                    revision: 1,
                    lines: try readLines(from: snapshot.stream)
                )
            },
            project: \.lines,
            onFailure: { _, _, _ in }
        )

        let handle = try FileHandle(forWritingTo: logURL)
        try handle.seekToEnd()
        try handle.write(contentsOf: Data("second\n".utf8))
        try handle.close()

        let secondCoordinator = JSONLLastGoodCacheCoordinator<
            IncrementalCoordinatorState,
            Scope
        >(fileReader: RecordingJSONLFileReader())
        let secondStore = SystemJSONLDiskCacheStore<IncrementalCoordinatorState>(
            fileURL: cacheFileURL
        )
        var restoredRevision: Int?
        let result = secondCoordinator.loadListedFiles(
            [listed],
            scope: .standard,
            diskStore: secondStore,
            cacheKey: { $0.url.standardizedFileURL.path },
            urlForFile: \.url,
            build: { _, snapshot, previous in
                restoredRevision = previous?.revision
                return IncrementalCoordinatorState(
                    revision: (previous?.revision ?? 0) + 1,
                    lines: try readLines(from: snapshot.stream)
                )
            },
            project: \.lines,
            onFailure: { _, _, _ in }
        )

        #expect(restoredRevision == 1)
        #expect(result == ["first", "second"])
    }

    @Test("状态入口在全量 unchanged 时可跳过候选投影")
    func unchangedStatusCanSkipCandidateMaterialization() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("JSONLStatus-\(UUID().uuidString)")
        let cacheFileURL = tempDir.appendingPathComponent("diskCache.json")
        let logURL = tempDir.appendingPathComponent("test.jsonl")
        try FileManager.default.createDirectory(
            at: tempDir,
            withIntermediateDirectories: true
        )
        try Data("first\n".utf8).write(to: logURL)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let listed = ListedFile(url: logURL)
        let firstStore = SystemJSONLDiskCacheStore<[String]>(
            fileURL: cacheFileURL
        )
        let firstCoordinator = JSONLLastGoodCacheCoordinator<[String], Scope>(
            fileReader: RecordingJSONLFileReader()
        )
        _ = firstCoordinator.loadListedFiles(
            [listed],
            scope: .standard,
            diskStore: firstStore,
            cacheKey: { $0.url.standardizedFileURL.path },
            urlForFile: \.url,
            build: { _, snapshot, _ in try readLines(from: snapshot.stream) },
            project: { $0 },
            onFailure: { _, _, _ in }
        )

        let secondStore = SystemJSONLDiskCacheStore<[String]>(
            fileURL: cacheFileURL
        )
        let secondCoordinator = JSONLLastGoodCacheCoordinator<[String], Scope>(
            fileReader: RecordingJSONLFileReader()
        )
        var projectCount = 0
        let result = secondCoordinator.loadListedFilesWithChangeStatus(
            [listed],
            scope: .standard,
            diskStore: secondStore,
            materializeCandidatesWhenUnchanged: false,
            cacheKey: { $0.url.standardizedFileURL.path },
            urlForFile: \.url,
            build: { _, _, _ in
                Issue.record("unchanged 文件不应 build")
                return []
            },
            project: { state in
                projectCount += 1
                return state
            },
            onFailure: { _, _, _ in }
        )

        #expect(result.didChange == false)
        #expect(result.candidates == nil)
        #expect(projectCount == 0)
    }

    @Test("source revision 跨冷启动稳定且随文件变化")
    func sourceRevisionIsStableAndChangesWithMetadata() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("JSONLRevision-\(UUID().uuidString)")
        let cacheFileURL = tempDir.appendingPathComponent("diskCache.json")
        let logURL = tempDir.appendingPathComponent("test.jsonl")
        try FileManager.default.createDirectory(
            at: tempDir,
            withIntermediateDirectories: true
        )
        try Data("first\n".utf8).write(to: logURL)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let listed = ListedFile(url: logURL)
        func load(
            coordinator: JSONLLastGoodCacheCoordinator<[String], Scope>,
            store: SystemJSONLDiskCacheStore<[String]>
        ) -> JSONLLastGoodCacheLoadResult<String> {
            coordinator.loadListedFilesWithChangeStatus(
                [listed],
                scope: .standard,
                diskStore: store,
                materializeCandidatesWhenUnchanged: false,
                cacheKey: { $0.url.standardizedFileURL.path },
                urlForFile: \.url,
                build: { _, snapshot, _ in try readLines(from: snapshot.stream) },
                project: { $0 },
                onFailure: { _, _, _ in }
            )
        }

        let first = load(
            coordinator: JSONLLastGoodCacheCoordinator(
                fileReader: RecordingJSONLFileReader()
            ),
            store: SystemJSONLDiskCacheStore(fileURL: cacheFileURL)
        )
        let coldCoordinator = JSONLLastGoodCacheCoordinator<[String], Scope>(
            fileReader: RecordingJSONLFileReader()
        )
        let unchanged = load(
            coordinator: coldCoordinator,
            store: SystemJSONLDiskCacheStore(fileURL: cacheFileURL)
        )

        #expect(first.didChange)
        #expect(unchanged.didChange == false)
        #expect(first.sourceRevision == unchanged.sourceRevision)

        let handle = try FileHandle(forWritingTo: logURL)
        try handle.seekToEnd()
        try handle.write(contentsOf: Data("second\n".utf8))
        try handle.close()
        let changed = load(
            coordinator: coldCoordinator,
            store: SystemJSONLDiskCacheStore(fileURL: cacheFileURL)
        )

        #expect(changed.didChange)
        #expect(changed.sourceRevision != unchanged.sourceRevision)
    }

    @Test("空扫描会清除已持久化的缓存")
    func emptyScanClearsPersistedDiskCache() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("JSONLDiskPrune-\(UUID().uuidString)")
        let cacheFileURL = tempDir.appendingPathComponent("diskCache.json")
        let logURL = tempDir.appendingPathComponent("test.jsonl")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        try Data("line1\n".utf8).write(to: logURL)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let listed = ListedFile(url: logURL)
        let store = SystemJSONLDiskCacheStore<[String]>(fileURL: cacheFileURL)
        let coordinator = JSONLLastGoodCacheCoordinator<[String], Scope>(
            fileReader: RecordingJSONLFileReader()
        )

        let first = coordinator.loadListedFiles(
            [listed],
            scope: .standard,
            diskStore: store,
            cacheKey: { $0.url.standardizedFileURL.path },
            urlForFile: \.url,
            build: { _, snapshot, _ in try readLines(from: snapshot.stream) },
            project: { $0 },
            onFailure: { _, _, _ in }
        )
        #expect(first == ["line1"])
        #expect(!store.loadAll().isEmpty)

        let emptyFiles: [ListedFile] = []
        let cleared = coordinator.loadListedFiles(
            emptyFiles,
            scope: .standard,
            diskStore: store,
            cacheKey: { $0.url.standardizedFileURL.path },
            urlForFile: \.url,
            build: { _, snapshot, _ in [] },
            project: { $0 },
            onFailure: { _, _, _ in }
        )

        #expect(cleared.isEmpty)
        let reloadedStore = SystemJSONLDiskCacheStore<[String]>(fileURL: cacheFileURL)
        #expect(reloadedStore.loadAll().isEmpty)
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
