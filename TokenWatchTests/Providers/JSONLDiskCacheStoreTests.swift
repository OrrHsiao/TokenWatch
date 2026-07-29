import Foundation
import Testing
@testable import TokenWatch

@Suite("JSONLDiskCacheStore")
struct JSONLDiskCacheStoreTests {

    struct TestCandidate: Codable, Sendable, Equatable {
        let id: String
        let value: Int
    }

    @Test("写入并重新读取磁盘缓存")
    func savesAndLoadsDiskCache() throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("JSONLDiskCacheTest-\(UUID().uuidString)")
        let store = SystemJSONLDiskCacheStore<TestCandidate>(fileURL: tempDir.appendingPathComponent("test.json"))

        let metadata = JSONLFileMetadata(
            identity: JSONLFileIdentity(deviceID: 1, fileID: 100),
            size: 512,
            modificationDate: Date(timeIntervalSince1970: 1000)
        )
        let entry = JSONLDiskCacheEntry(
            key: "/path/to/file.jsonl",
            scopeIdentifier: "standard",
            metadata: metadata,
            candidates: [TestCandidate(id: "item1", value: 42)]
        )

        store.saveAll(["/path/to/file.jsonl": entry])

        // 重新构建 store 模拟冷启动读取
        let reloadedStore = SystemJSONLDiskCacheStore<TestCandidate>(fileURL: tempDir.appendingPathComponent("test.json"))
        let loaded = reloadedStore.loadAll()

        #expect(loaded.count == 1)
        #expect(loaded["/path/to/file.jsonl"]?.candidates == [TestCandidate(id: "item1", value: 42)])
        #expect(loaded["/path/to/file.jsonl"]?.metadata.size == 512)

        try? FileManager.default.removeItem(at: tempDir)
    }

    @Test("无效文件或损坏 JSON 时优雅返回空缓存")
    func handlesCorruptedDiskCacheGracefully() throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("JSONLCorruptTest-\(UUID().uuidString)")
        let fileURL = tempDir.appendingPathComponent("corrupt.json")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        try Data("invalid json content".utf8).write(to: fileURL)

        let store = SystemJSONLDiskCacheStore<TestCandidate>(fileURL: fileURL)
        let loaded = store.loadAll()

        #expect(loaded.isEmpty)
        try? FileManager.default.removeItem(at: tempDir)
    }
}
