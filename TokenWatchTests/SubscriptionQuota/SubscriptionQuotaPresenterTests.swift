import Foundation
import Testing
@testable import TokenWatch

@Suite("SubscriptionQuotaPresenter")
struct SubscriptionQuotaPresenterTests {
    private let now = Date(timeIntervalSince1970: 1_793_170_000)

    @Test("剩余百分比：0% 只表示来源报告用尽，正剩余不足 1% 显示 <1%，其余向下取整")
    func percentTextBoundaries() {
        #expect(SubscriptionQuotaPresenter.percentText(remainingPercent: 0) == "0%")
        #expect(SubscriptionQuotaPresenter.percentText(remainingPercent: 0.4) == "<1%")
        #expect(SubscriptionQuotaPresenter.percentText(remainingPercent: 1) == "1%")
        #expect(SubscriptionQuotaPresenter.percentText(remainingPercent: 99.6) == "99%")
        #expect(SubscriptionQuotaPresenter.percentText(remainingPercent: 100) == "100%")
    }

    @Test("剩余 ≤20% 为警告，≤10% 为危险")
    func severityThresholds() {
        #expect(SubscriptionQuotaPresenter.severity(remainingPercent: 21) == .normal)
        #expect(SubscriptionQuotaPresenter.severity(remainingPercent: 20) == .warning)
        #expect(SubscriptionQuotaPresenter.severity(remainingPercent: 10.5) == .warning)
        #expect(SubscriptionQuotaPresenter.severity(remainingPercent: 10) == .danger)
        #expect(SubscriptionQuotaPresenter.severity(remainingPercent: 0) == .danger)
    }

    @Test("有效快照展示剩余、倒计时和来源记录时间")
    func freshSnapshotShowsRemainingAndCountdown() throws {
        let presentation = make(.snapshot(snapshot(
            recordedSecondsAgo: 120,
            fiveHour: (used: 32, resetsIn: 2 * 3_600 + 14 * 60 + 30),
            sevenDay: (used: 92, resetsIn: 3 * 86_400 + 5 * 3_600 + 30)
        )))

        #expect(presentation.statusText == "记录于 2 分钟前")
        #expect(!presentation.isStale)
        #expect(!presentation.isStatusHighlighted)
        #expect(presentation.message == nil)
        #expect(presentation.windows.map(\.kind) == [.fiveHour, .sevenDay])

        let fiveHour = try #require(presentation.windows.first)
        #expect(fiveHour.title == "5 小时")
        #expect(fiveHour.shortLabel == "5H")
        #expect(fiveHour.valueText == "68%")
        #expect(fiveHour.remainingPercent == 68)
        #expect(fiveHour.severity == .normal)
        #expect(fiveHour.detailText == "2小时14分钟后重置")

        let sevenDay = try #require(presentation.windows.last)
        #expect(sevenDay.title == "一周")
        #expect(sevenDay.valueText == "8%")
        #expect(sevenDay.severity == .danger)
        #expect(sevenDay.detailText == "3天5小时后重置")
    }

    @Test("0% 明确提示额度已用尽")
    func exhaustedWindowSaysUsedUp() throws {
        let presentation = make(.snapshot(snapshot(fiveHour: (used: 100, resetsIn: 600))))
        let fiveHour = try #require(presentation.windows.first)

        #expect(fiveHour.valueText == "0%")
        #expect(fiveHour.severity == .danger)
        #expect(fiveHour.detailText == "额度已用尽 · 10分钟后重置")
    }

    @Test("超过 60 分钟的快照标记旧记录并弱化，不再强调低额度颜色")
    func staleSnapshotIsMarkedAndNotEmphasized() throws {
        let presentation = make(.snapshot(snapshot(
            recordedSecondsAgo: 2 * 3_600 + 10,
            fiveHour: (used: 95, resetsIn: 3_600)
        )))
        let fiveHour = try #require(presentation.windows.first)

        #expect(presentation.isStale)
        #expect(presentation.isStatusHighlighted)
        #expect(presentation.statusText == "记录于 2 小时前 · 旧记录")
        #expect(fiveHour.valueText == "5%")
        #expect(fiveHour.isStale)
        #expect(fiveHour.severity == .normal)
    }

    @Test("已跨过重置点却没有新快照时显示等待新记录，不推断为 100%")
    func passedResetWaitsForNewRecord() throws {
        let presentation = make(.snapshot(snapshot(fiveHour: (used: 80, resetsIn: -60))))
        let fiveHour = try #require(presentation.windows.first)

        #expect(fiveHour.remainingPercent == nil)
        #expect(fiveHour.valueText == "—")
        #expect(fiveHour.detailText == "等待新记录")
    }

