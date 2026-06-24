import AppKit
import Charts
import SwiftUI

enum MonthlyBarChartStyle {
    static let regularBarColor = NSColor.systemBlue
    static let currentMonthBarColor = NSColor.controlAccentColor
    static let monthAxisLabelFontSize: CGFloat = 8
    private static let otherModelColor = NSColor.systemGray
    private static let modelColorPalette: [NSColor] = [
        .systemBlue,
        .systemGreen,
        .systemOrange,
        .systemPurple,
        .systemPink,
        .systemTeal,
        .systemIndigo,
        .systemYellow,
        .systemRed,
        .systemBrown,
    ]

    static var regularBarSwiftUIColor: Color {
        Color(nsColor: regularBarColor)
    }

    static var currentMonthBarSwiftUIColor: Color {
        Color(nsColor: currentMonthBarColor)
    }

    static func monthAxisLabel(for monthKey: String, language: AppLanguage = .zhHans) -> String {
        if let hourSeparatorRange = monthKey.range(of: "T"),
           let hour = Int(monthKey[hourSeparatorRange.upperBound...]) {
            return "\(hour)"
        }

        let parts = monthKey.split(separator: "-")
        if parts.count == 3,
           let month = Int(parts[1]),
           let day = Int(parts[2]) {
            return "\(month)/\n\(day)"
        }
        guard parts.count == 2,
              let year = Int(parts[0]),
              let month = Int(parts[1]) else {
            return monthKey
        }
        switch language {
        case .zhHans:
            return "\(year)年\n\(month)月"
        case .en:
            return "\(year)\n\(UsageStatsPeriod.englishShortMonthName(for: month))"
        }
    }

