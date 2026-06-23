import AppKit
import Charts
import SwiftUI

/// 最近 12 个月费用柱状图。只消费 snapshot,不读取 ViewModel。
final class MonthlyCostChartView: NSView {
    private let chartHost = NSHostingView(rootView: AnyView(MonthlyCostBarChartContent(buckets: [], onHoverMonthKeyChange: { _ in })))
    private var buckets: [MonthlyTokenBucket] = []
    private(set) var debugNormalizedHeights: [Double] = []
    private(set) var debugMonthLabels: [String] = []
    private(set) var debugXAxisLabels: [String] = []
    private(set) var debugModelSegmentLabelsByMonth: [String: [String]] = [:]
    private(set) var debugModelSegmentCostsByMonth: [String: [Double]] = [:]
    var onHoverTextChange: ((String?) -> Void)?

    var debugRegularBarColor: NSColor {
        MonthlyBarChartStyle.regularBarColor
    }

    var debugCurrentMonthBarColor: NSColor {
        MonthlyBarChartStyle.currentMonthBarColor
    }

    var debugLegendAlignment: Alignment {
        .trailing
    }

    var debugXAxisLabelFontSize: CGFloat {
        MonthlyBarChartStyle.monthAxisLabelFontSize
    }

    var debugBarCount: Int {
        debugMonthLabels.count
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setupView()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupView()
    }

    /// 用新的 snapshot 替换费用图表内容。
    func configure(with snapshot: MonthlyTokenChartSnapshot) {
        buckets = snapshot.monthBuckets
        debugNormalizedHeights = snapshot.monthBuckets.map { clampNormalizedCostHeight($0.normalizedCostHeight) }
        debugMonthLabels = snapshot.monthBuckets.map(\.monthLabel)
        debugXAxisLabels = snapshot.monthBuckets.map { MonthlyBarChartStyle.monthAxisLabel(for: $0.monthKey) }
        debugModelSegmentLabelsByMonth = Dictionary(uniqueKeysWithValues: snapshot.monthBuckets.map { bucket in
            (bucket.monthKey, bucket.modelSegments.map(\.modelName))
        })
        debugModelSegmentCostsByMonth = Dictionary(uniqueKeysWithValues: snapshot.monthBuckets.map { bucket in
            (bucket.monthKey, bucket.modelSegments.map(\.totalCost))
        })
        chartHost.rootView = AnyView(MonthlyCostBarChartContent(
            buckets: snapshot.monthBuckets,
            onHoverMonthKeyChange: { [weak self] monthKey in
                self?.updateHoverText(monthKey: monthKey)
            }
        ))
    }

    func debugSimulateHover(monthKey: String?) {
        updateHoverText(monthKey: monthKey)
    }

    func debugYAxisLabel(for value: Double) -> String {
        MonthlyBarChartStyle.costAxisLabel(for: value)
    }

    private func setupView() {
        wantsLayer = true
        layer?.backgroundColor = NSColor.clear.cgColor

        chartHost.translatesAutoresizingMaskIntoConstraints = false

        addSubview(chartHost)
        NSLayoutConstraint.activate([
            chartHost.leadingAnchor.constraint(equalTo: leadingAnchor),
            chartHost.trailingAnchor.constraint(equalTo: trailingAnchor),
            chartHost.topAnchor.constraint(equalTo: topAnchor),
            chartHost.bottomAnchor.constraint(equalTo: bottomAnchor),
            heightAnchor.constraint(greaterThanOrEqualToConstant: 220),
        ])
    }

    private func updateHoverText(monthKey: String?) {
        guard let monthKey,
              let bucket = buckets.first(where: { $0.monthKey == monthKey }) else {
            onHoverTextChange?(nil)
            return
        }
        var hoverText = "\(bucket.monthLabel) · \(formatCurrency(bucket.totalCost))"
        let modelText = bucket.modelSegments
            .filter { $0.totalCost > 0 }
            .map { "\($0.modelName) \(formatCurrency($0.totalCost))" }
            .joined(separator: ", ")
        if !modelText.isEmpty {
            hoverText += " · \(modelText)"
        }
        onHoverTextChange?(hoverText)
    }

