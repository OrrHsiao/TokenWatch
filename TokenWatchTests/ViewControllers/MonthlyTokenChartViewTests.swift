import AppKit
import Testing
@testable import TokenWatch

@Suite("MonthlyTokenChartView")
struct MonthlyTokenChartViewTests {

    @MainActor
    @Test("配置 snapshot 后渲染十二根柱")
    func configureRendersTwelveBars() {
        let view = MonthlyTokenChartView()
        let snapshot = makeSnapshot(tokens: [0, 10, 20, 30, 40, 50, 60, 70, 80, 90, 100, 110])

        view.configure(with: snapshot)

        #expect(view.debugBarCount == 12)
        #expect(view.debugMonthLabels == [
            "7月", "8月", "9月", "10月", "11月", "12月",
            "1月", "2月", "3月", "4月", "5月", "6月",
        ])
        #expect(view.debugNormalizedHeights.last == 1.0)
    }

    @MainActor
    @Test("全零数据保持稳定柱高状态")
    func zeroDataKeepsStableBarState() {
        let view = MonthlyTokenChartView()
        let snapshot = makeSnapshot(tokens: Array(repeating: 0, count: 12))

        view.configure(with: snapshot)

        #expect(view.debugBarCount == 12)
        #expect(view.debugNormalizedHeights.allSatisfy { $0 == 0 })
    }

    @MainActor
    @Test("重复配置会替换旧柱子")
    func repeatedConfigureReplacesExistingBars() {
        let view = MonthlyTokenChartView()

        view.configure(with: makeSnapshot(tokens: Array(repeating: 1, count: 12)))
        view.configure(with: makeSnapshot(tokens: Array(repeating: 2, count: 12)))

        #expect(view.debugBarCount == 12)
        #expect(view.debugNormalizedHeights.allSatisfy { $0 == 1.0 })
    }

    private func makeSnapshot(tokens: [Int]) -> MonthlyTokenChartSnapshot {
        let monthKeys = [
            "2025-07", "2025-08", "2025-09", "2025-10",
            "2025-11", "2025-12", "2026-01", "2026-02",
            "2026-03", "2026-04", "2026-05", "2026-06",
        ]
        let monthLabels = [
            "7月", "8月", "9月", "10月", "11月", "12月",
            "1月", "2月", "3月", "4月", "5月", "6月",
        ]
        let maxTokens = tokens.max() ?? 0
        let buckets = zip(monthKeys.indices, tokens).map { index, total in
            MonthlyTokenBucket(
                id: monthKeys[index],
                monthKey: monthKeys[index],
                monthLabel: monthLabels[index],
                totalTokens: total,
                normalizedHeight: maxTokens > 0 ? Double(total) / Double(maxTokens) : 0,
                isCurrentMonth: index == monthKeys.indices.last
            )
        }

        return MonthlyTokenChartSnapshot(
            monthBuckets: buckets,
            totalTokens: tokens.reduce(0, +),
            maxMonthlyTokens: maxTokens,
            loadedProviderCount: 1,
            loadingProviderCount: 0,
            unauthorizedProviderCount: 0,
            errorMessages: []
        )
    }
}
