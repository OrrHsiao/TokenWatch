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
        #expect(view.debugLineInterpolationMethodName == "catmullRom")
        #expect(view.debugAreaGradientScaleModeName == "dailyMaximum")
        #expect(view.debugAreaGradientPeakOpacity == 0.8)
        #expect(view.debugAreaGradientBaselineOpacity == 0.05)
        #expect(view.debugAreaGradientLightRGBAComponents == [0.129, 0.431, 0.224, 1.0])
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

    @Test("鼠标划过小时点时更新折线图自己的 hover 文案")
    func hoveringHourUpdatesOwnHoverText() {
        let view = TodayHourlyTokenLineChartView()
        let snapshot = makeSnapshot(tokens: Array(repeating: 0, count: 24), override: [9: 1_234_567])

        view.configure(with: snapshot)
        view.debugSimulateHover(monthKey: "2026-06-20T09")

        #expect(view.debugHoverText == "9时 · 1.2M")

        view.debugSimulateHover(monthKey: nil)
        #expect(view.debugHoverText == "")
    }

    @Test("英文 hover 小时标签不带中文时")
    func englishHoverTextUsesHourNumberOnly() {
        let view = TodayHourlyTokenLineChartView()
        let snapshot = makeSnapshot(tokens: Array(repeating: 0, count: 24), override: [14: 250_000])

        view.configure(with: snapshot, language: .en)
        view.debugSimulateHover(monthKey: "2026-06-20T14")

        #expect(view.debugHoverText == "14 · 0.2M")
    }

    @Test("不足 0.1M 的小时 hover 使用 k 单位")
    func hoverTextBelowOneTenthMillionUsesThousands() {
        let view = TodayHourlyTokenLineChartView()
        let snapshot = makeSnapshot(tokens: Array(repeating: 0, count: 24), override: [8: 99_999])

        view.configure(with: snapshot)
        view.debugSimulateHover(monthKey: "2026-06-20T08")

        #expect(view.debugHoverText == "8时 · 99.9k")
    }

    @Test("0 token 的小时 hover 仍使用 M 单位")
    func zeroHoverTextUsesMillions() {
        let view = TodayHourlyTokenLineChartView()
        let snapshot = makeSnapshot(tokens: Array(repeating: 0, count: 24))

        view.configure(with: snapshot)
        view.debugSimulateHover(monthKey: "2026-06-20T08")

        #expect(view.debugHoverText == "8时 · 0.0M")
    }

    @Test("小时 hover 在 0.1M 边界切换到 M 单位")
    func hoverTextAtOneTenthMillionUsesMillions() {
        let view = TodayHourlyTokenLineChartView()
        let snapshot = makeSnapshot(tokens: Array(repeating: 0, count: 24), override: [8: 100_000])

        view.configure(with: snapshot)
        view.debugSimulateHover(monthKey: "2026-06-20T08")

        #expect(view.debugHoverText == "8时 · 0.1M")
    }

    @Test("hover label 对齐到折线图右上角")
    func hoverLabelAlignsWithLineChartTopTrailingCorner() {
        let view = TodayHourlyTokenLineChartView()
        let snapshot = makeSnapshot(tokens: Array(repeating: 0, count: 24))

        view.configure(with: snapshot)

        #expect(view.debugHoverLabelTopAlignsWithChartView)
        #expect(view.debugHoverLabelTrailingAlignsWithChartView)
    }

    @Test("hover label 不覆盖 Charts 宿主绘制区域")
    func hoverLabelDoesNotOverlapChartHostDrawingArea() throws {
        let view = TodayHourlyTokenLineChartView(frame: NSRect(x: 0, y: 0, width: 327, height: 111))
        let snapshot = makeSnapshot(tokens: Array(repeating: 0, count: 24), override: [23: 1_234_567])

        view.configure(with: snapshot)
        view.debugSimulateHover(monthKey: "2026-06-20T23")
        view.layoutSubtreeIfNeeded()

        let chartHost = try #require(view.allDescendants(ofType: NSHostingView<AnyView>.self).first)
        let hoverLabel = try #require(view.allDescendants(ofType: NSTextField.self).first)
        #expect(chartHost.frame.maxY <= hoverLabel.frame.minY)
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
