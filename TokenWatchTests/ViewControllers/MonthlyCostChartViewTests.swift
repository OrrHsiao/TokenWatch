import AppKit
import Testing
@testable import TokenWatch

@Suite("MonthlyCostChartView")
struct MonthlyCostChartViewTests {

    @MainActor
    @Test("配置 snapshot 后渲染十二根费用柱")
    func configureRendersTwelveCostBars() {
        let view = MonthlyCostChartView()
        let snapshot = makeSnapshot(costs: [0, 0.25, 0.5, 0.75, 1, 1.25, 1.5, 1.75, 2, 2.25, 2.5, 5])

        view.configure(with: snapshot)

        #expect(view.debugBarCount == 12)
        #expect(view.debugMonthLabels == [
            "7月", "8月", "9月", "10月", "11月", "12月",
            "1月", "2月", "3月", "4月", "5月", "6月",
        ])
        #expect(view.debugNormalizedHeights.last == 1.0)
    }

    @MainActor
    @Test("全零费用保持稳定柱高状态")
    func zeroCostsKeepStableBarState() {
        let view = MonthlyCostChartView()
        let snapshot = makeSnapshot(costs: Array(repeating: 0, count: 12))

        view.configure(with: snapshot)

        #expect(view.debugBarCount == 12)
        #expect(view.debugNormalizedHeights.allSatisfy { $0 == 0 })
    }

    @MainActor
    @Test("重复配置会替换旧费用柱")
    func repeatedConfigureReplacesExistingCostBars() {
        let view = MonthlyCostChartView()

        view.configure(with: makeSnapshot(costs: Array(repeating: 1, count: 12)))
        view.configure(with: makeSnapshot(costs: [0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 20]))

        #expect(view.debugBarCount == 12)
        #expect(view.debugNormalizedHeights.first == 0)
        #expect(view.debugNormalizedHeights[10] == 0.5)
        #expect(view.debugNormalizedHeights.last == 1.0)
    }

    @MainActor
    @Test("debug 高度与渲染使用相同的稳定 clamp 值")
    func debugHeightsUseClampedFiniteValues() {
        let view = MonthlyCostChartView()
        let snapshot = makeSnapshot(normalizedCostHeights: [-0.2, 1.4, .nan, 0.25])

        view.configure(with: snapshot)

        #expect(view.debugNormalizedHeights[0] == 0)
        #expect(view.debugNormalizedHeights[1] == 1)
        #expect(view.debugNormalizedHeights[2] == 0)
        #expect(view.debugNormalizedHeights[3] == 0.25)
        #expect(view.debugNormalizedHeights.allSatisfy { $0.isFinite && (0...1).contains($0) })
    }

    @MainActor
    @Test("单根费用柱提供确定 intrinsic 尺寸")
    func barViewHasDeterministicIntrinsicSize() {
        let barView = MonthlyCostBarView()

        #expect(barView.intrinsicContentSize.width == 18)
        #expect(barView.intrinsicContentSize.height == 160)
    }

    private func makeSnapshot(costs: [Double]) -> MonthlyTokenChartSnapshot {
        let monthKeys = [
            "2025-07", "2025-08", "2025-09", "2025-10",
            "2025-11", "2025-12", "2026-01", "2026-02",
            "2026-03", "2026-04", "2026-05", "2026-06",
        ]
        let monthLabels = [
            "7月", "8月", "9月", "10月", "11月", "12月",
            "1月", "2月", "3月", "4月", "5月", "6月",
        ]
        let maxCost = costs.max() ?? 0
        let buckets = zip(monthKeys.indices, costs).map { index, totalCost in
            MonthlyTokenBucket(
                id: monthKeys[index],
                monthKey: monthKeys[index],
                monthLabel: monthLabels[index],
                totalTokens: 0,
                totalCost: totalCost,
                normalizedHeight: 0,
                normalizedCostHeight: maxCost > 0 ? totalCost / maxCost : 0,
                isCurrentMonth: index == monthKeys.indices.last
            )
        }

        return MonthlyTokenChartSnapshot(
            monthBuckets: buckets,
            totalTokens: 0,
            totalCost: costs.reduce(0, +),
            maxMonthlyTokens: 0,
            maxMonthlyCost: maxCost,
            toolShareSlices: [],
            modelShareSlices: [],
            loadedProviderCount: 1,
            loadingProviderCount: 0,
            unauthorizedProviderCount: 0,
            errorMessages: []
        )
    }

    private func makeSnapshot(normalizedCostHeights: [Double]) -> MonthlyTokenChartSnapshot {
        let buckets = normalizedCostHeights.indices.map { index in
            MonthlyTokenBucket(
                id: "manual-\(index)",
                monthKey: "manual-\(index)",
                monthLabel: "\(index + 1)月",
                totalTokens: 0,
                totalCost: Double(index),
                normalizedHeight: 0,
                normalizedCostHeight: normalizedCostHeights[index],
                isCurrentMonth: index == normalizedCostHeights.indices.last
            )
        }

        return MonthlyTokenChartSnapshot(
            monthBuckets: buckets,
            totalTokens: 0,
            totalCost: 0,
            maxMonthlyTokens: 0,
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
