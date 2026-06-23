import AppKit
import Charts
import SwiftUI

enum MonthlyBarChartStyle {
    static let regularBarColor = NSColor.systemBlue
    static let currentMonthBarColor = NSColor.controlAccentColor
    static let monthAxisLabelFontSize: CGFloat = 8

    static var regularBarSwiftUIColor: Color {
        Color(nsColor: regularBarColor)
    }

    static var currentMonthBarSwiftUIColor: Color {
        Color(nsColor: currentMonthBarColor)
    }

    static func monthAxisLabel(for monthKey: String) -> String {
        let parts = monthKey.split(separator: "-")
        guard parts.count == 2,
              let year = Int(parts[0]),
              let month = Int(parts[1]) else {
            return monthKey
        }
        return "\(year)年\n\(month)月"
    }

    static func tokenAxisLabel(for value: Double) -> String {
        let tokens = max(0, Int(value.rounded()))
        if tokens < 1_000 {
            return String(tokens)
        }
        if tokens < 1_000_000 {
            return "\(Int((Double(tokens) / 1_000).rounded()))k"
        }
        return "\(Int((Double(tokens) / 1_000_000).rounded()))M"
    }

    static func costAxisLabel(for value: Double) -> String {
        "$\(max(0, Int(value.rounded())))"
    }
}

/// 最近 12 个月 token 柱状图。只消费 snapshot,不读取 ViewModel。
final class MonthlyTokenChartView: NSView {
    private let chartHost = NSHostingView(rootView: AnyView(MonthlyTokenBarChartContent(buckets: [], onHoverMonthKeyChange: { _ in })))
    private var buckets: [MonthlyTokenBucket] = []
    private(set) var debugNormalizedHeights: [Double] = []
    private(set) var debugMonthLabels: [String] = []
    private(set) var debugXAxisLabels: [String] = []
    private(set) var debugModelSegmentLabelsByMonth: [String: [String]] = [:]
    private(set) var debugModelSegmentTotalsByMonth: [String: [Int]] = [:]
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

    /// 用新的 snapshot 替换图表内容。
    func configure(with snapshot: MonthlyTokenChartSnapshot) {
        buckets = snapshot.monthBuckets
        debugNormalizedHeights = snapshot.monthBuckets.map { clampNormalizedHeight($0.normalizedHeight) }
        debugMonthLabels = snapshot.monthBuckets.map(\.monthLabel)
        debugXAxisLabels = snapshot.monthBuckets.map { MonthlyBarChartStyle.monthAxisLabel(for: $0.monthKey) }
        debugModelSegmentLabelsByMonth = Dictionary(uniqueKeysWithValues: snapshot.monthBuckets.map { bucket in
            (bucket.monthKey, bucket.modelSegments.map(\.modelName))
        })
        debugModelSegmentTotalsByMonth = Dictionary(uniqueKeysWithValues: snapshot.monthBuckets.map { bucket in
            (bucket.monthKey, bucket.modelSegments.map(\.totalTokens))
        })
        chartHost.rootView = AnyView(MonthlyTokenBarChartContent(
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
        MonthlyBarChartStyle.tokenAxisLabel(for: value)
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
        var hoverText = "\(bucket.monthLabel) · \(CompactNumberFormatter.formatMillions(bucket.totalTokens))"
        let modelText = bucket.modelSegments
            .map { "\($0.modelName) \(CompactNumberFormatter.formatMillions($0.totalTokens))" }
            .joined(separator: ", ")
        if !modelText.isEmpty {
            hoverText += " · \(modelText)"
        }
        onHoverTextChange?(hoverText)
    }
}

private func clampNormalizedHeight(_ value: Double) -> Double {
    guard value.isFinite else { return 0 }
    return min(max(value, 0), 1)
}

private struct MonthlyTokenBarChartContent: View {
    let buckets: [MonthlyTokenBucket]
    let onHoverMonthKeyChange: (String?) -> Void

    private var maxTokens: Double {
        max(1, Double(buckets.map(\.totalTokens).max() ?? 0))
    }

    var body: some View {
        Chart {
            ForEach(buckets) { bucket in
                if bucket.modelSegments.isEmpty {
                    BarMark(
                        x: .value("月份", bucket.monthKey),
                        y: .value("Tokens", Double(bucket.totalTokens))
                    )
                    .foregroundStyle(
                        bucket.isCurrentMonth
                            ? MonthlyBarChartStyle.currentMonthBarSwiftUIColor
                            : MonthlyBarChartStyle.regularBarSwiftUIColor
                    )
                    .cornerRadius(4)
                    .accessibilityLabel(bucket.monthLabel)
                    .accessibilityValue(CompactNumberFormatter.formatMillions(bucket.totalTokens))
                } else {
                    ForEach(bucket.modelSegments) { segment in
                        BarMark(
                            x: .value("月份", bucket.monthKey),
                            y: .value("Tokens", Double(segment.totalTokens))
                        )
                        .foregroundStyle(by: .value("模型", segment.modelName))
                        .opacity(bucket.isCurrentMonth ? 1 : 0.74)
                        .cornerRadius(4)
                        .accessibilityLabel("\(bucket.monthLabel) \(segment.modelName)")
                        .accessibilityValue(CompactNumberFormatter.formatMillions(segment.totalTokens))
                    }
                }
            }
        }
        .chartLegend(position: .bottom, alignment: .trailing, spacing: 8)
        .chartYScale(domain: 0...maxTokens)
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
                if let tokens = value.as(Double.self) {
                    AxisValueLabel(MonthlyBarChartStyle.tokenAxisLabel(for: tokens))
                }
            }
        }
        .chartOverlay { proxy in
            hoverOverlay(proxy: proxy)
        }
        .padding(.top, 8)
        .frame(minHeight: 220)
        .accessibilityLabel("最近 12 个月 token 柱状图")
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
