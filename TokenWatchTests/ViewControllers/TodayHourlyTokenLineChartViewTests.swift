import AppKit
import SwiftUI
import Testing
@testable import TokenWatch

@MainActor
@Suite("TodayHourlyTokenLineChartView")
struct TodayHourlyTokenLineChartViewTests {

    @Test("配置 snapshot 后保留二十四个小时点并使用 Charts 宿主")
    func configureRendersTwentyFourHourlyPoints() throws {
        let view = TodayHourlyTokenLineChartView()
        let snapshot = makeSnapshot(tokens: Array(0..<24).map { $0 * 10 })

        view.configure(with: snapshot)

        #expect(view.debugPointCount == 24)
        #expect(view.debugXAxisLabels == ["0", "6", "12", "18", "23"])
        #expect(view.debugNormalizedHeights.first == 0)
        #expect(view.debugNormalizedHeights.last == 1.0)
        #expect(view.allDescendants(ofType: NSHostingView<AnyView>.self).count == 1)
    }

    @Test("全零数据保持稳定高度")
    func zeroDataKeepsStableLineState() {
        let view = TodayHourlyTokenLineChartView()
        let snapshot = makeSnapshot(tokens: Array(repeating: 0, count: 24))

        view.configure(with: snapshot)

        #expect(view.debugPointCount == 24)
        #expect(view.debugNormalizedHeights.allSatisfy { $0 == 0 })
    }

    @Test("鼠标划过小时点时回传该小时 token 文案")
    func hoveringHourEmitsTokenUsageText() {
        let view = TodayHourlyTokenLineChartView()
        let snapshot = makeSnapshot(tokens: Array(repeating: 0, count: 24), override: [9: 1_234_567])
        var hoverTexts: [String?] = []
        view.onHoverTextChange = { hoverTexts.append($0) }

        view.configure(with: snapshot)
        view.debugSimulateHover(monthKey: "2026-06-20T09")
        view.debugSimulateHover(monthKey: nil)

        #expect(hoverTexts == ["9时 · 1.2M", nil])
    }

    @Test("英文 hover 小时标签不带中文时")
    func englishHoverTextUsesHourNumberOnly() {
        let view = TodayHourlyTokenLineChartView()
        let snapshot = makeSnapshot(tokens: Array(repeating: 0, count: 24), override: [14: 250_000])
        var hoverTexts: [String?] = []
        view.onHoverTextChange = { hoverTexts.append($0) }

        view.configure(with: snapshot, language: .en)
        view.debugSimulateHover(monthKey: "2026-06-20T14")

        #expect(hoverTexts == ["14 · 0.2M"])
    }

    private func makeSnapshot(tokens: [Int], override: [Int: Int] = [:]) -> MonthlyTokenChartSnapshot {
        let resolvedTokens = tokens.enumerated().map { index, total in
            override[index] ?? total
        }
        let maxTokens = resolvedTokens.max() ?? 0
        let buckets = resolvedTokens.indices.map { index in
            let total = resolvedTokens[index]
            let key = String(format: "2026-06-20T%02d", index)
            return MonthlyTokenBucket(
                id: key,
                monthKey: key,
                monthLabel: "\(index)时",
                totalTokens: total,
                totalCost: 0,
                normalizedHeight: maxTokens > 0 ? Double(total) / Double(maxTokens) : 0,
                normalizedCostHeight: 0,
                isCurrentMonth: index == 14,
                modelSegments: []
            )
        }

        return MonthlyTokenChartSnapshot(
            monthBuckets: buckets,
            totalTokens: resolvedTokens.reduce(0, +),
            totalCost: 0,
            maxMonthlyTokens: maxTokens,
            maxMonthlyCost: 0,
            toolShareSlices: [],
            modelShareSlices: [],
            loadedProviderCount: 1,
            loadingProviderCount: 0,
            unauthorizedProviderCount: 0,
            errorMessages: []
        )
    }
}

private extension NSView {
    func allDescendants<T: NSView>(ofType type: T.Type) -> [T] {
        let current = (self as? T).map { [$0] } ?? []
        return current + subviews.flatMap { $0.allDescendants(ofType: type) }
    }
}
