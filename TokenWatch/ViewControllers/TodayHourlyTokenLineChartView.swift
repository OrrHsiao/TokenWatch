import AppKit
import Charts
import SwiftUI

/// 状态栏 popover 专用的本日小时 token 折线图。
final class TodayHourlyTokenLineChartView: NSView {
    private static let visibleAxisHourIndexes = [0, 6, 12, 18, 23]
    private static let hoverLabelToChartSpacing: CGFloat = 1

    private let chartHost = NSHostingView(rootView: AnyView(TodayHourlyTokenLineChartContent(
        buckets: [],
        language: .zhHans,
        axisKeys: [],
        accessibilityLabelText: UsageStatsPeriod.today.tokenChartAccessibilityLabel(language: .zhHans),
        onHoverMonthKeyChange: { _ in }
    )))
    private let hoverLabel = NSTextField(labelWithString: "")
    private var buckets: [MonthlyTokenBucket] = []
    private var language: AppLanguage = .zhHans
    private var hoverLabelTopConstraint: NSLayoutConstraint?
    private var hoverLabelTrailingConstraint: NSLayoutConstraint?

    private(set) var debugNormalizedHeights: [Double] = []
    private(set) var debugXAxisLabels: [String] = []
    private(set) var debugAccessibilityLabel = UsageStatsPeriod.today
        .tokenChartAccessibilityLabel(language: .zhHans)

    var debugPointCount: Int { buckets.count }
    var debugHoverText: String { hoverLabel.stringValue }
    var debugHoverLabelTopAlignsWithChartView: Bool {
        hoverLabelTopConstraint?.isActive == true
            && hoverLabelTopConstraint?.constant == 0
    }
    var debugHoverLabelTrailingAlignsWithChartView: Bool {
        hoverLabelTrailingConstraint?.isActive == true
            && hoverLabelTrailingConstraint?.constant == 0
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setupView()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupView()
    }

