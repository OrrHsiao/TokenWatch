import Foundation
import Testing
@testable import TokenWatch

@Suite("DeepSeekHarnessScanner")
struct DeepSeekHarnessScannerTests {
    private let scanner = DeepSeekHarnessScanner()

    @Test("规范文件名解析世代与编码")
    func parsesCanonicalFileNames() {
        #expect(DeepSeekHarnessScanner.parseGeneration(fileName: "session.jsonl")?.generation == 0)
        #expect(DeepSeekHarnessScanner.parseGeneration(fileName: "session.jsonl")?.isCompressed == false)
        #expect(DeepSeekHarnessScanner.parseGeneration(fileName: "session.jsonl.zstd")?.generation == 0)
        #expect(DeepSeekHarnessScanner.parseGeneration(fileName: "session.jsonl.zstd")?.isCompressed == true)
        #expect(DeepSeekHarnessScanner.parseGeneration(fileName: "session.v3.jsonl.zstd")?.generation == 3)
        #expect(DeepSeekHarnessScanner.parseGeneration(fileName: "session.v12.jsonl")?.generation == 12)

        // 非规范名（含 DSH 明确不产出的 `.v0`）必须被忽略。
        #expect(DeepSeekHarnessScanner.parseGeneration(fileName: "session.v0.jsonl") == nil)
        #expect(DeepSeekHarnessScanner.parseGeneration(fileName: "session.v01.jsonl") == nil)
        #expect(DeepSeekHarnessScanner.parseGeneration(fileName: "session.lock") == nil)
        #expect(DeepSeekHarnessScanner.parseGeneration(fileName: "other.v4.jsonl") == nil)
        #expect(DeepSeekHarnessScanner.parseGeneration(fileName: "session.v4.jsonl.zstd.tmp") == nil)
    }

    @Test("同一会话目录只选版本号最高的世代文件")
    func selectsHighestGeneration() throws {
        let directory = try DeepSeekHarnessTestSupport.makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let sessionDirectory = "session-multi-generation"
        try DeepSeekHarnessTestSupport.writeSessionLog(
            root: directory, sessionDirectory: sessionDirectory,
            fileName: "session.jsonl.zstd", contents: Data()
        )
        try DeepSeekHarnessTestSupport.writeSessionLog(
            root: directory, sessionDirectory: sessionDirectory,
            fileName: "session.v3.jsonl.zstd", contents: Data()
        )
        let expected = try DeepSeekHarnessTestSupport.writeSessionLog(
            root: directory, sessionDirectory: sessionDirectory,
            fileName: "session.v4.jsonl.zstd", contents: Data()
        )

        let files = try scanner.locateSessionLogFiles(in: directory)
        #expect(files.count == 1)
        #expect(files.first?.url.lastPathComponent == "session.v4.jsonl.zstd")
        #expect(files.first?.generation == expected.generation)
    }

