import Foundation
import Testing
@testable import TokenWatch

@Suite("ProviderStatsSnapshotStore")
struct ProviderStatsSnapshotStoreTests {
    @Test("最终聚合统计可完整写入并冷启动读取")
    func snapshotRoundTrips() throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let source = makeSnapshot()

        try SystemProviderStatsSnapshotStore(directoryURL: directory).save(source)

        let reloadedStore = SystemProviderStatsSnapshotStore(directoryURL: directory)
        #expect(reloadedStore.load(for: .codex) == source)
    }

    @Test("损坏的快照返回 nil")
    func corruptSnapshotReturnsNil() throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        try Data("not-json".utf8).write(
            to: directory.appendingPathComponent("codex.json")
        )

        let store = SystemProviderStatsSnapshotStore(directoryURL: directory)
        #expect(store.load(for: .codex) == nil)
    }

    @Test("不兼容版本的快照返回 nil")
    func unsupportedSchemaReturnsNil() throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let unsupported = makeSnapshot(
            schemaVersion: ProviderStatsSnapshot.currentSchemaVersion + 1
        )
        try JSONEncoder().encode(unsupported).write(
            to: directory.appendingPathComponent("codex.json")
        )

        let store = SystemProviderStatsSnapshotStore(directoryURL: directory)
        #expect(store.load(for: .codex) == nil)
    }

    private func makeTemporaryDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(
            "ProviderStatsSnapshotStoreTests-\(UUID().uuidString)",
            isDirectory: true
        )
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        return directory
    }

    private func makeSnapshot(schemaVersion: Int = ProviderStatsSnapshot.currentSchemaVersion)
        -> ProviderStatsSnapshot {
        let modelSummary = UsageSummary(
            inputTokens: 10,
            outputTokens: 20,
            cacheReadTokens: 30,
            cacheCreationTokens: 40,
            reasoningTokens: 5,
            totalTokens: 105,
            cost: 1.25,
            entryCount: 2,
            modelBreakdown: [:],
            projectBreakdown: [:]
        )
        let overall = UsageSummary(
            inputTokens: 10,
            outputTokens: 20,
            cacheReadTokens: 30,
            cacheCreationTokens: 40,
            reasoningTokens: 5,
            totalTokens: 105,
            cost: 1.25,
            entryCount: 2,
            modelBreakdown: ["gpt-5": modelSummary],
            projectBreakdown: ["/project": modelSummary]
        )
        let stats = AggregatedStats(
            overall: overall,
            byHour: ["2026-08-03T10": overall],
            byDay: ["2026-08-03": overall],
            byWeek: ["2026-W32": overall],
            byMonth: ["2026-08": overall],
            bySession: ["session": overall],
            byModel: ["gpt-5": modelSummary],
            byProject: ["/project": modelSummary],
            dataSourceCount: 3
        )
        return ProviderStatsSnapshot(
            providerID: .codex,
            stats: stats,
            generatedAt: Date(timeIntervalSince1970: 1_786_000_000),
            dataRootPath: "/Users/example/.codex",
            timeZoneIdentifier: "Asia/Shanghai",
            sourceRevision: "manifest-digest",
            schemaVersion: schemaVersion
        )
    }
}
