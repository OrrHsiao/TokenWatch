import Foundation
import Testing
@testable import TokenWatch

@Suite("TokenWatchWidgetSnapshotStore")
struct TokenWatchWidgetSnapshotStoreTests {

    @Test("写入后可以读取同一份 JSON 快照")
    func writeThenReadSnapshot() throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = TokenWatchWidgetSnapshotStore(containerURLProvider: { directory })
        let snapshot = TokenWatchWidgetSnapshot.sample(
            generatedAt: Date(timeIntervalSince1970: 1_779_811_200),
            languageIdentifier: "en"
        )

        try store.write(snapshot)
        let decoded = try #require(store.read())
        let fileURL = try store.snapshotFileURL()

        #expect(decoded == snapshot)
        #expect(FileManager.default.fileExists(atPath: fileURL.path))
    }

    @Test("已有快照会被后续写入覆盖")
    func overwritesExistingSnapshot() throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = TokenWatchWidgetSnapshotStore(containerURLProvider: { directory })
        let firstSnapshot = TokenWatchWidgetSnapshot.sample(
            generatedAt: Date(timeIntervalSince1970: 1_779_811_200),
            languageIdentifier: "en"
        )
        let secondSnapshot = TokenWatchWidgetSnapshot.sample(
            generatedAt: Date(timeIntervalSince1970: 1_779_814_800),
            languageIdentifier: "zh-Hans"
        )

        try store.write(firstSnapshot)
        try store.write(secondSnapshot)

        #expect(store.read() == secondSnapshot)
    }

    @Test("首次写入遇到目标刚被其它写入创建时仍然成功")
    func firstWriteToleratesTargetCreatedBeforeMove() throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let competingSnapshot = TokenWatchWidgetSnapshot.sample(
            generatedAt: Date(timeIntervalSince1970: 1_779_811_200),
            languageIdentifier: "competing"
        )
        let fileManager = TargetCreatedBeforeMoveFileManager(competingSnapshot: competingSnapshot)
        let store = TokenWatchWidgetSnapshotStore(
            fileManager: fileManager,
            containerURLProvider: { directory }
        )
        let snapshot = TokenWatchWidgetSnapshot.sample(
            generatedAt: Date(timeIntervalSince1970: 1_779_814_800),
            languageIdentifier: "winner"
        )

        try store.write(snapshot)

        #expect(store.read() == snapshot)
    }

    @Test("多个 Task 同时写入不会留下不可读快照")
    func concurrentWritesLeaveReadableSnapshot() async throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = TokenWatchWidgetSnapshotStore(containerURLProvider: { directory })
        let snapshots = (0..<64).map { index in
            TokenWatchWidgetSnapshot.sample(
                generatedAt: Date(timeIntervalSince1970: 1_779_811_200 + TimeInterval(index)),
                languageIdentifier: "concurrent-\(index)"
            )
        }

        try await withThrowingTaskGroup(of: Void.self) { group in
            for snapshot in snapshots {
                group.addTask {
                    try store.write(snapshot)
                }
            }
            try await group.waitForAll()
        }

        let decoded = try #require(store.read())
        let fileURL = try store.snapshotFileURL()

        #expect(snapshots.contains(decoded))
        #expect(FileManager.default.fileExists(atPath: fileURL.path))
    }

    @Test("缺失文件返回 nil 而不是崩溃")
    func missingFileReturnsNil() throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = TokenWatchWidgetSnapshotStore(containerURLProvider: { directory })

        #expect(store.read() == nil)
    }

    @Test("损坏 JSON 返回 nil")
    func corruptedJSONReturnsNil() throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = TokenWatchWidgetSnapshotStore(containerURLProvider: { directory })
        let fileURL = try store.snapshotFileURL()
        try FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try Data("not-json".utf8).write(to: fileURL)

        #expect(store.read() == nil)
    }

    @Test("App Group container 不可用时写入抛出明确错误")
    func unavailableContainerThrows() {
        let store = TokenWatchWidgetSnapshotStore(containerURLProvider: { nil })
        let snapshot = TokenWatchWidgetSnapshot.empty()

        do {
            try store.write(snapshot)
            Issue.record("Expected appGroupContainerUnavailable")
        } catch let error as TokenWatchWidgetSnapshotStoreError {
            #expect(error == .appGroupContainerUnavailable)
        } catch {
            Issue.record("Unexpected error: \(error)")
        }
    }

    private func makeTemporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("TokenWatchWidgetSnapshotStoreTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
}

private final class TargetCreatedBeforeMoveFileManager: FileManager {
    private let competingSnapshot: TokenWatchWidgetSnapshot
    private var didCreateTarget = false

    init(competingSnapshot: TokenWatchWidgetSnapshot) {
        self.competingSnapshot = competingSnapshot
        super.init()
    }

    override func moveItem(at srcURL: URL, to dstURL: URL) throws {
        if !didCreateTarget && dstURL.lastPathComponent == "latest.json" {
            didCreateTarget = true
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            encoder.outputFormatting = [.sortedKeys]
            let data = try encoder.encode(competingSnapshot)
            try data.write(to: dstURL)
        }

        try super.moveItem(at: srcURL, to: dstURL)
    }
}
