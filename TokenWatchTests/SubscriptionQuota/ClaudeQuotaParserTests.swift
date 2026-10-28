import Foundation
import Testing
@testable import TokenWatch

@Suite("ClaudeQuotaParser")
struct ClaudeQuotaParserTests {

    @Test("两层 utilization 换算为窗口，毫秒来源时间与 ISO 8601 重置时间保持原值")
    func parsesNestedUtilizationWithSourceTimestamps() throws {
        let result = try ClaudeQuotaParser.parse(config(cache: """
        {
          "fetchedAtMs": 1793170561369,
          "accountUuid": "account-a",
          "utilization": {
            "five_hour": { "utilization": 32, "resets_at": "2026-10-28T12:50:00.206689+00:00" },
            "seven_day": { "utilization": 14.5, "resets_at": "2026-11-01T00:00:00+00:00" }
          }
        }
        """, accountID: "account-a"))

        let snapshot = try #require(snapshot(from: result))
        #expect(snapshot.provider == .claude)
        #expect(snapshot.accountID == "account-a")
        #expect(snapshot.recordedAt == Date(timeIntervalSince1970: 1_793_170_561.369))
        #expect(snapshot.windows[.fiveHour]?.usedPercent == 32)
        #expect(snapshot.windows[.fiveHour]?.remainingPercent == 68)
        #expect(snapshot.windows[.sevenDay]?.usedPercent == 14.5)
        let fiveHourReset = try #require(snapshot.windows[.fiveHour]?.resetsAt)
        #expect(abs(fiveHourReset.timeIntervalSince1970 - 1_793_191_800.2067) < 0.001)
        #expect(snapshot.windows[.sevenDay]?.resetsAt == ISO8601DateFormatterHelper.parse("2026-11-01T00:00:00Z"))
    }

    @Test("重置时间为 null 时保留窗口，只把重置时间视为未知")
    func nullResetKeepsWindowWithUnknownReset() throws {
        let result = try ClaudeQuotaParser.parse(config(cache: """
        {
          "fetchedAtMs": 1793170561369,
          "utilization": { "five_hour": { "utilization": 0, "resets_at": null } }
        }
        """))

        let snapshot = try #require(snapshot(from: result))
        #expect(snapshot.windows[.fiveHour]?.usedPercent == 0)
        #expect(snapshot.windows[.fiveHour]?.resetsAt == nil)
        #expect(snapshot.windows[.sevenDay] == nil)
    }

    @Test("使用率缺失或非数值的窗口独立缺失，不被写成 0% 或 100%")
    func invalidUtilizationDropsOnlyThatWindow() throws {
        let result = try ClaudeQuotaParser.parse(config(cache: """
        {
          "fetchedAtMs": 1793170561369,
          "utilization": {
            "five_hour": { "utilization": "abc", "resets_at": "2026-10-28T12:50:00Z" },
            "seven_day": { "utilization": "14", "resets_at": "2026-11-01T00:00:00Z" }
          }
        }
        """))

        let snapshot = try #require(snapshot(from: result))
        #expect(snapshot.windows[.fiveHour] == nil)
        #expect(snapshot.windows[.sevenDay]?.usedPercent == 14)
    }

    @Test("超出范围的使用率夹到 0...100")
    func clampsOutOfRangeUtilization() throws {
        let result = try ClaudeQuotaParser.parse(config(cache: """
        {
          "fetchedAtMs": 1793170561369,
          "utilization": {
            "five_hour": { "utilization": 130 },
            "seven_day": { "utilization": -5 }
          }
        }
        """))

        let snapshot = try #require(snapshot(from: result))
        #expect(snapshot.windows[.fiveHour]?.remainingPercent == 0)
        #expect(snapshot.windows[.sevenDay]?.remainingPercent == 100)
    }

    @Test("缺少额度缓存、来源时间或全部窗口时视为尚无记录")
    func missingCachePartsAreNoRecord() throws {
        #expect(try ClaudeQuotaParser.parse(Data(#"{"numStartups": 3}"#.utf8)) == .noRecord)
        #expect(try ClaudeQuotaParser.parse(config(cache: """
        { "utilization": { "five_hour": { "utilization": 10 } } }
        """)) == .noRecord)
        #expect(try ClaudeQuotaParser.parse(config(cache: """
        { "fetchedAtMs": 1793170561369, "utilization": { "five_hour": null, "seven_day": null } }
        """)) == .noRecord)
    }

    @Test("额度缓存属于其他账号时不展示，不与当前账号合并")
    func cacheFromAnotherAccountIsIgnored() throws {
        let result = try ClaudeQuotaParser.parse(config(cache: """
        {
          "fetchedAtMs": 1793170561369,
          "accountUuid": "account-old",
          "utilization": { "five_hour": { "utilization": 10 } }
        }
        """, accountID: "account-new"))

        #expect(result == .noRecord)
    }

    @Test("半截写入的配置文件抛错，由 store 保留最后有效值")
    func truncatedConfigThrows() {
        #expect(throws: (any Error).self) {
            try ClaudeQuotaParser.parse(Data(#"{"cachedUsageUtilization": {"fetchedAtMs": 17931"#.utf8))
        }
    }

    @Test("文件读取器在内容变化后重新解析")
    func fileReaderReparsesChangedFile() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("ClaudeQuotaParserTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let fileURL = directory.appendingPathComponent(".claude.json")
        let reader = ClaudeQuotaFileReader()

        try config(cache: #"{"fetchedAtMs": 1000, "utilization": {"five_hour": {"utilization": 10}}}"#)
            .write(to: fileURL)
        try FileManager.default.setAttributes(
            [.modificationDate: Date(timeIntervalSince1970: 1_000)],
            ofItemAtPath: fileURL.path
        )
        #expect(snapshot(from: try reader.read(fileURL: fileURL))?.windows[.fiveHour]?.usedPercent == 10)

        try config(cache: #"{"fetchedAtMs": 2000, "utilization": {"five_hour": {"utilization": 25}}}"#)
            .write(to: fileURL)
        try FileManager.default.setAttributes(
            [.modificationDate: Date(timeIntervalSince1970: 2_000)],
            ofItemAtPath: fileURL.path
        )
        let updated = try #require(snapshot(from: try reader.read(fileURL: fileURL)))
        #expect(updated.windows[.fiveHour]?.usedPercent == 25)
        #expect(updated.recordedAt == Date(timeIntervalSince1970: 2))
    }

    private func config(cache: String, accountID: String? = nil) -> Data {
        let account = accountID.map { #", "oauthAccount": {"accountUuid": "\#($0)", "emailAddress": "x"}"# } ?? ""
        return Data(#"{"numStartups": 3, "cachedUsageUtilization": \#(cache)\#(account)}"#.utf8)
    }

    private func snapshot(from result: SubscriptionQuotaReadResult) -> SubscriptionQuotaSnapshot? {
        guard case .snapshot(let snapshot) = result else { return nil }
        return snapshot
    }
}
