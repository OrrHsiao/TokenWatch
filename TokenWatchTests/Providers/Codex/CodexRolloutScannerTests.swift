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
}
