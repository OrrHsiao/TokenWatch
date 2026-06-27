import Foundation
import Testing
@testable import TokenWatch

@Suite("TokenWatchWidgetSnapshot")
struct TokenWatchWidgetSnapshotTests {

    @Test("示例快照包含固定热力图单元和二十四个小时桶")
    func sampleSnapshotHasStableShape() {
        let snapshot = TokenWatchWidgetSnapshot.sample(
            generatedAt: Date(timeIntervalSince1970: 1_779_811_200),
            languageIdentifier: "zh-Hans"
        )

        #expect(snapshot.status == .ready)
        #expect(snapshot.languageIdentifier == "zh-Hans")
        #expect(snapshot.heatmap.cells.count == 154)
        #expect(snapshot.todayLine.buckets.count == 24)
        #expect(snapshot.todayLine.currentHourKey == "2026-06-27T14")
    }

    @Test("空快照可以表达未授权状态")
    func emptySnapshotCanRepresentNeedsAuthorization() {
        let snapshot = TokenWatchWidgetSnapshot.empty(
            generatedAt: Date(timeIntervalSince1970: 1_779_811_200),
            languageIdentifier: "en",
            status: .needsAuthorization
        )

        #expect(snapshot.status == .needsAuthorization)
        #expect(snapshot.heatmap.cells.count == 154)
        #expect(snapshot.heatmap.summary.todayTokens == 0)
        #expect(snapshot.todayLine.totalTokens == 0)
        #expect(snapshot.todayLine.buckets.allSatisfy { $0.totalTokens == 0 })
    }

    @Test("空快照可以表达等待刷新状态")
    func emptySnapshotCanRepresentWaitingForRefresh() {
        let snapshot = TokenWatchWidgetSnapshot.empty(
            generatedAt: Date(timeIntervalSince1970: 1_779_811_200),
            languageIdentifier: "en",
            status: .waitingForRefresh
        )

        #expect(snapshot.status == .waitingForRefresh)
        #expect(TokenWatchWidgetCopy.text(.waitingForRefresh, languageIdentifier: snapshot.languageIdentifier) == "Waiting for TokenWatch to refresh")
        #expect(snapshot.heatmap.cells.count == 154)
        #expect(snapshot.todayLine.buckets.count == 24)
    }

    @Test("快照支持 Codable 往返")
    func snapshotSupportsCodableRoundTrip() throws {
        let snapshot = TokenWatchWidgetSnapshot.sample(
            generatedAt: Date(timeIntervalSince1970: 1_779_811_200),
            languageIdentifier: "zh-Hans"
        )

        let data = try JSONEncoder().encode(snapshot)
        let decoded = try JSONDecoder().decode(TokenWatchWidgetSnapshot.self, from: data)

        #expect(decoded == snapshot)
    }

    @Test("紧凑数字格式与状态栏格式一致")
    func compactFormatterMatchesStatusBarRules() {
        #expect(TokenWatchWidgetCompactNumberFormatter.format(0) == "0")
        #expect(TokenWatchWidgetCompactNumberFormatter.format(999) == "999")
        #expect(TokenWatchWidgetCompactNumberFormatter.format(12_345) == "12.3k")
        #expect(TokenWatchWidgetCompactNumberFormatter.format(1_234_567) == "1.2M")
        #expect(TokenWatchWidgetCompactNumberFormatter.formatHoverTokens(99_999) == "99.9k")
        #expect(TokenWatchWidgetCompactNumberFormatter.formatHoverTokens(100_000) == "0.1M")
    }

    @Test("Widget 文案按快照语言回退")
    func widgetCopyUsesSnapshotLanguage() {
        #expect(TokenWatchWidgetCopy.text(.openAppToAuthorize, languageIdentifier: "zh-Hans") == "打开 TokenWatch 完成授权")
        #expect(TokenWatchWidgetCopy.text(.openAppToAuthorize, languageIdentifier: "zh-Hant") == "開啟 TokenWatch 完成授權")
        #expect(TokenWatchWidgetCopy.text(.openAppToAuthorize, languageIdentifier: "zh_Hant") == "開啟 TokenWatch 完成授權")
        #expect(TokenWatchWidgetCopy.text(.openAppToAuthorize, languageIdentifier: "zh-TW") == "開啟 TokenWatch 完成授權")
        #expect(TokenWatchWidgetCopy.text(.openAppToAuthorize, languageIdentifier: "zh-HK") == "開啟 TokenWatch 完成授權")
        #expect(TokenWatchWidgetCopy.text(.openAppToAuthorize, languageIdentifier: "zh-MO") == "開啟 TokenWatch 完成授權")
        #expect(TokenWatchWidgetCopy.text(.openAppToAuthorize, languageIdentifier: "fr") == "Open TokenWatch to authorize")
        #expect(TokenWatchWidgetCopy.text(.today, languageIdentifier: "zh-Hans") == "今日")
        #expect(TokenWatchWidgetCopy.text(.today, languageIdentifier: "en") == "Today")
    }

    @Test("Widget gallery 文案语言使用系统首选语言")
    func widgetGalleryCopyUsesPreferredLanguage() {
        #expect(TokenWatchWidgetCopy.preferredLanguageIdentifier(from: ["en-US", "zh-Hans"]) == "en-US")
        #expect(TokenWatchWidgetCopy.preferredLanguageIdentifier(from: ["zh-Hant-TW"]) == "zh-Hant-TW")
        #expect(TokenWatchWidgetCopy.preferredLanguageIdentifier(from: []) == "en")
        #expect(TokenWatchWidgetCopy.text(.tokenHeatmapDisplayName, languageIdentifier: "en-US") == "Token Heatmap")
    }

    @Test("Widget 尺寸映射到稳定布局")
    func widgetFamilyLayoutMappingIsStable() {
        #expect(TokenWatchHeatmapWidgetLayout.layout(for: .small) == .compact)
        #expect(TokenWatchHeatmapWidgetLayout.layout(for: .medium) == .summary)
        #expect(TokenWatchHeatmapWidgetLayout.layout(for: .large) == .expanded)
        #expect(TokenWatchTodayLineWidgetLayout.layout(for: .small) == .compact)
        #expect(TokenWatchTodayLineWidgetLayout.layout(for: .medium) == .chart)
        #expect(TokenWatchTodayLineWidgetLayout.layout(for: .large) == .expanded)
    }
}
