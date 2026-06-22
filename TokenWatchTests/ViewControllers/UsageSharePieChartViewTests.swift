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
    }

    @MainActor
    @Test("长图例名称保持完整文本并单独分离数值列")
    func longLegendNamesRemainFullTextWithSeparateValueColumn() {
        let view = UsageSharePieChartView(title: "模型占比")

        view.configure(slices: [
            UsageShareSlice(id: "codex-auto-review", label: "codex-auto-review", totalTokens: 24_600_000, percentage: 0.051),
            UsageShareSlice(id: "huoshan-zijie/GLM-5.1", label: "huoshan-zijie/GLM-5.1", totalTokens: 51_500, percentage: 0.0001),
        ])

        #expect(view.debugLegendNameLabels == ["codex-auto-review", "huoshan-zijie/GLM-5.1"])
        #expect(view.debugLegendValueLabels == ["5.1% · 24.6M", "0.0% · 51.5k"])
        #expect(view.debugLegendNameLineBreakModes.allSatisfy { $0 == .byClipping })
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
    @Test("空 slices 展示暂无数据")
    func emptySlicesShowNoDataLabel() {
        let view = UsageSharePieChartView(title: "模型占比")

        view.configure(slices: [])

        let labels = view.allDescendants(ofType: NSTextField.self).map(\.stringValue)
        #expect(labels.contains("暂无数据"))
        #expect(view.debugLegendRowCount == 0)
        #expect(view.debugSliceLabels.isEmpty)
    }

    @MainActor
    @Test("饼图绘制视图提供稳定尺寸")
    func drawingViewHasDeterministicIntrinsicSize() {
        let drawingView = UsageSharePieDrawingView()

        #expect(drawingView.intrinsicContentSize.width == 128)
        #expect(drawingView.intrinsicContentSize.height == 128)
    }
}

private extension NSView {
    func allDescendants<T: NSView>(ofType type: T.Type) -> [T] {
        let current = (self as? T).map { [$0] } ?? []
        return current + subviews.flatMap { $0.allDescendants(ofType: type) }
    }
}