    private func formatCurrency(_ value: Double) -> String {
        String(format: "$%.2f", value)
    }
}

private func clampNormalizedCostHeight(_ value: Double) -> Double {
    guard value.isFinite else { return 0 }
    return min(max(value, 0), 1)
}

private struct MonthlyCostBarChartContent: View {
    let buckets: [MonthlyTokenBucket]
    let onHoverMonthKeyChange: (String?) -> Void

    private var maxCost: Double {
        max(1, buckets.map(\.totalCost).max() ?? 0)
    }

    var body: some View {
        Chart {
            ForEach(buckets) { bucket in
                if bucket.modelSegments.isEmpty {
                    BarMark(
                        x: .value("月份", bucket.monthKey),
                        y: .value("USD", bucket.totalCost)
                    )
                    .foregroundStyle(
                        bucket.isCurrentMonth
                            ? MonthlyBarChartStyle.currentMonthBarSwiftUIColor
                            : MonthlyBarChartStyle.regularBarSwiftUIColor
                    )
                    .cornerRadius(4)
                    .accessibilityLabel(bucket.monthLabel)
                    .accessibilityValue(String(format: "$%.2f", bucket.totalCost))
                } else {
                    ForEach(bucket.modelSegments) { segment in
                        BarMark(
                            x: .value("月份", bucket.monthKey),
                            y: .value("USD", segment.totalCost)
                        )
                        .foregroundStyle(by: .value("模型", segment.modelName))
                        .opacity(bucket.isCurrentMonth ? 1 : 0.74)
                        .cornerRadius(4)
                        .accessibilityLabel("\(bucket.monthLabel) \(segment.modelName)")
                        .accessibilityValue(String(format: "$%.2f", segment.totalCost))
                    }
                }
            }
        }
        .chartLegend(position: .bottom, alignment: .trailing, spacing: 8)
        .chartYScale(domain: 0...maxCost)
        .chartXAxis {
            AxisMarks(values: buckets.map(\.monthKey)) { value in
                AxisTick()
                AxisValueLabel {
                    if let monthKey = value.as(String.self) {
                        Text(MonthlyBarChartStyle.monthAxisLabel(for: monthKey))
                            .font(.system(size: MonthlyBarChartStyle.monthAxisLabelFontSize))
                            .multilineTextAlignment(.center)
                            .lineLimit(2)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
        .chartYAxis {
            AxisMarks(position: .leading) { value in
                AxisGridLine()
                    .foregroundStyle(.secondary.opacity(0.18))
                AxisTick()
                if let cost = value.as(Double.self) {
                    AxisValueLabel(MonthlyBarChartStyle.costAxisLabel(for: cost))
                }
            }
        }
        .chartOverlay { proxy in
            hoverOverlay(proxy: proxy)
        }
        .padding(.top, 8)
        .frame(minHeight: 220)
        .accessibilityLabel("最近 12 个月费用柱状图")
    }

    private func hoverOverlay(proxy: ChartProxy) -> some View {
        GeometryReader { geometry in
            Rectangle()
                .fill(.clear)
                .contentShape(Rectangle())
                .onContinuousHover { phase in
                    guard let plotFrame = proxy.plotFrame else {
                        onHoverMonthKeyChange(nil)
                        return
                    }
                    let frame = geometry[plotFrame]
                    switch phase {
                    case .active(let location):
                        guard frame.contains(location) else {
                            onHoverMonthKeyChange(nil)
                            return
                        }
                        let xPosition = location.x - frame.origin.x
                        onHoverMonthKeyChange(proxy.value(atX: xPosition, as: String.self))
                    case .ended:
                        onHoverMonthKeyChange(nil)
                    }
                }
        }
    }
}
