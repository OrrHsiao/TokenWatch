import AppKit
import SwiftUI
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
            "1月", "2月", "3月", "4月", "5月", "6月",
            "7月", "8月", "9月", "10月", "11月", "12月",
        ])
        #expect(view.debugXAxisLabels == [
            "2026年\n1月", "2026年\n2月", "2026年\n3月", "2026年\n4月",
            "2026年\n5月", "2026年\n6月", "2026年\n7月", "2026年\n8月",
            "2026年\n9月", "2026年\n10月", "2026年\n11月", "2026年\n12月",
        ])
        #expect(view.debugNormalizedHeights.last == 1.0)
        #expect(view.allDescendants(ofType: NSHostingView<AnyView>.self).count == 1)
    }

    @MainActor
    @Test("英文下费用月份横轴使用英文缩写")
    func englishCostXAxisLabelsUseShortMonthNames() {
        let view = MonthlyCostChartView()
        let snapshot = makeSnapshot(monthKeys: ["2026-06"], monthLabels: ["Jun"], costs: [12.5])

        view.configure(with: snapshot, language: .en)

        #expect(view.debugXAxisLabels == ["2026\nJun"])
    }

    @MainActor
    @Test("费用纵轴标签不显示小数")
    func costYAxisLabelsUseWholeCurrencyValues() {
        let view = MonthlyCostChartView()

        #expect(view.debugYAxisLabel(for: 12.5) == "$13")
        #expect(view.debugYAxisLabel(for: 12.0) == "$12")
        #expect(!view.debugYAxisLabel(for: 12.5).contains("."))
    }

    @MainActor
    @Test("费用横轴标签使用小字号以容纳十二个月")
    func costXAxisLabelsUseCompactFontSize() {
        let view = MonthlyCostChartView()

        #expect(view.debugXAxisLabelFontSize <= 9)
    }

    @MainActor
    @Test("本日小时桶费用横轴只展示小时")
    func todayHourlyCostXAxisLabelsShowOnlyHour() {
        let view = MonthlyCostChartView()
        let snapshot = makeSnapshot(
            monthKeys: ["2026-06-20T00", "2026-06-20T14", "2026-06-20T23"],
            monthLabels: ["0", "14", "23"],
            costs: [0.5, 1.25, 2.0]
        )

        view.configure(with: snapshot)

        #expect(view.debugXAxisLabels == ["0", "14", "23"])
        #expect(view.debugXAxisLabels.allSatisfy { !$0.contains("2026") && !$0.contains("6/20") })
        #expect(view.debugXAxisLabels.allSatisfy { !$0.contains(":") })
        #expect(view.debugXAxisLabels.allSatisfy { !$0.contains("时") })
    }

    @MainActor
    @Test("费用图表内容保持完整宽度")
    func chartHostKeepsFullWidth() throws {
        let view = MonthlyCostChartView(frame: NSRect(x: 0, y: 0, width: 520, height: 246))
        view.configure(with: makeSnapshot(costs: [0, 0.25, 0.5, 0.75, 1, 1.25, 1.5, 1.75, 2, 2.25, 2.5, 5]))

        view.layoutSubtreeIfNeeded()

        let chartHost = try #require(view.allDescendants(ofType: NSHostingView<AnyView>.self).first)
        let hostFrame = chartHost.convert(chartHost.bounds, to: view)
        #expect(hostFrame.width > 500)
    }

    @MainActor
    @Test("费用图表宿主直接填满外层视图")
    func chartHostIsDirectSubview() throws {
        let view = MonthlyCostChartView()

        let chartHost = try #require(view.allDescendants(ofType: NSHostingView<AnyView>.self).first)
        #expect(chartHost.superview === view)
    }

    @MainActor
    @Test("费用图例与 Token 图一样右对齐")
    func costLegendAlignsTrailing() {
        let view = MonthlyCostChartView()

        #expect(view.debugLegendAlignment == .trailing)
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
    @Test("鼠标划过月份柱时回传该月费用")
    func hoveringMonthBarEmitsCostText() {
        let view = MonthlyCostChartView()
        let snapshot = makeSnapshot(costs: [0, 0.25, 0.5, 0.75, 1, 12.5, 1.5, 1.75, 2, 2.25, 2.5, 5])
        var hoverTexts: [String?] = []
        view.onHoverTextChange = { text in
            hoverTexts.append(text)
        }

        view.configure(with: snapshot)
        view.debugSimulateHover(monthKey: "2026-06")
        view.debugSimulateHover(monthKey: nil)

        #expect(hoverTexts.count == 2)
        #expect(hoverTexts[0] == "6月 · $12.50")
        #expect(hoverTexts[1] == nil)
    }

    @MainActor
    @Test("英文配置下费用悬停文案不使用旧 snapshot 月份标签")
    func englishCostHoverTextDerivesPeriodFromCurrentLanguage() {
        let view = MonthlyCostChartView()
        let snapshot = makeSnapshot(monthKeys: ["2026-06"], monthLabels: ["6月"], costs: [12.5])
        var hoverTexts: [String?] = []
        view.onHoverTextChange = { text in
            hoverTexts.append(text)
        }

        view.configure(with: snapshot, language: .en)
        view.debugSimulateHover(monthKey: "2026-06")

        #expect(hoverTexts == ["2026 Jun · $12.50"])
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
    @Test("配置 snapshot 后保留每月模型费用段供堆叠柱渲染")
    func configureKeepsMonthlyModelCostSegmentsForStackedBars() {
        let view = MonthlyCostChartView()
        let snapshot = makeSnapshot(
            costs: [0, 0.25, 0.5, 0.75, 1, 12.5, 1.5, 1.75, 2, 2.25, 2.5, 5],
            modelBreakdowns: [
                5: [
                    ("claude-sonnet", 8.25),
                    ("gpt-5", 4.25),
                ],
            ]
        )

        view.configure(with: snapshot)

        #expect(view.debugModelSegmentLabelsByMonth["2026-06"] == ["claude-sonnet", "gpt-5"])
        #expect(view.debugModelSegmentCostsByMonth["2026-06"] == [8.25, 4.25])
    }

    @MainActor
    @Test("Token 图和费用图对同一模型使用同一图例颜色")
    func tokenAndCostChartsShareModelLegendColors() {
        let tokenView = MonthlyTokenChartView()
        let costView = MonthlyCostChartView()
        let tokenSnapshot = makeTokenSnapshot(
            modelBreakdowns: [
                0: [
                    ("claude-sonnet", 800_000),
                    ("gpt-5", 400_000),
                ],
            ]
        )
        let costSnapshot = makeSnapshot(
            costs: [12.5],
            modelBreakdowns: [
                0: [
                    ("gpt-5", 4.25),
                    ("claude-sonnet", 8.25),
                ],
            ]
        )

        tokenView.configure(with: tokenSnapshot)
        costView.configure(with: costSnapshot)

        #expect(
            tokenView.debugModelSegmentColorsByMonth["2026-06"]?["claude-sonnet"]
                == costView.debugModelSegmentColorsByMonth["2026-01"]?["claude-sonnet"]
        )
        #expect(
            tokenView.debugModelSegmentColorsByMonth["2026-06"]?["gpt-5"]
                == costView.debugModelSegmentColorsByMonth["2026-01"]?["gpt-5"]
        )
    }

    @MainActor
    @Test("鼠标划过分段费用月份时回传该月模型费用明细")
    func hoveringStackedCostMonthBarEmitsModelBreakdownText() {
        let view = MonthlyCostChartView()
        let snapshot = makeSnapshot(
            costs: [0, 0.25, 0.5, 0.75, 1, 12.5, 1.5, 1.75, 2, 2.25, 2.5, 5],
            modelBreakdowns: [
                5: [
                    ("claude-sonnet", 8.25),
                    ("gpt-5", 4.25),
                ],
            ]
        )
        var hoverTexts: [String?] = []
        view.onHoverTextChange = { text in
            hoverTexts.append(text)
        }

        view.configure(with: snapshot)
        view.debugSimulateHover(monthKey: "2026-06")

        #expect(hoverTexts == ["6月 · $12.50 · claude-sonnet $8.25, gpt-5 $4.25"])
    }

    private func makeSnapshot(costs: [Double]) -> MonthlyTokenChartSnapshot {
        makeSnapshot(costs: costs, modelBreakdowns: [:])
    }

    private func makeSnapshot(
        costs: [Double],
        modelBreakdowns: [Int: [(String, Double)]]
    ) -> MonthlyTokenChartSnapshot {
        let monthKeys = [
            "2026-01", "2026-02", "2026-03", "2026-04",
            "2026-05", "2026-06", "2026-07", "2026-08",
            "2026-09", "2026-10", "2026-11", "2026-12",
        ]
        let monthLabels = [
            "1月", "2月", "3月", "4月", "5月", "6月",
            "7月", "8月", "9月", "10月", "11月", "12月",
        ]
        let maxCost = costs.max() ?? 0
        let buckets = zip(monthKeys.indices, costs).map { index, totalCost in
            let modelSegments = (modelBreakdowns[index] ?? []).map { modelName, modelCost in
                MonthlyTokenModelSegment(
                    modelName: modelName,
                    totalTokens: 0,
                    totalCost: modelCost,
                    percentage: totalCost > 0 ? modelCost / totalCost : 0
                )
            }
            return MonthlyTokenBucket(
                id: monthKeys[index],
                monthKey: monthKeys[index],
                monthLabel: monthLabels[index],
                totalTokens: 0,
                totalCost: totalCost,
                normalizedHeight: 0,
                normalizedCostHeight: maxCost > 0 ? totalCost / maxCost : 0,
                isCurrentMonth: index == monthKeys.indices.last,
                modelSegments: modelSegments
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

    private func makeTokenSnapshot(
        modelBreakdowns: [Int: [(String, Int)]]
    ) -> MonthlyTokenChartSnapshot {
        let tokens = [1_200_000]
        let modelSegments = (modelBreakdowns[0] ?? []).map { modelName, modelTotal in
            MonthlyTokenModelSegment(
                modelName: modelName,
                totalTokens: modelTotal,
                percentage: Double(modelTotal) / Double(tokens[0])
            )
        }
        return MonthlyTokenChartSnapshot(
            monthBuckets: [
                MonthlyTokenBucket(
                    id: "2026-06",
                    monthKey: "2026-06",
                    monthLabel: "6月",
                    totalTokens: tokens[0],
                    totalCost: 0,
                    normalizedHeight: 1,
                    normalizedCostHeight: 0,
                    isCurrentMonth: true,
                    modelSegments: modelSegments
                ),
            ],
            totalTokens: tokens[0],
            totalCost: 0,
            maxMonthlyTokens: tokens[0],
            maxMonthlyCost: 0,
            toolShareSlices: [],
            modelShareSlices: [],
            loadedProviderCount: 1,
            loadingProviderCount: 0,
            unauthorizedProviderCount: 0,
            errorMessages: []
        )
    }

    private func makeSnapshot(
        monthKeys: [String],
        monthLabels: [String],
        costs: [Double]
    ) -> MonthlyTokenChartSnapshot {
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

private extension NSView {
    func allDescendants<T: NSView>(ofType type: T.Type) -> [T] {
        let current = (self as? T).map { [$0] } ?? []
        return current + subviews.flatMap { $0.allDescendants(ofType: type) }
    }
}
