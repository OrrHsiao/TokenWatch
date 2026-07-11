import Testing
import Foundation
@testable import TokenWatch

@Suite("CodexRolloutScanner")
struct CodexRolloutScannerTests {

    /// 在临时目录构造一个简化的 Codex 数据结构
    /// 返回 (rootURL, cleanup)
    private func makeFixture() throws -> (URL, () -> Void) {
        let root = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("codex-test-\(UUID().uuidString)", isDirectory: true)
        let fm = FileManager.default

        let sessions = root.appendingPathComponent("sessions/2026/05/04", isDirectory: true)
        let archived = root.appendingPathComponent("archived_sessions/2026/05/04", isDirectory: true)
        try fm.createDirectory(at: sessions, withIntermediateDirectories: true)
        try fm.createDirectory(at: archived, withIntermediateDirectories: true)

        // 主目录下 2 个 rollout
        try Data().write(to: sessions.appendingPathComponent("rollout-2026-05-04T16-35-18-019df220-aaaa-bbbb-cccc-ddddeeeeffff.jsonl"))
        try Data().write(to: sessions.appendingPathComponent("rollout-2026-05-04T17-00-00-019df221-1111-2222-3333-444455556666.jsonl"))
        // archived 一个与主目录同名(以相对路径计),应被去重
        try Data().write(to: archived.appendingPathComponent("rollout-2026-05-04T16-35-18-019df220-aaaa-bbbb-cccc-ddddeeeeffff.jsonl"))
        // archived 一个独立的
        try Data().write(to: archived.appendingPathComponent("rollout-2026-05-04T18-00-00-019df222-7777-8888-9999-aaaabbbbcccc.jsonl"))
        // 一个非 jsonl 文件(应忽略)
        try Data().write(to: sessions.appendingPathComponent("not-a-rollout.txt"))

        let cleanup: () -> Void = { _ = try? fm.removeItem(at: root) }
        return (root, cleanup)
    }

    @Test("递归扫 sessions/ + archived_sessions/,去重保留 sessions/ 优先")
    func scansAndDedupes() throws {
        let (root, cleanup) = try makeFixture()
        defer { cleanup() }

        let scanner = CodexRolloutScanner()
        let files = try scanner.scanAll(in: root)

        #expect(files.count == 3)  // 2 sessions + 1 唯一 archived;同名 archived 被剔除

        // 同名(16-35-18 那条)应来自 sessions/,不应来自 archived_sessions/
        let dupName = "rollout-2026-05-04T16-35-18-019df220-aaaa-bbbb-cccc-ddddeeeeffff.jsonl"
        let chosen = files.first(where: { $0.url.lastPathComponent == dupName })
        #expect(chosen != nil)
        #expect(chosen?.url.path.contains("/sessions/") == true)
        #expect(chosen?.url.path.contains("/archived_sessions/") == false)
    }

    @Test("从文件名推断 sessionID")
    func extractsSessionIDFromFilename() throws {
        let (root, cleanup) = try makeFixture()
        defer { cleanup() }

        let scanner = CodexRolloutScanner()
        let files = try scanner.scanAll(in: root)
        let target = files.first(where: {
            $0.url.lastPathComponent.contains("019df220-aaaa")
        })
        #expect(target?.sessionID == "019df220-aaaa-bbbb-cccc-ddddeeeeffff")
    }

    @Test("非 jsonl 文件被忽略")
    func ignoresNonJsonl() throws {
        let (root, cleanup) = try makeFixture()
        defer { cleanup() }

        let scanner = CodexRolloutScanner()
        let files = try scanner.scanAll(in: root)
        #expect(files.allSatisfy { $0.url.pathExtension == "jsonl" })
    }

    @Test("根目录不存在时返回空数组,不抛错")
    func missingRootReturnsEmpty() throws {
        let nonExistent = URL(fileURLWithPath: "/tmp/codex-non-existent-\(UUID().uuidString)")
        let scanner = CodexRolloutScanner()
        let files = try scanner.scanAll(in: nonExistent)
        #expect(files.isEmpty)
    }

