import Foundation
import Testing
@testable import TokenWatch

@Suite("JSONLDiskCacheStore")
struct JSONLDiskCacheStoreTests {

    struct TestState: Codable, Sendable, Equatable {
        let committedOffset: UInt64
        let candidates: [String]
    }

    @Test("写入并重新读取磁盘缓存")
    func savesAndLoadsDiskCache() throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("JSONLDiskCacheTest-\(UUID().uuidString)")
        let store = SystemJSONLDiskCacheStore<TestState>(fileURL: tempDir.appendingPathComponent("test.json"))

        let metadata = JSONLFileMetadata(
            identity: JSONLFileIdentity(deviceID: 1, fileID: 100),
            size: 512,
            modificationDate: Date(timeIntervalSince1970: 1000)
        )
        let entry = JSONLDiskCacheEntry(
            key: "/path/to/file.jsonl",
            scopeIdentifier: "standard",
            metadata: metadata,
            state: TestState(
                committedOffset: 384,
                candidates: ["item1"]
            )
        )

        store.saveAll(["/path/to/file.jsonl": entry])

        // 重新构建 store 模拟冷启动读取
        let reloadedStore = SystemJSONLDiskCacheStore<TestState>(fileURL: tempDir.appendingPathComponent("test.json"))
        let loaded = reloadedStore.loadAll()

        #expect(loaded.count == 1)
        #expect(loaded["/path/to/file.jsonl"]?.state == TestState(
            committedOffset: 384,
            candidates: ["item1"]
        ))
        #expect(loaded["/path/to/file.jsonl"]?.metadata.size == 512)

        try? FileManager.default.removeItem(at: tempDir)
    }

    @Test("无效文件或损坏 JSON 时优雅返回空缓存")
    func handlesCorruptedDiskCacheGracefully() throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("JSONLCorruptTest-\(UUID().uuidString)")
        let fileURL = tempDir.appendingPathComponent("corrupt.json")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        try Data("invalid json content".utf8).write(to: fileURL)

        let store = SystemJSONLDiskCacheStore<TestState>(fileURL: fileURL)
        let loaded = store.loadAll()

        #expect(loaded.isEmpty)
        try? FileManager.default.removeItem(at: tempDir)
    }

    @Test("不同 cacheVersion 的 store 互不读取对方 payload")
    func versionMismatchDiscardsPayload() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("JSONLVersionTest-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        let fileURL = tempDir.appendingPathComponent("versioned.json")

        let metadata = JSONLFileMetadata(
            identity: JSONLFileIdentity(deviceID: 1, fileID: 100),
            size: 512,
            modificationDate: Date(timeIntervalSince1970: 1000)
        )
        let entry = JSONLDiskCacheEntry(
            key: "/path/to/file.jsonl",
            scopeIdentifier: "standard",
            metadata: metadata,
            state: TestState(committedOffset: 384, candidates: ["item1"])
        )

        // 版本 2 写入
        let v2Writer = SystemJSONLDiskCacheStore<TestState>(fileURL: fileURL, cacheVersion: 2)
        v2Writer.saveAll(["/path/to/file.jsonl": entry])

        // 版本 3 读取 → 版本不匹配，丢弃旧 payload
        let v3Reader = SystemJSONLDiskCacheStore<TestState>(fileURL: fileURL, cacheVersion: 3)
        #expect(v3Reader.loadAll().isEmpty)

        // 版本 2 仍可读取自己的 payload
        let v2Reader = SystemJSONLDiskCacheStore<TestState>(fileURL: fileURL, cacheVersion: 2)
        #expect(v2Reader.loadAll().count == 1)

        try? FileManager.default.removeItem(at: tempDir)
    }
}