    /// 用新的小时 snapshot 替换折线图内容。
    func configure(with snapshot: MonthlyTokenChartSnapshot, language: AppLanguage = .zhHans) {
        self.language = language
        buckets = snapshot.monthBuckets
        hoverLabel.stringValue = ""
        debugNormalizedHeights = snapshot.monthBuckets.map { clampHourlyNormalizedHeight($0.normalizedHeight) }
        debugXAxisLabels = Self.visibleAxisHourIndexes.compactMap { index in
            guard snapshot.monthBuckets.indices.contains(index) else { return nil }
            return MonthlyBarChartStyle.monthAxisLabel(
                for: snapshot.monthBuckets[index].monthKey,
                language: language
            )
        }
        debugAccessibilityLabel = UsageStatsPeriod.today.tokenChartAccessibilityLabel(language: language)

        let axisKeys = Self.visibleAxisHourIndexes.compactMap { index in
            snapshot.monthBuckets.indices.contains(index) ? snapshot.monthBuckets[index].monthKey : nil
        }
        chartHost.rootView = AnyView(TodayHourlyTokenLineChartContent(
            buckets: snapshot.monthBuckets,
            language: language,
            axisKeys: axisKeys,
            accessibilityLabelText: debugAccessibilityLabel,
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
        hoverLabel.font = .systemFont(ofSize: 10, weight: .medium)
        hoverLabel.textColor = .secondaryLabelColor
        hoverLabel.alignment = .right
        hoverLabel.lineBreakMode = .byTruncatingMiddle
        hoverLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        hoverLabel.translatesAutoresizingMaskIntoConstraints = false
        addSubview(hoverLabel)

        let hoverLabelTopConstraint = hoverLabel.topAnchor.constraint(equalTo: topAnchor)
        let hoverLabelTrailingConstraint = hoverLabel.trailingAnchor.constraint(equalTo: trailingAnchor)
        self.hoverLabelTopConstraint = hoverLabelTopConstraint
        self.hoverLabelTrailingConstraint = hoverLabelTrailingConstraint

        NSLayoutConstraint.activate([
            chartHost.leadingAnchor.constraint(equalTo: leadingAnchor),
            chartHost.trailingAnchor.constraint(equalTo: trailingAnchor),
            chartHost.topAnchor.constraint(equalTo: hoverLabel.bottomAnchor, constant: Self.hoverLabelToChartSpacing),
            chartHost.bottomAnchor.constraint(equalTo: bottomAnchor),
            hoverLabelTopConstraint,
            hoverLabelTrailingConstraint,
            hoverLabel.leadingAnchor.constraint(greaterThanOrEqualTo: leadingAnchor),
        ])
    }

    private func updateHoverText(monthKey: String?) {
        guard let monthKey,
              let bucket = buckets.first(where: { $0.monthKey == monthKey }) else {
            hoverLabel.stringValue = ""
            return
        }
        let periodLabel = MonthlyBarChartStyle.hoverPeriodLabel(
            for: bucket.monthKey,
            fallback: bucket.monthLabel,
            language: language
        )
        hoverLabel.stringValue = "\(periodLabel) · \(CompactNumberFormatter.formatHoverTokens(bucket.totalTokens))"
    }
}

private func clampHourlyNormalizedHeight(_ value: Double) -> Double {
    guard value.isFinite else { return 0 }
    return min(max(value, 0), 1)
}

private struct TodayHourlyTokenLineChartContent: View {
    let buckets: [MonthlyTokenBucket]
    let language: AppLanguage
    let axisKeys: [String]
    let accessibilityLabelText: String
    let onHoverMonthKeyChange: (String?) -> Void

    private var maxTokens: Double {
        max(1, Double(buckets.map(\.totalTokens).max() ?? 0))
    }

    var body: some View {
        Chart {
            ForEach(buckets) { bucket in
                LineMark(
                    x: .value(axisValueName, bucket.monthKey),
                    y: .value("Tokens", Double(bucket.totalTokens))
                )
                .foregroundStyle(Color(nsColor: .controlAccentColor))
                .lineStyle(StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
                .accessibilityLabel(accessibilityLabel(for: bucket))
                .accessibilityValue(CompactNumberFormatter.formatMillions(bucket.totalTokens))

                if bucket.isCurrentMonth {
                    PointMark(
                        x: .value(axisValueName, bucket.monthKey),
                        y: .value("Tokens", Double(bucket.totalTokens))
                    )
                    .foregroundStyle(Color(nsColor: .controlAccentColor))
                    .symbolSize(22)
                }
            }
        }
        .chartLegend(.hidden)
        .chartYScale(domain: 0...maxTokens)
        .chartXAxis {
            AxisMarks(values: axisKeys) { value in
                AxisTick()
                AxisValueLabel {
                    if let monthKey = value.as(String.self) {
                        Text(MonthlyBarChartStyle.monthAxisLabel(for: monthKey, language: language))
                            .font(.system(size: 8))
                    }
                }
            }
        }
        .chartYAxis {
            AxisMarks(position: .leading, values: .automatic(desiredCount: 3)) { value in
                AxisGridLine()
                    .foregroundStyle(.secondary.opacity(0.16))
                AxisTick()
                if let tokens = value.as(Double.self) {
                    AxisValueLabel(MonthlyBarChartStyle.tokenAxisLabel(for: tokens))
                        .font(.system(size: 8))
                }
            }
        }
        .chartOverlay { proxy in
            hoverOverlay(proxy: proxy)
        }
        .padding(.top, 4)
        .accessibilityLabel(accessibilityLabelText)
    }

    private var axisValueName: String {
        language.periodAxisValueName
    }

    private func accessibilityLabel(for bucket: MonthlyTokenBucket) -> String {
        MonthlyBarChartStyle.hoverPeriodLabel(
            for: bucket.monthKey,
            fallback: bucket.monthLabel,
            language: language
        )
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
