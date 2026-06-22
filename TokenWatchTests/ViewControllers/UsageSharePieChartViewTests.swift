import AppKit
import Testing
@testable import TokenWatch

@Suite("UsageSharePieChartView")
struct UsageSharePieChartViewTests {

    @MainActor
    @Test("配置 slices 后渲染标题和图例")
    func configureRendersTitleAndLegendRows() {
        let view = UsageSharePieChartView(title: "工具占比")

        view.configure(slices: [
            UsageShareSlice(id: "claude", label: "Claude Code", totalTokens: 300, percentage: 0.75),
            UsageShareSlice(id: "codex", label: "Codex", totalTokens: 100, percentage: 0.25),
        ])

        let labels = view.allDescendants(ofType: NSTextField.self).map(\.stringValue)
        #expect(labels.contains("工具占比"))
        #expect(labels.contains("Claude Code"))
        #expect(labels.contains("Codex"))
        #expect(view.debugLegendRowCount == 2)
        #expect(view.debugSliceLabels == ["Claude Code", "Codex"])
        #expect(view.debugPercentages == [0.75, 0.25])
        #expect(view.allDescendants(ofType: UsageSharePieDrawingView.self).count == 1)
    }

    @MainActor
    @Test("标题左对齐")
    func titleAlignsLeft() throws {
        let view = UsageSharePieChartView(title: "工具占比")
        view.frame = NSRect(x: 0, y: 0, width: 520, height: 170)

        view.configure(slices: [
            UsageShareSlice(id: "claude", label: "Claude Code", totalTokens: 300, percentage: 1.0),
        ])
        view.layoutSubtreeIfNeeded()

        let titleLabel = try #require(view.allDescendants(ofType: NSTextField.self).first {
            $0.stringValue == "工具占比"
        })
        let titleFrame = titleLabel.convert(titleLabel.bounds, to: view)
        #expect(titleLabel.alignment == .left)
        #expect(titleFrame.minX < 4)
    }

    @MainActor
    @Test("图例值只展示百分比并用 M 单位保留 token tooltip")
    func legendValuesShowOnlyPercentagesWithMillionTokenTooltip() {
        let view = UsageSharePieChartView(title: "模型占比")

        view.configure(slices: [
            UsageShareSlice(id: "codex-auto-review", label: "codex-auto-review", totalTokens: 24_600_000, percentage: 0.051),
            UsageShareSlice(id: "huoshan-zijie/GLM-5.1", label: "huoshan-zijie/GLM-5.1", totalTokens: 51_500, percentage: 0.0001),
        ])

        #expect(view.debugLegendNameLabels == ["codex-auto-review", "huoshan-zijie/GLM-5.1"])
        #expect(view.debugLegendValueLabels == ["5.1%", "0.0%"])
        #expect(view.debugLegendNameLineBreakModes.allSatisfy { $0 == .byTruncatingMiddle })
        let toolTips = view.allDescendants(ofType: NSStackView.self).compactMap(\.toolTip)
        #expect(toolTips.contains("codex-auto-review · 24.6M · 5.1%"))
    }

    @MainActor
    @Test("鼠标划过 slice 时标题右侧用 M 单位展示该项 token 用量")
    func hoveringSliceShowsMillionTokenUsageBesideTitle() {
        let view = UsageSharePieChartView(title: "工具占比")
        view.configure(slices: [
            UsageShareSlice(id: "claude", label: "Claude Code", totalTokens: 1_234_567, percentage: 0.75),
            UsageShareSlice(id: "codex", label: "Codex", totalTokens: 432_100, percentage: 0.25),
        ])

        view.debugSimulateHover(sliceID: "claude")

        #expect(view.debugHoverText == "Claude Code · 1.2M")

        view.debugSimulateHover(sliceID: nil)

        #expect(view.debugHoverText == "")
    }

    @MainActor
    @Test("标题右侧用量贴齐饼图右侧")
    func hoverUsageAlignsWithPieChartTrailingEdge() throws {
        let view = UsageSharePieChartView(title: "工具占比")
        view.frame = NSRect(x: 0, y: 0, width: 520, height: 170)
        view.configure(slices: [
            UsageShareSlice(id: "claude", label: "Claude Code", totalTokens: 300, percentage: 1.0),
        ])

        view.debugSimulateHover(sliceID: "claude")
        view.layoutSubtreeIfNeeded()

        #expect(view.debugHoverLabelTrailingAlignsWithChart)
    }

    @MainActor
    @Test("图例超过五项时合并剩余项为其他")
    func legendMergesOverflowRowsIntoOther() {
        let view = UsageSharePieChartView(title: "模型占比")

        view.configure(slices: [
            UsageShareSlice(id: "a", label: "a", totalTokens: 500, percentage: 0.50),
            UsageShareSlice(id: "b", label: "b", totalTokens: 200, percentage: 0.20),
            UsageShareSlice(id: "c", label: "c", totalTokens: 120, percentage: 0.12),
            UsageShareSlice(id: "d", label: "d", totalTokens: 80, percentage: 0.08),
            UsageShareSlice(id: "e", label: "e", totalTokens: 60, percentage: 0.06),
            UsageShareSlice(id: "f", label: "f", totalTokens: 40, percentage: 0.04),
        ])

        #expect(view.debugLegendRowCount == 5)
        #expect(view.debugSliceLabels == ["a", "b", "c", "d", "其他"])
        #expect(view.debugLegendValueLabels == ["50.0%", "20.0%", "12.0%", "8.0%", "10.0%"])
        #expect(view.debugPercentages == [0.50, 0.20, 0.12, 0.08, 0.10])
    }

    @MainActor
    @Test("重复配置会替换旧图例")
    func repeatedConfigureReplacesExistingLegendRows() {
        let view = UsageSharePieChartView(title: "模型占比")

        view.configure(slices: [
            UsageShareSlice(id: "a", label: "a", totalTokens: 1, percentage: 0.5),
            UsageShareSlice(id: "b", label: "b", totalTokens: 1, percentage: 0.5),
        ])
        view.configure(slices: [
            UsageShareSlice(id: "c", label: "c", totalTokens: 2, percentage: 1.0),
        ])

        #expect(view.debugLegendRowCount == 1)
        #expect(view.debugSliceLabels == ["c"])
        #expect(view.debugPercentages == [1.0])
    }

    @MainActor
    @Test("刷新时图例增加行数不会让首行上下跳动")
    func refreshWithMoreLegendRowsKeepsFirstRowVerticallyStable() throws {
        let view = UsageSharePieChartView(title: "工具占比")
        view.frame = NSRect(x: 0, y: 0, width: 520, height: 170)

        view.configure(slices: [
            UsageShareSlice(id: "claude", label: "Claude Code", totalTokens: 300, percentage: 1.0),
        ])
        view.layoutSubtreeIfNeeded()
        let initialFirstRowTop = try #require(view.legendRowTops().first)

        view.configure(slices: [
            UsageShareSlice(id: "claude", label: "Claude Code", totalTokens: 300, percentage: 0.60),
            UsageShareSlice(id: "codex", label: "Codex", totalTokens: 150, percentage: 0.30),
            UsageShareSlice(id: "opencode", label: "OpenCode", totalTokens: 50, percentage: 0.10),
        ])
        view.layoutSubtreeIfNeeded()

        let refreshedFirstRowTop = try #require(view.legendRowTops().first)
        #expect(abs(refreshedFirstRowTop - initialFirstRowTop) < 0.5)
    }

    @MainActor
    @Test("饼图绘制视图贴齐内容左侧")
    func pieDrawingViewAlignsToLeadingEdge() throws {
        let view = UsageSharePieChartView(title: "工具占比")
        view.frame = NSRect(x: 0, y: 0, width: 520, height: 170)

        view.configure(slices: [
            UsageShareSlice(id: "claude", label: "Claude Code", totalTokens: 300, percentage: 0.75),
            UsageShareSlice(id: "codex", label: "Codex", totalTokens: 100, percentage: 0.25),
        ])
        view.layoutSubtreeIfNeeded()

        let drawingView = try #require(view.firstDescendant(ofType: UsageSharePieDrawingView.self))
        let drawingFrame = drawingView.convert(drawingView.bounds, to: view)
        #expect(abs(drawingFrame.minX) < 0.5)
        #expect(drawingView.intrinsicContentSize.width == 128)
        #expect(drawingView.intrinsicContentSize.height == 128)
    }

    @MainActor
    @Test("空 slices 展示暂无数据")
    func emptySlicesShowNoDataLabel() {
        let view = UsageSharePieChartView(title: "模型占比")

        view.configure(slices: [])

        let labels = view.allDescendants(ofType: NSTextField.self).map(\.stringValue)
        #expect(labels.contains("暂无数据"))
        #expect(view.debugLegendRowCount == 0)
        #expect(view.debugSliceLabels.isEmpty)
    }

}

private extension NSView {
    func allDescendants<T: NSView>(ofType type: T.Type) -> [T] {
        let current = (self as? T).map { [$0] } ?? []
        return current + subviews.flatMap { $0.allDescendants(ofType: type) }
    }

    func firstDescendant<T: NSView>(ofType type: T.Type) -> T? {
        allDescendants(ofType: type).first
    }

    func legendRowTops() -> [CGFloat] {
        allDescendants(ofType: NSStackView.self)
            .filter { $0.toolTip != nil }
            .map { row in row.convert(row.bounds, to: self).maxY }
            .sorted(by: >)
    }
}
