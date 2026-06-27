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
