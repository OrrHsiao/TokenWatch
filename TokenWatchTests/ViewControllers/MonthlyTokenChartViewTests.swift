import AppKit
import SwiftUI
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
    @Test("英文下月份横轴使用英文缩写")
    func englishXAxisLabelsUseShortMonthNames() {
        let view = MonthlyTokenChartView()
        let snapshot = makeSnapshot(monthKeys: ["2026-06"], monthLabels: ["Jun"], tokens: [100])

        view.configure(with: snapshot, language: .en)

        #expect(view.debugXAxisLabels == ["2026\nJun"])
    }

    @MainActor
    @Test("Token 纵轴标签不显示小数")
    func tokenYAxisLabelsUseWholeCompactNumbers() {
        let view = MonthlyTokenChartView()

        #expect(view.debugYAxisLabel(for: 950_000) == "950k")
        #expect(view.debugYAxisLabel(for: 1_234_567) == "1M")
        #expect(!view.debugYAxisLabel(for: 1_234_567).contains("."))
    }

    @MainActor
    @Test("横轴标签使用小字号以容纳十二个月")
    func xAxisLabelsUseCompactFontSize() {
        let view = MonthlyTokenChartView()

        #expect(view.debugXAxisLabelFontSize <= 9)
    }

    @MainActor
    @Test("本日小时桶横轴只展示小时")
    func todayHourlyXAxisLabelsShowOnlyHour() {
        let view = MonthlyTokenChartView()
        let snapshot = makeSnapshot(
            monthKeys: ["2026-06-20T00", "2026-06-20T14", "2026-06-20T23"],
            monthLabels: ["0", "14", "23"],
            tokens: [10, 20, 30]
        )

        view.configure(with: snapshot)

        #expect(view.debugXAxisLabels == ["0", "14", "23"])
        #expect(view.debugXAxisLabels.allSatisfy { !$0.contains("2026") && !$0.contains("6/20") })
        #expect(view.debugXAxisLabels.allSatisfy { !$0.contains(":") })
        #expect(view.debugXAxisLabels.allSatisfy { !$0.contains("时") })
    }

    @MainActor
    @Test("图表内容保持完整宽度")
    func chartHostKeepsFullWidth() throws {
        let view = MonthlyTokenChartView(frame: NSRect(x: 0, y: 0, width: 520, height: 246))
        view.configure(with: makeSnapshot(tokens: [0, 10, 20, 30, 40, 50, 60, 70, 80, 90, 100, 110]))

        view.layoutSubtreeIfNeeded()

        let chartHost = try #require(view.allDescendants(ofType: NSHostingView<AnyView>.self).first)
        let hostFrame = chartHost.convert(chartHost.bounds, to: view)
        #expect(hostFrame.width > 500)
    }

    @MainActor
    @Test("图表宿主直接填满外层视图")
    func chartHostIsDirectSubview() throws {
        let view = MonthlyTokenChartView()

        let chartHost = try #require(view.allDescendants(ofType: NSHostingView<AnyView>.self).first)
        #expect(chartHost.superview === view)
    }

    @MainActor
    @Test("Token 图例右对齐")
    func tokenLegendAlignsTrailing() {
        let view = MonthlyTokenChartView()

        #expect(view.debugLegendAlignment == .trailing)
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
        view.configure(with: makeSnapshot(tokens: [0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 20]))

        #expect(view.debugBarCount == 12)
        #expect(view.debugNormalizedHeights.first == 0)
        #expect(view.debugNormalizedHeights[10] == 0.5)
        #expect(view.debugNormalizedHeights.last == 1.0)
    }

    @MainActor
    @Test("鼠标划过月份柱时用 M 单位回传该月 token 用量")
    func hoveringMonthBarEmitsMillionTokenUsageText() {
        let view = MonthlyTokenChartView()
        let snapshot = makeSnapshot(tokens: [0, 10, 20, 30, 40, 1_234_567, 60, 70, 80, 90, 100, 110])
        var hoverTexts: [String?] = []
        view.onHoverTextChange = { text in
            hoverTexts.append(text)
        }

        view.configure(with: snapshot)
        view.debugSimulateHover(monthKey: "2026-06")
        view.debugSimulateHover(monthKey: nil)

        #expect(hoverTexts.count == 2)
        #expect(hoverTexts[0] == "6月 · 1.2M")
        #expect(hoverTexts[1] == nil)
    }

    @MainActor
    @Test("配置 snapshot 后保留每月模型段供堆叠柱渲染")
    func configureKeepsMonthlyModelSegmentsForStackedBars() {
        let view = MonthlyTokenChartView()
        let snapshot = makeSnapshot(
            tokens: [0, 10, 20, 30, 40, 1_200_000, 60, 70, 80, 90, 100, 110],
            modelBreakdowns: [
                5: [
                    ("claude-sonnet", 800_000),
                    ("gpt-5", 400_000),
                ],
            ]
        )

        view.configure(with: snapshot)

        #expect(view.debugModelSegmentLabelsByMonth["2026-06"] == ["claude-sonnet", "gpt-5"])
        #expect(view.debugModelSegmentTotalsByMonth["2026-06"] == [800_000, 400_000])
    }

    @MainActor
    @Test("同一模型在最近十二个月和最近三十天视图中使用同一图例颜色")
    func modelLegendColorsRemainStableAcrossMonthlyAndDailySnapshots() {
        let monthlyView = MonthlyTokenChartView()
        let dailyView = MonthlyTokenChartView()
        let monthlySnapshot = makeSnapshot(
            monthKeys: ["2026-06"],
            monthLabels: ["6月"],
            tokens: [300],
            modelBreakdowns: [
                0: [
                    ("claude-sonnet", 100),
                    ("gpt-5", 200),
                ],
            ]
        )
        let dailySnapshot = makeSnapshot(
            monthKeys: ["2026-06-20"],
            monthLabels: ["6/20"],
            tokens: [300],
            modelBreakdowns: [
                0: [
                    ("gpt-5", 200),
                    ("claude-sonnet", 100),
                ],
            ]
        )

        monthlyView.configure(with: monthlySnapshot)
        dailyView.configure(with: dailySnapshot)

        #expect(
            monthlyView.debugModelSegmentColorsByMonth["2026-06"]?["claude-sonnet"]
                == dailyView.debugModelSegmentColorsByMonth["2026-06-20"]?["claude-sonnet"]
        )
        #expect(
            monthlyView.debugModelSegmentColorsByMonth["2026-06"]?["gpt-5"]
                == dailyView.debugModelSegmentColorsByMonth["2026-06-20"]?["gpt-5"]
        )
    }

    @MainActor
    @Test("鼠标划过分段柱月份时回传该月模型明细")
    func hoveringStackedMonthBarEmitsModelBreakdownText() {
        let view = MonthlyTokenChartView()
        let snapshot = makeSnapshot(
            tokens: [0, 10, 20, 30, 40, 1_200_000, 60, 70, 80, 90, 100, 110],
            modelBreakdowns: [
                5: [
                    ("claude-sonnet", 800_000),
                    ("gpt-5", 400_000),
                ],
            ]
        )
        var hoverTexts: [String?] = []
        view.onHoverTextChange = { text in
            hoverTexts.append(text)
        }

        view.configure(with: snapshot)
        view.debugSimulateHover(monthKey: "2026-06")

        #expect(hoverTexts == ["6月 · 1.2M · claude-sonnet 0.8M, gpt-5 0.4M"])
    }

    @MainActor
    @Test("debug 高度与渲染使用相同的稳定 clamp 值")
    func debugHeightsUseClampedFiniteValues() {
        let view = MonthlyTokenChartView()
        let snapshot = makeSnapshot(normalizedHeights: [-0.2, 1.4, .nan, 0.25])

        view.configure(with: snapshot)

        #expect(view.debugNormalizedHeights[0] == 0)
        #expect(view.debugNormalizedHeights[1] == 1)
        #expect(view.debugNormalizedHeights[2] == 0)
        #expect(view.debugNormalizedHeights[3] == 0.25)
        #expect(view.debugNormalizedHeights.allSatisfy { $0.isFinite && (0...1).contains($0) })
    }

    private func makeSnapshot(
        tokens: [Int],
        modelBreakdowns: [Int: [(String, Int)]] = [:]
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
        return makeSnapshot(
            monthKeys: monthKeys,
            monthLabels: monthLabels,
            tokens: tokens,
            modelBreakdowns: modelBreakdowns
        )
    }

    private func makeSnapshot(
        monthKeys: [String],
        monthLabels: [String],
        tokens: [Int],
        modelBreakdowns: [Int: [(String, Int)]] = [:]
    ) -> MonthlyTokenChartSnapshot {
        let maxTokens = tokens.max() ?? 0
        let buckets = zip(monthKeys.indices, tokens).map { index, total in
            let modelSegments = (modelBreakdowns[index] ?? []).map { modelName, modelTotal in
                MonthlyTokenModelSegment(
                    modelName: modelName,
                    totalTokens: modelTotal,
                    percentage: total > 0 ? Double(modelTotal) / Double(total) : 0
                )
            }
            return MonthlyTokenBucket(
                id: monthKeys[index],
                monthKey: monthKeys[index],
                monthLabel: monthLabels[index],
                totalTokens: total,
                totalCost: 0,
                normalizedHeight: maxTokens > 0 ? Double(total) / Double(maxTokens) : 0,
                normalizedCostHeight: 0,
                isCurrentMonth: index == monthKeys.indices.last,
                modelSegments: modelSegments
            )
        }

        return MonthlyTokenChartSnapshot(
            monthBuckets: buckets,
            totalTokens: tokens.reduce(0, +),
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

    private func makeSnapshot(normalizedHeights: [Double]) -> MonthlyTokenChartSnapshot {
        let buckets = normalizedHeights.indices.map { index in
            MonthlyTokenBucket(
                id: "manual-\(index)",
                monthKey: "manual-\(index)",
                monthLabel: "\(index + 1)月",
                totalTokens: index,
                totalCost: 0,
                normalizedHeight: normalizedHeights[index],
                normalizedCostHeight: 0,
                isCurrentMonth: index == normalizedHeights.indices.last,
                modelSegments: []
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
