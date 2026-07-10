import Foundation
import Testing
@testable import TokenWatch

@Suite("JSONLFileReader")
struct JSONLFileReaderTests {
    @Test("生产 reader 返回身份大小修改时间并支持 seek read")
    func systemReaderReportsMetadataAndReadsFromOffset() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("JSONLFileReaderTests-\(UUID().uuidString).jsonl")
        try Data("abcdef".utf8).write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }

        let reader = SystemJSONLFileReader()
        let snapshot = try reader.openSnapshot(for: url)
        defer { snapshot.stream.close() }
        try snapshot.stream.seek(toOffset: 2)
        let data = try snapshot.stream.read(upToCount: 3)

        #expect(snapshot.metadata.identity != nil)
        #expect(snapshot.metadata.size == 6)
        #expect(snapshot.metadata.modificationDate != .distantPast)
        #expect(String(decoding: data, as: UTF8.self) == "cde")
    }

    @Test("atomic replace 后 snapshot metadata 与已打开 stream 指向同一文件")
    func snapshotClosesMetadataOpenTOCTOU() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("JSONLSnapshot-\(UUID().uuidString).jsonl")
        try Data("old".utf8).write(to: url, options: .atomic)
        defer { try? FileManager.default.removeItem(at: url) }
        let reader = SystemJSONLFileReader()
        let old = try reader.openSnapshot(for: url)
        defer { old.stream.close() }

        try Data("replacement".utf8).write(to: url, options: .atomic)
        let fresh = try reader.openSnapshot(for: url)
        defer { fresh.stream.close() }
        let oldData = try old.stream.read(upToCount: 64)
        let freshData = try fresh.stream.read(upToCount: 64)

        #expect(String(decoding: oldData, as: UTF8.self) == "old")
        #expect(String(decoding: freshData, as: UTF8.self) == "replacement")
        #expect(old.metadata.identity != fresh.metadata.identity)
    }
}