    @Test("目录枚举失败向上抛出,不伪装成空扫描")
    func enumerationFailureIsPropagated() {
        let scanner = CodexRolloutScanner(directoryLister: FailingCodexDirectoryLister())

        #expect(throws: InjectedCodexDirectoryListingError.self) {
            try scanner.scanAll(in: URL(fileURLWithPath: "/tmp/codex-enumeration-failure"))
        }
    }

    @Test("live 枚举成功但 archived 失败时整次扫描失败")
    func archivedEnumerationFailureDiscardsLiveResults() {
        let root = URL(fileURLWithPath: "/tmp/codex-archived-enumeration-failure", isDirectory: true)
        let sessions = root.appendingPathComponent("sessions", isDirectory: true)
        let liveFile = sessions.appendingPathComponent(
            "2026/05/04/rollout-live-00000000-0000-0000-0000-000000000001.jsonl"
        )
        let scanner = CodexRolloutScanner(
            directoryLister: ArchivedFailingCodexDirectoryLister(liveFile: liveFile)
        )

        #expect(throws: InjectedCodexDirectoryListingError.self) {
            try scanner.scanAll(in: root)
        }
    }

    @Test("live 与 archived 各自按路径排序且 live 保持优先")
    func scanOrderIsDeterministicAcrossDirectoryEnumerationOrder() throws {
        let root = URL(fileURLWithPath: "/tmp/codex-deterministic-order", isDirectory: true)
        let sessions = root.appendingPathComponent("sessions", isDirectory: true)
        let archived = root.appendingPathComponent("archived_sessions", isDirectory: true)
        let liveA = sessions.appendingPathComponent(
            "2026/05/04/rollout-a-00000000-0000-0000-0000-000000000001.jsonl"
        )
        let liveZ = sessions.appendingPathComponent(
            "2026/05/04/rollout-z-00000000-0000-0000-0000-000000000002.jsonl"
        )
        let archivedB = archived.appendingPathComponent(
            "2026/05/04/rollout-b-00000000-0000-0000-0000-000000000003.jsonl"
        )
        let archivedY = archived.appendingPathComponent(
            "2026/05/04/rollout-y-00000000-0000-0000-0000-000000000004.jsonl"
        )
        let lister = StubCodexDirectoryLister(listings: [
            sessions.standardizedFileURL.path: [liveZ, liveA],
            archived.standardizedFileURL.path: [archivedY, archivedB],
        ])

        let files = try CodexRolloutScanner(directoryLister: lister).scanAll(in: root)

        #expect(files.map(\.url) == [liveA, liveZ, archivedB, archivedY])
        #expect(files.map(\.isArchived) == [false, false, true, true])
    }

    @Test("逆序枚举经 scanner 到 parser 后仍由字典序文件稳定赢得 first-wins")
    func deterministicScanOrderStabilizesParserAttribution() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("CodexScannerAttribution-\(UUID().uuidString)", isDirectory: true)
        let sessions = root.appendingPathComponent("sessions", isDirectory: true)
        let liveA = sessions.appendingPathComponent(
            "2026/05/04/rollout-a-00000000-0000-0000-0000-000000000001.jsonl"
        )
        let liveZ = sessions.appendingPathComponent(
            "2026/05/04/rollout-z-00000000-0000-0000-0000-000000000002.jsonl"
        )
        try FileManager.default.createDirectory(
            at: liveA.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        defer { try? FileManager.default.removeItem(at: root) }

        let turnContext = #"{"timestamp":"2026-05-04T08:35:44.717Z","type":"turn_context","payload":{"model":"gpt-5"}}"#
        let usageEvent = #"{"timestamp":"2026-05-04T08:35:59.868Z","type":"event_msg","payload":{"type":"token_count","info":{"last_token_usage":{"input_tokens":1000,"cached_input_tokens":300,"output_tokens":200,"reasoning_output_tokens":50,"total_tokens":1200}}}}"#
        func writeSession(to url: URL, id: String, cwd: String) throws {
            let metadata = #"{"timestamp":"2026-05-04T08:35:44.692Z","type":"session_meta","payload":{"id":"\#(id)","cwd":"\#(cwd)","model_provider":"openai"}}"#
            try ([metadata, turnContext, usageEvent].joined(separator: "\n") + "\n")
                .write(to: url, atomically: true, encoding: .utf8)
        }
        try writeSession(to: liveA, id: "session-a", cwd: "/project/a")
        try writeSession(to: liveZ, id: "session-z", cwd: "/project/z")

        let lister = StubCodexDirectoryLister(listings: [
            sessions.standardizedFileURL.path: [liveZ, liveA],
        ])
        let files = try CodexRolloutScanner(directoryLister: lister).scanAll(in: root)
        let entries = try CodexRolloutParser().parseAllFiles(files)

        #expect(entries.count == 1)
        #expect(entries.first?.sessionID == "session-a")
        #expect(entries.first?.cwd == "/project/a")
    }
}

private enum InjectedCodexDirectoryListingError: Error {
    case failed
}

private struct FailingCodexDirectoryLister: JSONLDirectoryListing {
    func recursiveFileURLs(in directory: URL) throws -> [URL] {
        throw InjectedCodexDirectoryListingError.failed
    }
}

private struct ArchivedFailingCodexDirectoryLister: JSONLDirectoryListing {
    let liveFile: URL

    func recursiveFileURLs(in directory: URL) throws -> [URL] {
        if directory.lastPathComponent == "archived_sessions" {
            throw InjectedCodexDirectoryListingError.failed
        }
        return [liveFile]
    }
}

private struct StubCodexDirectoryLister: JSONLDirectoryListing {
    let listings: [String: [URL]]

    func recursiveFileURLs(in directory: URL) throws -> [URL] {
        listings[directory.standardizedFileURL.path] ?? []
    }
}