    static func hoverPeriodLabel(
        for monthKey: String,
        fallback: String,
        language: AppLanguage = .zhHans
    ) -> String {
        switch language {
        case .zhHans:
            return fallback
        case .en:
            return monthAxisLabel(for: monthKey, language: language)
                .replacingOccurrences(of: "\n", with: " ")
        }
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

    static func modelColor(for segment: MonthlyTokenModelSegment) -> NSColor {
        guard !segment.isOverflow else { return otherModelColor }
        return modelColorPalette[stablePaletteIndex(for: segment.id)]
    }

    static func modelSwiftUIColor(for segment: MonthlyTokenModelSegment) -> Color {
        Color(nsColor: modelColor(for: segment))
    }

    static func modelColorDebugMap(for bucket: MonthlyTokenBucket) -> [String: NSColor] {
        Dictionary(uniqueKeysWithValues: bucket.modelSegments.map { segment in
            (segment.id, modelColor(for: segment))
        })
    }

    private static func stablePaletteIndex(for value: String) -> Int {
        var hash: UInt64 = 1_469_598_103_934_665_603
        for byte in value.utf8 {
            hash ^= UInt64(byte)
            hash &*= 1_099_511_628_211
        }
        return Int(hash % UInt64(modelColorPalette.count))
    }
}

/// 最近 12 个月 token 柱状图。只消费 snapshot,不读取 ViewModel。
final class MonthlyTokenChartView: NSView {
    private let chartHost = NSHostingView(rootView: AnyView(MonthlyTokenBarChartContent(
        buckets: [],
        language: .zhHans,
        accessibilityLabelText: UsageStatsPeriod.recent12Months.tokenChartAccessibilityLabel(language: .zhHans),
        onHoverMonthKeyChange: { _ in }
    )))
    private var buckets: [MonthlyTokenBucket] = []
    private(set) var debugNormalizedHeights: [Double] = []
    private(set) var debugMonthLabels: [String] = []
    private(set) var debugXAxisLabels: [String] = []
    private(set) var debugModelSegmentLabelsByMonth: [String: [String]] = [:]
    private(set) var debugModelSegmentTotalsByMonth: [String: [Int]] = [:]
    private(set) var debugModelSegmentColorsByMonth: [String: [String: NSColor]] = [:]
    private(set) var debugAccessibilityLabel = UsageStatsPeriod.recent12Months
        .tokenChartAccessibilityLabel(language: .zhHans)
    var onHoverTextChange: ((String?) -> Void)?
    private var language: AppLanguage = .zhHans

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
    func configure(
        with snapshot: MonthlyTokenChartSnapshot,
        period: UsageStatsPeriod = .recent12Months,
        language: AppLanguage = .zhHans
    ) {
        self.language = language
        debugAccessibilityLabel = period.tokenChartAccessibilityLabel(language: language)
        buckets = snapshot.monthBuckets
        debugNormalizedHeights = snapshot.monthBuckets.map { clampNormalizedHeight($0.normalizedHeight) }
        debugMonthLabels = snapshot.monthBuckets.map(\.monthLabel)
        debugXAxisLabels = snapshot.monthBuckets.map {
            MonthlyBarChartStyle.monthAxisLabel(for: $0.monthKey, language: language)
        }
        debugModelSegmentLabelsByMonth = Dictionary(uniqueKeysWithValues: snapshot.monthBuckets.map { bucket in
            (bucket.monthKey, bucket.modelSegments.map(\.modelName))
        })
        debugModelSegmentTotalsByMonth = Dictionary(uniqueKeysWithValues: snapshot.monthBuckets.map { bucket in
            (bucket.monthKey, bucket.modelSegments.map(\.totalTokens))
        })
        debugModelSegmentColorsByMonth = Dictionary(uniqueKeysWithValues: snapshot.monthBuckets.map { bucket in
            (bucket.monthKey, MonthlyBarChartStyle.modelColorDebugMap(for: bucket))
        })
        chartHost.rootView = AnyView(MonthlyTokenBarChartContent(
            buckets: snapshot.monthBuckets,
            language: language,
            accessibilityLabelText: debugAccessibilityLabel,
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
        let periodLabel = MonthlyBarChartStyle.hoverPeriodLabel(
            for: bucket.monthKey,
            fallback: bucket.monthLabel,
            language: language
        )
        var hoverText = "\(periodLabel) · \(CompactNumberFormatter.formatMillions(bucket.totalTokens))"
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
    let language: AppLanguage
    let accessibilityLabelText: String
    let onHoverMonthKeyChange: (String?) -> Void

    private var maxTokens: Double {
        max(1, Double(buckets.map(\.totalTokens).max() ?? 0))
    }

    var body: some View {
        Chart {
            ForEach(buckets) { bucket in
                if bucket.modelSegments.isEmpty {
                    BarMark(
                        x: .value(axisValueName, bucket.monthKey),
                        y: .value("Tokens", Double(bucket.totalTokens))
                    )
                    .foregroundStyle(
                        bucket.isCurrentMonth
                            ? MonthlyBarChartStyle.currentMonthBarSwiftUIColor
                            : MonthlyBarChartStyle.regularBarSwiftUIColor
                    )
                    .cornerRadius(4)
                    .accessibilityLabel(accessibilityLabel(for: bucket))
                    .accessibilityValue(CompactNumberFormatter.formatMillions(bucket.totalTokens))
                } else {
                    ForEach(bucket.modelSegments) { segment in
                        let accessibilityLabel = "\(accessibilityLabel(for: bucket)) \(segment.modelName)"
                        BarMark(
                            x: .value(axisValueName, bucket.monthKey),
                            y: .value("Tokens", Double(segment.totalTokens))
                        )
                        .foregroundStyle(MonthlyBarChartStyle.modelSwiftUIColor(for: segment))
                        .opacity(bucket.isCurrentMonth ? 1 : 0.74)
                        .cornerRadius(4)
                        .accessibilityLabel(accessibilityLabel)
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
                        Text(MonthlyBarChartStyle.monthAxisLabel(for: monthKey, language: language))
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
        .accessibilityLabel(accessibilityLabelText)
    }

    private var axisValueName: String {
        switch language {
        case .zhHans:
            return "月份"
        case .en:
            return "Period"
        }
    }

    private func accessibilityLabel(for bucket: MonthlyTokenBucket) -> String {
        MonthlyBarChartStyle.monthAxisLabel(for: bucket.monthKey, language: language)
            .replacingOccurrences(of: "\n", with: " ")
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