    @Test("重置时间未知与窗口缺失分开提示")
    func unknownResetAndMissingWindowAreDistinct() throws {
        var windows: [SubscriptionQuotaWindowKind: SubscriptionQuotaWindow] = [:]
        windows[.fiveHour] = SubscriptionQuotaWindow(usedPercent: 10, resetsAt: nil)
        let presentation = make(.snapshot(SubscriptionQuotaSnapshot(
            provider: .claude,
            accountID: nil,
            bucketID: nil,
            recordedAt: now,
            windows: windows
        )))

        #expect(presentation.windows[0].valueText == "90%")
        #expect(presentation.windows[0].detailText == "重置时间未知")
        #expect(presentation.windows[1].valueText == "—")
        #expect(presentation.windows[1].detailText == "尚无额度记录")
    }

    @Test("未授权时展示简短授权入口，两个工具使用各自的授权动作")
    func notAuthorizedShowsProviderSpecificAction() {
        let claude = make(.notAuthorized, provider: .claude)
        #expect(claude.message == "尚未读取额度")
        #expect(claude.action == .chooseClaudeFile)
        #expect(claude.actionTitle == "选择额度文件")
        #expect(claude.windows.allSatisfy { $0.valueText == "—" })

        let codex = make(.notAuthorized, provider: .codex)
        #expect(codex.action == .authorizeCodexDirectory)
        #expect(codex.actionTitle == "去授权")
    }

    @Test("已授权但来源未记录额度时窗口显示尚无额度记录")
    func noRecordShowsDashes() {
        let presentation = make(.noRecord)

        #expect(presentation.message == nil)
        #expect(presentation.windows.allSatisfy { $0.valueText == "—" && $0.detailText == "尚无额度记录" })
    }

    @Test("读取失败保留最后有效快照并继续计龄；从未成功时只提示读取失败")
    func readFailureKeepsLastSnapshot() throws {
        let kept = SubscriptionQuotaPresenter.make(
            provider: .codex,
            state: SubscriptionQuotaProviderState(
                result: .snapshot(snapshot(recordedSecondsAgo: 5 * 60, fiveHour: (used: 40, resetsIn: 3_600))),
                lastReadFailed: true
            ),
            now: now,
            language: .zhHans
        )
        #expect(kept.statusText == "记录于 5 分钟前 · 读取失败")
        #expect(kept.isStatusHighlighted)
        #expect(try #require(kept.windows.first).valueText == "60%")

        let neverRead = SubscriptionQuotaPresenter.make(
            provider: .codex,
            state: SubscriptionQuotaProviderState(result: nil, lastReadFailed: true),
            now: now,
            language: .zhHans
        )
        #expect(neverRead.message == "读取失败")
        #expect(neverRead.action == nil)
    }

    @Test("英文文案与悬停说明按工具分组")
    func englishToolTipGroupsByProvider() {
        let presentations = [
            SubscriptionQuotaPresenter.make(
                provider: .claude,
                state: SubscriptionQuotaProviderState(result: .notAuthorized, lastReadFailed: false),
                now: now,
                language: .en
            ),
            SubscriptionQuotaPresenter.make(
                provider: .codex,
                state: SubscriptionQuotaProviderState(
                    result: .snapshot(snapshot(provider: .codex, recordedSecondsAgo: 10, fiveHour: (used: 12, resetsIn: 3_600))),
                    lastReadFailed: false
                ),
                now: now,
                language: .en
            ),
        ]

        #expect(SubscriptionQuotaPresenter.toolTip(for: presentations, language: .en) == """
        Claude · Usage not read yet

        Codex · Recorded just now
        5 hours · 88% left · Resets in 1h
        Week · — · No usage record yet
        """)
    }

    // MARK: - Helpers

    private func make(
        _ result: SubscriptionQuotaReadResult,
        provider: SubscriptionQuotaProvider = .claude
    ) -> SubscriptionQuotaProviderPresentation {
        SubscriptionQuotaPresenter.make(
            provider: provider,
            state: SubscriptionQuotaProviderState(result: result, lastReadFailed: false),
            now: now,
            language: .zhHans
        )
    }

    private func snapshot(
        provider: SubscriptionQuotaProvider = .claude,
        recordedSecondsAgo: TimeInterval = 0,
        fiveHour: (used: Double, resetsIn: TimeInterval)? = nil,
        sevenDay: (used: Double, resetsIn: TimeInterval)? = nil
    ) -> SubscriptionQuotaSnapshot {
        var windows: [SubscriptionQuotaWindowKind: SubscriptionQuotaWindow] = [:]
        if let fiveHour {
            windows[.fiveHour] = SubscriptionQuotaWindow(
                usedPercent: fiveHour.used,
                resetsAt: now.addingTimeInterval(fiveHour.resetsIn)
            )
        }
        if let sevenDay {
            windows[.sevenDay] = SubscriptionQuotaWindow(
                usedPercent: sevenDay.used,
                resetsAt: now.addingTimeInterval(sevenDay.resetsIn)
            )
        }
        return SubscriptionQuotaSnapshot(
            provider: provider,
            accountID: nil,
            bucketID: nil,
            recordedAt: now.addingTimeInterval(-recordedSecondsAgo),
            windows: windows
        )
    }
}
