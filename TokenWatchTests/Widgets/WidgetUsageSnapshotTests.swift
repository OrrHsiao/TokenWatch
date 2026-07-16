import Foundation
import Testing
@testable import TokenWatch

@Suite("WidgetUsageSnapshot")
struct WidgetUsageSnapshotTests {
    @Test("schema 1 snapshot round-trips through JSON")
    func schemaOneRoundTrips() throws {
        let source = makeSnapshot(generatedAt: Date(timeIntervalSince1970: 100))
        let data = try JSONEncoder().encode(source)
        let decoded = try JSONDecoder().decode(WidgetUsageSnapshot.self, from: data)
        #expect(decoded == source)
        #expect(decoded.schemaVersion == WidgetSharedConfiguration.schemaVersion)
    }

    @Test("semantic comparison ignores generatedAt")
    func semanticComparisonIgnoresGeneratedAt() {
        let first = makeSnapshot(generatedAt: Date(timeIntervalSince1970: 100))
        let later = makeSnapshot(generatedAt: Date(timeIntervalSince1970: 200))

        #expect(
            first.hasSameContent(as: later),
            "hasSameContent(as:) must ignore generatedAt"
        )
    }

    @Test("semantic comparison includes schemaVersion")
    func semanticComparisonIncludesSchemaVersion() {
        let first = makeSnapshot()
        let changed = makeSnapshot(
            schemaVersion: WidgetSharedConfiguration.schemaVersion + 1
        )

        #expect(
            !first.hasSameContent(as: changed),
            "hasSameContent(as:) must compare schemaVersion"
        )
    }

    @Test("semantic comparison includes localDayKey")
    func semanticComparisonIncludesLocalDayKey() {
        let first = makeSnapshot()
        let changed = makeSnapshot(localDayKey: "2026-07-16")

        #expect(
            !first.hasSameContent(as: changed),
            "hasSameContent(as:) must compare localDayKey"
        )
    }

    @Test("semantic comparison includes localizedText")
    func semanticComparisonIncludesLocalizedText() {
        let first = makeSnapshot()
        let changed = makeSnapshot(notReadyMessage: "Open TokenWatch to refresh data")

        #expect(
            !first.hasSameContent(as: changed),
            "hasSameContent(as:) must compare localizedText"
        )
    }

    @Test("semantic comparison includes heatmap")
    func semanticComparisonIncludesHeatmap() {
        let first = makeSnapshot()
        let changed = makeSnapshot(heatmapTotalTokens: 43)

        #expect(
            !first.hasSameContent(as: changed),
            "hasSameContent(as:) must compare heatmap"
        )
    }

    @Test("semantic comparison includes hourlyLine")
    func semanticComparisonIncludesHourlyLine() {
        let first = makeSnapshot()
        let changed = makeSnapshot(hourlyTotalTokens: 43)

        #expect(
            !first.hasSameContent(as: changed),
            "hasSameContent(as:) must compare hourlyLine"
        )
    }

    private func makeSnapshot(
        generatedAt: Date = Date(timeIntervalSince1970: 100),
        schemaVersion: Int = WidgetSharedConfiguration.schemaVersion,
        localDayKey: String = "2026-07-15",
        notReadyMessage: String = "打开 TokenWatch 刷新数据",
        heatmapTotalTokens: Int = 42,
        hourlyTotalTokens: Int = 42
    ) -> WidgetUsageSnapshot {
        WidgetUsageSnapshot(
            schemaVersion: schemaVersion,
            generatedAt: generatedAt,
            localDayKey: localDayKey,
            localizedText: WidgetLocalizedText(
                heatmapTitle: "最近 22 周",
                todayUsageTitle: "今日用量",
                datedUsageTitle: "7/15 用量",
                updatedThroughTitle: "更新至 7/15",
                notReadyMessage: notReadyMessage
            ),
            heatmap: WidgetHeatmapSnapshot(
                totalTokens: heatmapTotalTokens,
                maxDailyTokens: 42,
                cells: [
                    WidgetHeatmapCell(
                        dateKey: "2026-07-15",
                        totalTokens: 42,
                        intensity: 4,
                        isPlaceholder: false
                    )
                ]
            ),
            hourlyLine: WidgetHourlyLineSnapshot(
                dayKey: "2026-07-15",
                totalTokens: hourlyTotalTokens,
                maxHourlyTokens: 42,
                points: [
                    WidgetHourlyPoint(
                        hour: 0,
                        hourKey: "2026-07-15T00",
                        hourLabel: "0时",
                        totalTokens: 42,
                        isCurrentHour: true
                    )
                ]
            )
        )
    }
}
