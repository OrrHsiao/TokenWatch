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

    @Test("semantic comparison ignores generatedAt and nothing else")
    func semanticComparisonIgnoresGeneratedAtOnly() {
        let first = makeSnapshot(generatedAt: Date(timeIntervalSince1970: 100))
        let later = makeSnapshot(generatedAt: Date(timeIntervalSince1970: 200))
        let changed = makeSnapshot(
            generatedAt: Date(timeIntervalSince1970: 200),
            todayTotal: 43
        )

        #expect(first.hasSameContent(as: later))
        #expect(!first.hasSameContent(as: changed))
    }

    private func makeSnapshot(
        generatedAt: Date,
        todayTotal: Int = 42
    ) -> WidgetUsageSnapshot {
        WidgetUsageSnapshot(
            schemaVersion: WidgetSharedConfiguration.schemaVersion,
            generatedAt: generatedAt,
            localDayKey: "2026-07-15",
            localizedText: WidgetLocalizedText(
                heatmapTitle: "最近 22 周",
                todayUsageTitle: "今日用量",
                datedUsageTitle: "7/15 用量",
                updatedThroughTitle: "更新至 7/15",
                notReadyMessage: "打开 TokenWatch 刷新数据"
            ),
            heatmap: WidgetHeatmapSnapshot(
                totalTokens: 42,
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
                totalTokens: todayTotal,
                maxHourlyTokens: todayTotal,
                points: [
                    WidgetHourlyPoint(
                        hour: 0,
                        hourKey: "2026-07-15T00",
                        hourLabel: "0时",
                        totalTokens: todayTotal,
                        isCurrentHour: true
                    )
                ]
            )
        )
    }
}
