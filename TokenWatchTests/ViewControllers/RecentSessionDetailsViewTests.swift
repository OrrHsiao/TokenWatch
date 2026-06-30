import AppKit
import Foundation
import Testing
@testable import TokenWatch

@Suite("RecentSessionDetailsView")
struct RecentSessionDetailsViewTests {

    @MainActor
    @Test("渲染最近会话明细行")
    func rendersRows() {
        let view = RecentSessionDetailsView()
        let snapshot = makeSnapshot(rows: [
            makeRow(
                provider: .claude,
                sessionID: "s1",
                projectPath: "/Users/example/project",
                primaryModel: "claude-sonnet-4-5",
                additionalModelCount: 1,
                totalTokens: 170
            ),
        ])

        view.configure(with: snapshot, language: .zhHans)

        #expect(view.debugTitleText == "最近明细")
        #expect(view.debugRowTexts.count == 1)
        #expect(view.debugRowTexts[0].contains("s1"))
        #expect(view.debugRowTexts[0].contains("Claude"))
        #expect(view.debugRowTexts[0].contains("claude-sonnet-4-5 +1"))
        #expect(view.debugRowTexts[0].contains("170"))
        #expect(view.debugEmptyText == "")
    }

    @MainActor
    @Test("空 rows 时展示空状态")
    func rendersEmptyState() {
        let view = RecentSessionDetailsView()

        view.configure(with: makeSnapshot(rows: []), language: .zhHans)

        #expect(view.debugRowTexts.isEmpty)
        #expect(view.debugEmptyText == "当前筛选暂无会话明细")
    }

    @MainActor
    @Test("英文表头和成本记录数字段被渲染")
    func rendersEnglishLabelsCostAndRecords() {
        let view = RecentSessionDetailsView()
        let snapshot = makeSnapshot(rows: [
            makeRow(
                provider: .codex,
                sessionID: "english-session",
                projectPath: nil,
                primaryModel: "gpt-5",
                additionalModelCount: 0,
                totalTokens: 2_400,
                cost: 0.12345,
                entryCount: 7
            ),
        ])

        view.configure(with: snapshot, language: .en)

        #expect(view.debugTitleText == "Recent Details")
        #expect(view.debugHeaderTexts == [
            "Time", "Session", "Tool", "Project", "Model", "Tokens", "Cost", "Records",
        ])
        #expect(view.debugRowTexts.count == 1)
        #expect(view.debugRowTexts[0].contains("Codex"))
        #expect(view.debugRowTexts[0].contains("gpt-5"))
        #expect(view.debugRowTexts[0].contains("$0.1235"))
        #expect(view.debugRowTexts[0].contains("7"))
    }

    private func makeSnapshot(rows: [RecentSessionRow]) -> RecentSessionDetailsSnapshot {
        RecentSessionDetailsSnapshot(
            rows: rows,
            totalSessionCount: rows.count,
            totalTokens: rows.reduce(0) { $0 + $1.totalTokens },
            totalCost: rows.reduce(0) { $0 + $1.cost },
            loadedProviderCount: 1,
            loadingProviderCount: 0,
            unauthorizedProviderCount: 0,
            errorMessages: []
        )
    }

    private func makeRow(
        provider: ProviderID,
        sessionID: String,
        projectPath: String?,
        primaryModel: String,
        additionalModelCount: Int,
        totalTokens: Int,
        cost: Double = 0.0123,
        entryCount: Int = 3
    ) -> RecentSessionRow {
        RecentSessionRow(
            id: "\(provider.rawValue):\(sessionID)",
            provider: provider,
            sessionID: sessionID,
            projectPath: projectPath,
            primaryModel: primaryModel,
            additionalModelCount: additionalModelCount,
            firstActiveAt: Date(timeIntervalSince1970: 1_782_452_800),
            lastActiveAt: Date(timeIntervalSince1970: 1_782_456_400),
            inputTokens: totalTokens,
            outputTokens: 0,
            cacheReadTokens: 0,
            cacheCreationTokens: 0,
            reasoningTokens: 0,
            totalTokens: totalTokens,
            cost: cost,
            entryCount: entryCount,
            modelBreakdown: [:],
            upstreamProviderIDs: [],
            isSubagentIncluded: false
        )
    }
}
