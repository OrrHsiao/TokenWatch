import Foundation
import Testing
@testable import TokenWatch

@Suite("CodexQuotaReader")
struct CodexQuotaReaderTests {

    @Test("按窗口时长识别 5 小时与一周，Unix 秒重置时间与事件时间保持原值")
    func decodesWindowsByDuration() throws {
        let event = try #require(CodexQuotaReader.decodeQuotaEvent(from: line(
            timestamp: "2026-10-28T07:11:16.314Z",
            primary: window(used: 12, minutes: 300, resetsAt: 1_793_188_826),
            secondary: window(used: 2.5, minutes: 10_080, resetsAt: 1_793_775_626)
        )))

        #expect(event.bucketID == "codex")
        #expect(event.recordedAt == ISO8601DateFormatterHelper.parse("2026-10-28T07:11:16.314Z"))
        #expect(event.windows[.fiveHour]?.usedPercent == 12)
        #expect(event.windows[.fiveHour]?.resetsAt == Date(timeIntervalSince1970: 1_793_188_826))
        #expect(event.windows[.sevenDay]?.usedPercent == 2.5)
        #expect(event.windows[.sevenDay]?.resetsAt == Date(timeIntervalSince1970: 1_793_775_626))
    }

    @Test("primary / secondary 顺序变化不导致窗口误认")
    func swappedPrimaryAndSecondaryAreMappedByDuration() throws {
        let event = try #require(CodexQuotaReader.decodeQuotaEvent(from: line(
            primary: window(used: 40, minutes: 10_080, resetsAt: 1_793_775_626),
            secondary: window(used: 70, minutes: 300, resetsAt: 1_793_188_826)
        )))

        #expect(event.windows[.fiveHour]?.usedPercent == 70)
        #expect(event.windows[.sevenDay]?.usedPercent == 40)
    }

    @Test("一个窗口缺失或损坏不吞掉另一个窗口")
    func missingWindowDoesNotDropTheOther() throws {
        let missingPrimary = try #require(CodexQuotaReader.decodeQuotaEvent(from: line(
            primary: "null",
            secondary: window(used: 5, minutes: 10_080, resetsAt: 1_793_775_626)
        )))
        #expect(missingPrimary.windows[.fiveHour] == nil)
        #expect(missingPrimary.windows[.sevenDay]?.usedPercent == 5)

        let corruptPrimary = try #require(CodexQuotaReader.decodeQuotaEvent(from: line(
            primary: #"{"used_percent": "bad", "window_minutes": 300}"#,
            secondary: window(used: 5, minutes: 10_080, resetsAt: nil)
        )))
        #expect(corruptPrimary.windows[.fiveHour] == nil)
        #expect(corruptPrimary.windows[.sevenDay]?.resetsAt == nil)
    }

    @Test("info 为 null 的纯额度事件同样可以更新额度")
    func rateLimitOnlyEventWithoutInfoIsAccepted() {
        #expect(CodexQuotaReader.decodeQuotaEvent(from: line(
            info: "null",
            primary: window(used: 1, minutes: 300, resetsAt: 1_793_188_826)
        )) != nil)
    }

    @Test("其他额度桶、无窗口和缺失 rate_limits 的事件被忽略，不与主额度桶合并")
    func otherBucketsAndEmptyEventsAreIgnored() {
        #expect(CodexQuotaReader.decodeQuotaEvent(from: line(
            limitID: "premium",
            primary: window(used: 1, minutes: 300, resetsAt: 1_793_188_826)
        )) == nil)
        #expect(CodexQuotaReader.decodeQuotaEvent(from: line(primary: "null", secondary: "null")) == nil)
        #expect(CodexQuotaReader.decodeQuotaEvent(from: Data(
            #"{"timestamp":"2026-10-28T07:11:16.314Z","type":"event_msg","payload":{"type":"token_count","info":null,"rate_limits":null}}"#.utf8
        )) == nil)
        #expect(CodexQuotaReader.decodeQuotaEvent(from: line(
            primary: window(used: 1, minutes: 60, resetsAt: 1_793_188_826)
        )) == nil)
    }

    @Test("缺少 limit_id 的旧日志归入默认额度桶")
    func missingLimitIDUsesDefaultBucket() throws {
        let event = try #require(CodexQuotaReader.decodeQuotaEvent(from: line(
            limitID: nil,
            primary: window(used: 1, minutes: 300, resetsAt: 1_793_188_826)
        )))
        #expect(event.bucketID == CodexQuotaReader.defaultBucketID)
    }

    @Test("跨文件按事件时间选择最新快照，不只看文件名；末尾半行被跳过")
    func readSelectsNewestEventAcrossFiles() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }

        // 文件名更新但事件更旧。
        try fixture.writeRollout(
            relativePath: "sessions/2026/10/28/rollout-2026-10-28T10-00-00-\(uuid(1)).jsonl",
            lines: [
                sessionMeta(accountID: "account-a"),
                String(decoding: line(timestamp: "2026-10-28T06:00:00.000Z", primary: window(used: 50, minutes: 300, resetsAt: 1_793_188_826)), as: UTF8.self),
            ],
            modificationDate: Date(timeIntervalSince1970: 1_793_169_000)
        )
        // 恢复的旧会话追加了更新的事件，末尾还有一条未写完的半行。
        try fixture.writeRollout(
            relativePath: "sessions/2026/10/20/rollout-2026-10-20T10-00-00-\(uuid(2)).jsonl",
            lines: [
                sessionMeta(accountID: "account-b"),
                String(decoding: line(timestamp: "2026-10-28T07:00:00.000Z", primary: window(used: 20, minutes: 300, resetsAt: 1_793_188_826)), as: UTF8.self),
                #"{"timestamp":"2026-10-28T07:05:00.000Z","type":"event_msg","payload":{"type":"token_count","rate_limits":{"primary":{"used_percent":99"#,
            ],
            modificationDate: Date(timeIntervalSince1970: 1_793_170_000),
            endsWithNewline: false
        )

        let result = try CodexQuotaReader().read(codexRoot: fixture.root)
        guard case .snapshot(let snapshot) = result else {
            Issue.record("Expected a snapshot, got \(result)")
            return
        }
        #expect(snapshot.windows[.fiveHour]?.usedPercent == 20)
        #expect(snapshot.recordedAt == ISO8601DateFormatterHelper.parse("2026-10-28T07:00:00.000Z"))
        #expect(snapshot.accountID == "account-b")
        #expect(snapshot.bucketID == "codex")
    }

    @Test("文件追加新的额度事件后，复用缓存的读取器返回新快照")
    func appendedEventInvalidatesCachedFile() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let path = "sessions/2026/10/28/rollout-2026-10-28T10-00-00-\(uuid(3)).jsonl"
        var lines = [
            sessionMeta(accountID: nil),
            String(decoding: line(timestamp: "2026-10-28T06:00:00.000Z", primary: window(used: 30, minutes: 300, resetsAt: 1_793_188_826)), as: UTF8.self),
        ]
        try fixture.writeRollout(relativePath: path, lines: lines, modificationDate: Date(timeIntervalSince1970: 1_793_169_000))
        let reader = CodexQuotaReader()
        guard case .snapshot(let first) = try reader.read(codexRoot: fixture.root) else {
            Issue.record("Expected first snapshot")
            return
        }
        #expect(first.windows[.fiveHour]?.usedPercent == 30)
        #expect(first.accountID == nil)

        // 只有额度事件追加，没有 token 增量。
        lines.append(String(decoding: line(
            timestamp: "2026-10-28T06:30:00.000Z",
            info: "null",
            primary: window(used: 45, minutes: 300, resetsAt: 1_793_188_826)
        ), as: UTF8.self))
        try fixture.writeRollout(relativePath: path, lines: lines, modificationDate: Date(timeIntervalSince1970: 1_793_170_800))
        guard case .snapshot(let second) = try reader.read(codexRoot: fixture.root) else {
            Issue.record("Expected second snapshot")
            return
        }
        #expect(second.windows[.fiveHour]?.usedPercent == 45)
    }

    @Test("长于单次读取块的尾部内容仍能向前找到额度事件")
    func findsEventBeforeLargeTrailingLines() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let filler = #"{"timestamp":"2026-10-28T06:01:00.000Z","type":"response_item","payload":{"text":"\#(String(repeating: "x", count: 3_000))"}}"#
        try fixture.writeRollout(
            relativePath: "sessions/2026/10/28/rollout-2026-10-28T10-00-00-\(uuid(4)).jsonl",
            lines: [
                sessionMeta(accountID: "account-a"),
                String(decoding: line(timestamp: "2026-10-28T06:00:00.000Z", primary: window(used: 8, minutes: 300, resetsAt: 1_793_188_826)), as: UTF8.self),
                filler, filler, filler,
            ],
            modificationDate: Date(timeIntervalSince1970: 1_793_169_000)
        )
        var configuration = CodexQuotaReader.Configuration()
        configuration.tailChunkSize = 1_024

        guard case .snapshot(let snapshot) = try CodexQuotaReader(configuration: configuration)
            .read(codexRoot: fixture.root) else {
            Issue.record("Expected a snapshot")
            return
        }
        #expect(snapshot.windows[.fiveHour]?.usedPercent == 8)
        #expect(snapshot.accountID == "account-a")
    }

    @Test("没有任何额度事件时返回尚无记录")
    func noRateLimitEventsIsNoRecord() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        try fixture.writeRollout(
            relativePath: "archived_sessions/rollout-2026-10-28T10-00-00-\(uuid(5)).jsonl",
            lines: [sessionMeta(accountID: "account-a")],
            modificationDate: Date(timeIntervalSince1970: 1_793_169_000)
        )

        #expect(try CodexQuotaReader().read(codexRoot: fixture.root) == .noRecord)
    }

    // MARK: - Helpers

    private func line(
        timestamp: String = "2026-10-28T07:11:16.314Z",
        limitID: String? = "codex",
        info: String = #"{"last_token_usage":{"input_tokens":10,"output_tokens":2}}"#,
        primary: String,
        secondary: String = "null"
    ) -> Data {
        let limit = limitID.map { #""limit_id":"\#($0)","# } ?? ""
        return Data(#"{"timestamp":"\#(timestamp)","type":"event_msg","payload":{"type":"token_count","info":\#(info),"rate_limits":{\#(limit)"primary":\#(primary),"secondary":\#(secondary),"plan_type":"plus"}}}"#.utf8)
    }

    private func window(used: Double, minutes: Int, resetsAt: Int?) -> String {
        #"{"used_percent":\#(used),"window_minutes":\#(minutes),"resets_at":\#(resetsAt.map(String.init) ?? "null")}"#
    }

    private func sessionMeta(accountID: String?) -> String {
        let account = accountID.map { #","creator_account_id":"\#($0)""# } ?? ""
        return #"{"timestamp":"2026-10-28T05:00:00.000Z","type":"session_meta","payload":{"id":"session","cwd":"/tmp","base_instructions":{"text":"long"}\#(account)}}"#
    }

    private func uuid(_ index: Int) -> String {
        String(format: "00000000-0000-0000-0000-%012d", index)
    }

    private struct Fixture {
        let root: URL

        init() throws {
            root = FileManager.default.temporaryDirectory
                .appendingPathComponent("CodexQuotaReaderTests-\(UUID().uuidString)", isDirectory: true)
            try FileManager.default.createDirectory(
                at: root.appendingPathComponent("sessions", isDirectory: true),
                withIntermediateDirectories: true
            )
        }

        func writeRollout(
            relativePath: String,
            lines: [String],
            modificationDate: Date,
            endsWithNewline: Bool = true
        ) throws {
            let url = root.appendingPathComponent(relativePath)
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            let text = lines.joined(separator: "\n") + (endsWithNewline ? "\n" : "")
            try Data(text.utf8).write(to: url)
            try FileManager.default.setAttributes([.modificationDate: modificationDate], ofItemAtPath: url.path)
        }

        func remove() {
            try? FileManager.default.removeItem(at: root)
        }
    }
}
