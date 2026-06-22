import AppKit
import Charts
import SwiftUI

enum MonthlyBarChartStyle {
    static let regularBarColor = NSColor.systemBlue
    static let currentMonthBarColor = NSColor.controlAccentColor

    static var regularBarSwiftUIColor: Color {
        Color(nsColor: regularBarColor)
    }

    static var currentMonthBarSwiftUIColor: Color {
        Color(nsColor: currentMonthBarColor)
    }
}

/// 过去 12 个月 token 柱状图。只消费 snapshot,不读取 ViewModel。
final class MonthlyTokenChartView: NSView {
    private let chartHost = NSHostingView(rootView: AnyView(MonthlyTokenBarChartContent(buckets: [])))
    private(set) var debugNormalizedHeights: [Double] = []
    private(set) var debugMonthLabels: [String] = []

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

    /// 用新的 snapshot 替换图表内容。
    func configure(with snapshot: MonthlyTokenChartSnapshot) {
        debugNormalizedHeights = snapshot.monthBuckets.map { clampNormalizedHeight($0.normalizedHeight) }
        debugMonthLabels = snapshot.monthBuckets.map(\.monthLabel)
        chartHost.rootView = AnyView(MonthlyTokenBarChartContent(buckets: snapshot.monthBuckets))
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
}

private func clampNormalizedHeight(_ value: Double) -> Double {
    guard value.isFinite else { return 0 }
    return min(max(value, 0), 1)
}

private struct MonthlyTokenBarChartContent: View {
    let buckets: [MonthlyTokenBucket]

    private var maxTokens: Double {
        max(1, Double(buckets.map(\.totalTokens).max() ?? 0))
    }

    var body: some View {
        Chart(buckets) { bucket in
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
            .accessibilityValue("\(bucket.totalTokens) tokens")
        }
        .chartLegend(.hidden)
        .chartYScale(domain: 0...maxTokens)
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
        .padding(.top, 8)
        .frame(minHeight: 220)
        .accessibilityLabel("过去 12 个月 token 柱状图")
    }

    private func monthLabel(for monthKey: String) -> String {
        buckets.first { $0.monthKey == monthKey }?.monthLabel ?? monthKey
    }
}