    @Test("多个会话目录各自选出自己的世代文件")
    func selectsPerSessionDirectory() throws {
        let directory = try DeepSeekHarnessTestSupport.makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        try DeepSeekHarnessTestSupport.writeSessionLog(
            root: directory, sessionDirectory: "session-one",
            fileName: "session.jsonl.zstd", contents: Data()
        )
        try DeepSeekHarnessTestSupport.writeSessionLog(
            root: directory, sessionDirectory: "session-two",
            fileName: "session.v3.jsonl.zstd", contents: Data()
        )

        let files = try scanner.locateSessionLogFiles(in: directory)
        #expect(files.count == 2)
        #expect(Set(files.map { $0.url.deletingLastPathComponent().lastPathComponent })
            == ["session-one", "session-two"])
    }

    @Test("目录不存在时返回空列表而不是抛错")
    func missingSessionsDirectoryReturnsEmpty() throws {
        let directory = try DeepSeekHarnessTestSupport.makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        #expect(try scanner.locateSessionLogFiles(in: directory).isEmpty)
    }

    @Test("数据根既接受 ~/.dsh 也接受 ~/.dsh/sessions")
    func resolvesDataRoots() throws {
        let directory = try DeepSeekHarnessTestSupport.makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let sessions = directory.appendingPathComponent("sessions", isDirectory: true)
        try FileManager.default.createDirectory(at: sessions, withIntermediateDirectories: true)

        let fromHome = scanner.resolveDataRoots(directory)
        #expect(fromHome.sessionsRoot.standardizedFileURL == sessions.standardizedFileURL)
        #expect(fromHome.dshHome?.standardizedFileURL == directory.standardizedFileURL)

        let fromSessions = scanner.resolveDataRoots(sessions)
        #expect(fromSessions.sessionsRoot.standardizedFileURL == sessions.standardizedFileURL)
        #expect(fromSessions.dshHome?.standardizedFileURL == directory.standardizedFileURL)

        #expect(scanner.validateDataRoot(directory) == .valid)
        #expect(scanner.validateDataRoot(sessions) == .valid)

        let unrelated = directory.appendingPathComponent("unrelated", isDirectory: true)
        try FileManager.default.createDirectory(at: unrelated, withIntermediateDirectories: true)
        #expect(scanner.validateDataRoot(unrelated) == .missingExpectedStructure)
    }

    @Test("provider 端到端：世代去重后同一会话只统计一次")
    func providerDeduplicatesGenerations() throws {
        let directory = try DeepSeekHarnessTestSupport.makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let sessionDirectory = "session-generation-dedup"
        // v0 与 v3 是同一会话的两种编码（历史迁移保留旧文件）。
        let legacy = DeepSeekHarnessTestSupport.logContents([
            DeepSeekHarnessTestSupport.headerLine(id: "session-generation-dedup", version: 0),
            DeepSeekHarnessTestSupport.assistantMessageLine(
                sequence: 0, time: 1_000, turn: 1, step: 1, messageID: "msg-legacy",
                inputTokens: 500, outputTokens: 50
            ),
        ])
        try DeepSeekHarnessTestSupport.writeSessionLog(
            root: directory, sessionDirectory: sessionDirectory,
            fileName: "session.jsonl", contents: legacy
        )
        try DeepSeekHarnessTestSupport.writeSessionLog(
            root: directory, sessionDirectory: sessionDirectory,
            fileName: "session.v3.jsonl",
            contents: DeepSeekHarnessTestSupport.logContents([
                DeepSeekHarnessTestSupport.headerLine(id: "session-generation-dedup", version: 3),
                DeepSeekHarnessTestSupport.assistantMessageLine(
                    sequence: 0, time: 1_000, turn: 1, step: 1, messageID: "msg-current",
                    inputTokens: 500, outputTokens: 50
                ),
            ])
        )

        let provider = DeepSeekHarnessProvider(diskStore: nil)
        let entries = try provider.loadEntries(from: directory)

        #expect(entries.count == 1)
        #expect(entries.first?.messageId == "msg-current")
        #expect(entries.first?.usage.inputTokens == 500)
    }

    @Test("provider 在源未变化时可跳过条目物化")
    func providerReportsUnchangedSource() throws {
        let directory = try DeepSeekHarnessTestSupport.makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        try DeepSeekHarnessTestSupport.writeSessionLog(
            root: directory, sessionDirectory: "session-cache-status",
            fileName: "session.v4.jsonl",
            contents: DeepSeekHarnessTestSupport.logContents([
                DeepSeekHarnessTestSupport.headerLine(id: "session-cache-status"),
                DeepSeekHarnessTestSupport.assistantMessageLine(
                    sequence: 0, time: 1_000, turn: 1, step: 1, messageID: "msg-cache",
                    inputTokens: 1, outputTokens: 1
                ),
            ])
        )

        let provider = DeepSeekHarnessProvider(diskStore: nil)
        let first = try provider.loadEntriesWithCacheStatus(
            from: directory,
            materializeEntriesWhenUnchanged: true
        )
        #expect(first.didChange)
        #expect(first.entries?.count == 1)
        #expect(first.sourceRevision?.isEmpty == false)

        let second = try provider.loadEntriesWithCacheStatus(
            from: directory,
            materializeEntriesWhenUnchanged: false
        )
        #expect(!second.didChange)
        #expect(second.entries == nil)
        #expect(second.sourceRevision == first.sourceRevision)
    }
}
