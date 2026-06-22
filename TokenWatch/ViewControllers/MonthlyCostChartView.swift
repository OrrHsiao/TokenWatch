import AppKit
import Charts
import SwiftUI

/// 本年 12 个月费用柱状图。只消费 snapshot,不读取 ViewModel。
final class MonthlyCostChartView: NSView {
    private let chartHost = NSHostingView(rootView: AnyView(MonthlyCostBarChartContent(buckets: [], onHoverMonthKeyChange: { _ in })))
    private var buckets: [MonthlyTokenBucket] = []
    private(set) var debugNormalizedHeights: [Double] = []
    private(set) var debugMonthLabels: [String] = []
    var onHoverTextChange: ((String?) -> Void)?

    var debugRegularBarColor: NSColor {
        MonthlyBarChartStyle.regularBarColor
    }

    var debugCurrentMonthBarColor: NSColor {
        MonthlyBarChartStyle.currentMonthBarColor
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
        onHoverTextChange?("\(bucket.monthLabel) · \(formatCurrency(bucket.totalCost))")
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
        Chart(buckets) { bucket in
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
        }
        .chartLegend(.hidden)
        .chartYScale(domain: 0...maxCost)
        .chartXAxis {
            AxisMarks(values: buckets.map(\.monthKey)) { value in
                AxisTick()
                AxisValueLabel {
                    if let monthKey = value.as(String.self) {
                        Text(monthLabel(for: monthKey))
                    }
                }
            }
        }
        .chartYAxis {
            AxisMarks(position: .leading) {
                AxisGridLine()
                    .foregroundStyle(.secondary.opacity(0.18))
                AxisTick()
                AxisValueLabel()
            }
        }
        .chartOverlay { proxy in
            hoverOverlay(proxy: proxy)
        }
        .padding(.top, 8)
        .frame(minHeight: 220)
        .accessibilityLabel("本年费用柱状图")
    }

    private func monthLabel(for monthKey: String) -> String {
        buckets.first { $0.monthKey == monthKey }?.monthLabel ?? monthKey
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
