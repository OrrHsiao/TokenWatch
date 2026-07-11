import AppKit
import Charts
import SwiftUI

final class DashboardBarRowView: NSView {
    private let fraction: CGFloat
    private let color: NSColor

    init(title: String, value: String, fraction: CGFloat, color: NSColor) {
        self.fraction = fraction
        self.color = color
        super.init(frame: .zero)
        setup(title: title, value: value)
    }

    required init?(coder: NSCoder) {
        fatalError("DashboardBarRowView 必须用 init(title:value:fraction:color:) 构造")
    }

    private func setup(title: String, value: String) {
        let bar = DashboardRoundedView(
            backgroundColor: color.withAlphaComponent(0.55),
            cornerRadius: 4
        )
        let titleLabel = NSTextField(labelWithString: title)
        titleLabel.font = .systemFont(ofSize: 12, weight: .medium)
        titleLabel.textColor = DashboardPalette.primaryText
        titleLabel.lineBreakMode = .byTruncatingMiddle

        let valueLabel = NSTextField(labelWithString: value)
        valueLabel.font = .monospacedDigitSystemFont(ofSize: 11, weight: .regular)
        valueLabel.textColor = DashboardPalette.secondaryText
        valueLabel.alignment = .right

        addSubview(bar)
        addSubview(titleLabel)
        addSubview(valueLabel)
        bar.translatesAutoresizingMaskIntoConstraints = false
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        valueLabel.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            heightAnchor.constraint(equalToConstant: 28),
            bar.leadingAnchor.constraint(equalTo: leadingAnchor),
            bar.topAnchor.constraint(equalTo: topAnchor),
            bar.bottomAnchor.constraint(equalTo: bottomAnchor),
            bar.widthAnchor.constraint(equalTo: widthAnchor, multiplier: fraction),
            titleLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12),
            titleLabel.centerYAnchor.constraint(equalTo: centerYAnchor),
            titleLabel.trailingAnchor.constraint(lessThanOrEqualTo: valueLabel.leadingAnchor, constant: -12),
            valueLabel.trailingAnchor.constraint(equalTo: trailingAnchor),
            valueLabel.centerYAnchor.constraint(equalTo: centerYAnchor),
            valueLabel.widthAnchor.constraint(greaterThanOrEqualToConstant: 76),
        ])
    }
}

private enum DashboardTrendRendering {
    static let tokenSeriesName = "Token"
    static let costSeriesName = "Cost"
    static let seriesKeys = [tokenSeriesName, costSeriesName]
    static var tokenLegendTitle: String {
        tokenLegendTitle(language: .zhHans)
    }
    static var costLegendTitle: String {
        costLegendTitle(language: .zhHans)
    }
    static var trendLegendTitles: [String] {
        trendLegendTitles(language: .zhHans)
    }
    static let trendLegendPlacementName = "subtitleHeaderTrailing"
    static let chartLegendVisibilityName = "hidden"
    static let areaStacking: MarkStackingMethod = .unstacked
    static let areaStackingModeName = "unstacked"
    static let areaLayerOrder = seriesKeys
    static let costLineDashPattern: [CGFloat] = []
    static let costYAxisPositionName = "trailing"
    private static let costScalePaddingMultiplier = 1.20

    static func tokenLegendTitle(language: AppLanguage) -> String {
        AppStrings.text(.dashboardTrendTokenLegend, language: language)
    }

    static func costLegendTitle(language: AppLanguage) -> String {
        AppStrings.text(.chartCost, language: language)
    }

    static func trendLegendTitles(language: AppLanguage) -> [String] {
        [tokenLegendTitle(language: language), costLegendTitle(language: language)]
    }

    static func costAxisLabel(forScaledValue value: Double, maxTokens: Double, maxCost: Double) -> String {
        guard value.isFinite, maxTokens > 0, maxCost > 0 else {
            return MonthlyBarChartStyle.costAxisLabel(for: 0)
        }

        let normalizedValue = clampedUnit(value / costPlotMaximum(maxTokens: maxTokens))
        return MonthlyBarChartStyle.costAxisLabel(for: normalizedValue * maxCost)
    }

    static func tokenAxisValues(maxTokens: Double) -> [Double] {
        [0, maxTokens * 0.5, maxTokens]
    }

    static func costAxisValues(maxTokens: Double) -> [Double] {
        let maximum = costPlotMaximum(maxTokens: maxTokens)
        return [0, maximum * 0.5, maximum]
    }

    static func costPlotY(forNormalizedCostHeight value: Double, maxTokens: Double) -> Double {
        clampedUnit(value) * costPlotMaximum(maxTokens: maxTokens)
    }

    static func chartYScaleUpperBound(maxTokens: Double) -> Double {
        costPlotMaximum(maxTokens: maxTokens)
    }

    private static func costPlotMaximum(maxTokens: Double) -> Double {
        guard maxTokens.isFinite, maxTokens > 0 else {
            return costScalePaddingMultiplier
        }
        return maxTokens * costScalePaddingMultiplier
    }

    private static func clampedUnit(_ value: Double) -> Double {
        guard value.isFinite else { return 0 }
        return min(max(value, 0), 1)
    }
}

struct DashboardTrendBucket: Sendable, Equatable, Identifiable {
    let id: String
    let key: String
    let label: String
    let totalTokens: Int
    let totalCost: Double
    let normalizedHeight: Double
    let normalizedCostHeight: Double
    let isCurrent: Bool
}

final class DashboardTrendView: NSView {
    private static let hoverLabelToChartSpacing: CGFloat = 1

    private let chartHost = NSHostingView(rootView: AnyView(DashboardTrendChartContent(
        buckets: [],
        language: .zhHans,
        axisKeys: [],
        onHoverBucketKeyChange: { _ in }
    )))
    private let hoverLabel = NSTextField(labelWithString: "")
    private var buckets: [DashboardTrendBucket] = []
    private var language: AppLanguage = .zhHans

    var debugBucketKeys: [String] {
        buckets.map(\.key)
    }

    var debugHoverText: String {
        hoverLabel.stringValue
    }

    var debugLineInterpolationMethodName: String {
        TodayHourlyLineChartRendering.interpolationMethodName
    }

    var debugAreaGradientScaleModeName: String {
        TodayHourlyLineChartRendering.areaGradientScaleModeName
    }

    var debugAreaStackingModeName: String {
        DashboardTrendRendering.areaStackingModeName
    }

    var debugAreaLayerOrder: [String] {
        DashboardTrendRendering.areaLayerOrder
    }

    var debugTrendSeriesKeys: [String] {
        DashboardTrendRendering.seriesKeys
    }

    var debugChartLegendVisibilityName: String {
        DashboardTrendRendering.chartLegendVisibilityName
    }

    var debugTrendLegendPlacementName: String {
        DashboardTrendRendering.trendLegendPlacementName
    }

    var debugTrendLegendTitles: [String] {
        DashboardTrendRendering.trendLegendTitles(language: language)
    }

    var debugCostLineDashPattern: [CGFloat] {
        DashboardTrendRendering.costLineDashPattern
    }

    var debugCostYAxisPositionName: String {
        DashboardTrendRendering.costYAxisPositionName
    }

    func debugCostYAxisLabel(forScaledValue value: Double, maxTokens: Double, maxCost: Double) -> String {
        DashboardTrendRendering.costAxisLabel(
            forScaledValue: value,
            maxTokens: maxTokens,
            maxCost: maxCost
        )
    }

    func debugCostPlotY(forNormalizedCostHeight value: Double, maxTokens: Double) -> Double {
        DashboardTrendRendering.costPlotY(
            forNormalizedCostHeight: value,
            maxTokens: maxTokens
        )
    }

    func debugChartYScaleUpperBound(maxTokens: Double) -> Double {
        DashboardTrendRendering.chartYScaleUpperBound(maxTokens: maxTokens)
    }

    var debugTokenAreaGradientLightRGBAComponents: [CGFloat]? {
        Self.roundedRGBAComponents(for: DashboardPalette.accent, appearanceName: .aqua)
    }

    var debugCostAreaGradientLightRGBAComponents: [CGFloat]? {
        Self.roundedRGBAComponents(for: DashboardPalette.costLine, appearanceName: .aqua)
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setupView()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupView()
    }

    /// 用所选 Dashboard 范围的趋势桶替换折线图内容。
    func configure(buckets: [DashboardTrendBucket], language: AppLanguage = .zhHans) {
        self.buckets = buckets
        self.language = language
        hoverLabel.stringValue = ""
        chartHost.rootView = AnyView(DashboardTrendChartContent(
            buckets: buckets,
            language: language,
            axisKeys: Self.axisKeys(for: buckets),
            onHoverBucketKeyChange: { [weak self] key in
                self?.updateHoverText(bucketKey: key)
            }
        ))
    }

    func debugSimulateHover(bucketKey: String?) {
        updateHoverText(bucketKey: bucketKey)
    }

    private func setupView() {
        wantsLayer = true
        layer?.backgroundColor = NSColor.clear.cgColor

        chartHost.translatesAutoresizingMaskIntoConstraints = false
        addSubview(chartHost)

        hoverLabel.font = .systemFont(ofSize: 10, weight: .medium)
        hoverLabel.textColor = DashboardPalette.secondaryText
        hoverLabel.alignment = .right
        hoverLabel.lineBreakMode = .byTruncatingMiddle
        hoverLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        hoverLabel.translatesAutoresizingMaskIntoConstraints = false
        addSubview(hoverLabel)

        NSLayoutConstraint.activate([
            chartHost.leadingAnchor.constraint(equalTo: leadingAnchor),
            chartHost.trailingAnchor.constraint(equalTo: trailingAnchor),
            chartHost.topAnchor.constraint(equalTo: hoverLabel.bottomAnchor, constant: Self.hoverLabelToChartSpacing),
            chartHost.bottomAnchor.constraint(equalTo: bottomAnchor),
            hoverLabel.topAnchor.constraint(equalTo: topAnchor),
            hoverLabel.trailingAnchor.constraint(equalTo: trailingAnchor),
            hoverLabel.leadingAnchor.constraint(greaterThanOrEqualTo: leadingAnchor),
            heightAnchor.constraint(greaterThanOrEqualToConstant: 176),
        ])
    }

    private func updateHoverText(bucketKey: String?) {
        guard let bucketKey,
              let bucket = buckets.first(where: { $0.key == bucketKey }) else {
            hoverLabel.stringValue = ""
            return
        }
        let costTitle = AppStrings.text(.chartCost, language: language)
        hoverLabel.stringValue = "\(bucket.label) · \(CompactNumberFormatter.formatHoverTokens(bucket.totalTokens)) · \(costTitle) \(Self.costText(bucket.totalCost))"
    }

    private static func axisKeys(for buckets: [DashboardTrendBucket]) -> [String] {
        guard !buckets.isEmpty else { return [] }
        let preferredIndexes: [Int]
        switch buckets.count {
        case 1...6:
            preferredIndexes = Array(buckets.indices)
        case 7:
            preferredIndexes = [0, 3, 6]
        case 24:
            preferredIndexes = [0, 6, 12, 18, 23]
        case 30:
            preferredIndexes = [0, 6, 13, 20, 29]
        default:
            let lastIndex = buckets.count - 1
            let step = max(1, lastIndex / 5)
            preferredIndexes = stride(from: 0, through: lastIndex, by: step).map { $0 }
        }
        return preferredIndexes
            .filter { buckets.indices.contains($0) }
            .map { buckets[$0].key }
    }

    private static func costText(_ value: Double) -> String {
        guard value.isFinite else { return "$0.00" }
        return String(format: "$%.2f", max(0, value))
    }

    private static func roundedRGBAComponents(for color: NSColor, appearanceName: NSAppearance.Name) -> [CGFloat]? {
        guard let appearance = NSAppearance(named: appearanceName) else {
            return nil
        }

        var components: [CGFloat]?
        appearance.performAsCurrentDrawingAppearance {
            components = color.cgColor.components
        }
        return components?.map { ($0 * 1_000).rounded() / 1_000 }
    }
}

private struct DashboardTrendChartContent: View {
    let buckets: [DashboardTrendBucket]
    let language: AppLanguage
    let axisKeys: [String]
    let onHoverBucketKeyChange: (String?) -> Void

    private var maxTokens: Double {
        max(1, Double(buckets.map(\.totalTokens).max() ?? 0))
    }

    private var maxCost: Double {
        max(0, buckets.map(\.totalCost).max() ?? 0)
    }

    var body: some View {
        Chart {
            ForEach(buckets) { bucket in
                AreaMark(
                    x: .value(axisValueName, bucket.key),
                    y: .value("Tokens", Double(bucket.totalTokens)),
                    series: .value("Series", DashboardTrendRendering.tokenSeriesName),
                    stacking: DashboardTrendRendering.areaStacking
                )
                .interpolationMethod(TodayHourlyLineChartRendering.interpolationMethod)
                .foregroundStyle(tokenAreaGradient)

                AreaMark(
                    x: .value(axisValueName, bucket.key),
                    y: .value(
                        "Cost",
                        DashboardTrendRendering.costPlotY(
                            forNormalizedCostHeight: bucket.normalizedCostHeight,
                            maxTokens: maxTokens
                        )
                    ),
                    series: .value("Series", DashboardTrendRendering.costSeriesName),
                    stacking: DashboardTrendRendering.areaStacking
                )
                .interpolationMethod(TodayHourlyLineChartRendering.interpolationMethod)
                .foregroundStyle(costAreaGradient)
            }

            ForEach(buckets) { bucket in
                LineMark(
                    x: .value(axisValueName, bucket.key),
                    y: .value("Tokens", Double(bucket.totalTokens)),
                    series: .value("Series", DashboardTrendRendering.tokenSeriesName)
                )
                .interpolationMethod(TodayHourlyLineChartRendering.interpolationMethod)
                .foregroundStyle(by: .value("Legend", DashboardTrendRendering.tokenLegendTitle(language: language)))
                .lineStyle(StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))

                LineMark(
                    x: .value(axisValueName, bucket.key),
                    y: .value(
                        "Cost",
                        DashboardTrendRendering.costPlotY(
                            forNormalizedCostHeight: bucket.normalizedCostHeight,
                            maxTokens: maxTokens
                        )
                    ),
                    series: .value("Series", DashboardTrendRendering.costSeriesName)
                )
                .interpolationMethod(TodayHourlyLineChartRendering.interpolationMethod)
                .foregroundStyle(by: .value("Legend", DashboardTrendRendering.costLegendTitle(language: language)))
                .lineStyle(StrokeStyle(lineWidth: 1.8, lineCap: .round, lineJoin: .round))

                if bucket.isCurrent {
                    PointMark(
                        x: .value(axisValueName, bucket.key),
                        y: .value("Tokens", Double(bucket.totalTokens))
                    )
                    .foregroundStyle(Color(nsColor: DashboardPalette.accent))
                    .symbolSize(22)

                    PointMark(
                        x: .value(axisValueName, bucket.key),
                        y: .value(
                            "Cost",
                            DashboardTrendRendering.costPlotY(
                                forNormalizedCostHeight: bucket.normalizedCostHeight,
                                maxTokens: maxTokens
                            )
                        )
                    )
                    .foregroundStyle(Color(nsColor: DashboardPalette.costLine))
                    .symbolSize(18)
                }
            }
        }
        .chartForegroundStyleScale([
            DashboardTrendRendering.tokenLegendTitle(language: language): Color(nsColor: DashboardPalette.accent),
            DashboardTrendRendering.costLegendTitle(language: language): Color(nsColor: DashboardPalette.costLine),
        ])
        .chartLegend(.hidden)
        .chartYScale(domain: 0...DashboardTrendRendering.chartYScaleUpperBound(maxTokens: maxTokens))
        .chartXAxis {
            AxisMarks(values: axisKeys) { value in
                AxisTick()
                AxisValueLabel {
                    if let key = value.as(String.self) {
                        Text(MonthlyBarChartStyle.monthAxisLabel(for: key, language: language))
                            .font(.system(size: 8))
                    }
                }
            }
        }
        .chartYAxis {
            AxisMarks(position: .leading, values: DashboardTrendRendering.tokenAxisValues(maxTokens: maxTokens)) { value in
                AxisGridLine()
                    .foregroundStyle(.secondary.opacity(0.16))
                AxisTick()
                if let tokens = value.as(Double.self) {
                    AxisValueLabel(MonthlyBarChartStyle.tokenAxisLabel(for: tokens))
                        .font(.system(size: 8))
                }
            }
            AxisMarks(position: .trailing, values: DashboardTrendRendering.costAxisValues(maxTokens: maxTokens)) { value in
                AxisTick()
                    .foregroundStyle(Color(nsColor: DashboardPalette.costLine).opacity(0.65))
                if let scaledValue = value.as(Double.self) {
                    AxisValueLabel(
                        DashboardTrendRendering.costAxisLabel(
                            forScaledValue: scaledValue,
                            maxTokens: maxTokens,
                            maxCost: maxCost
                        )
                    )
                    .font(.system(size: 8))
                    .foregroundStyle(Color(nsColor: DashboardPalette.costLine))
                }
            }
        }
        .chartOverlay { proxy in
            hoverOverlay(proxy: proxy)
        }
        .padding(.top, 4)
    }

    private var axisValueName: String {
        language.periodAxisValueName
    }

    private var tokenAreaGradient: LinearGradient {
        let color = Color(nsColor: DashboardPalette.accent)
        return LinearGradient(
            colors: [
                color.opacity(TodayHourlyLineChartRendering.areaGradientPeakOpacity),
                color.opacity(TodayHourlyLineChartRendering.areaGradientBaselineOpacity),
            ],
            startPoint: .top,
            endPoint: .bottom
        )
    }

    private var costAreaGradient: LinearGradient {
        let color = Color(nsColor: DashboardPalette.costLine)
        return LinearGradient(
            colors: [
                color.opacity(TodayHourlyLineChartRendering.areaGradientPeakOpacity),
                color.opacity(TodayHourlyLineChartRendering.areaGradientBaselineOpacity),
            ],
            startPoint: .top,
            endPoint: .bottom
        )
    }

    private func hoverOverlay(proxy: ChartProxy) -> some View {
        GeometryReader { geometry in
            Rectangle()
                .fill(.clear)
                .contentShape(Rectangle())
                .onContinuousHover { phase in
                    guard let plotFrame = proxy.plotFrame else {
                        onHoverBucketKeyChange(nil)
                        return
                    }
                    let frame = geometry[plotFrame]
                    switch phase {
                    case .active(let location):
                        guard frame.contains(location) else {
                            onHoverBucketKeyChange(nil)
                            return
                        }
                        onHoverBucketKeyChange(proxy.value(atX: location.x - frame.origin.x, as: String.self))
                    case .ended:
                        onHoverBucketKeyChange(nil)
                    }
                }
        }
    }
}

final class DashboardDonutView: NSView {
    private var slices: [UsageShareSlice] = []

    func configure(slices: [UsageShareSlice]) {
        self.slices = slices.filter { $0.totalTokens > 0 }
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        let rect = bounds.insetBy(dx: 10, dy: 10)
        // 绘图比例使用 Double 汇总，避免多个 Int.max 被展示层饱和后各自画成整圆。
        let total = slices.reduce(0.0) { $0 + Double($1.totalTokens) }
        guard total > 0 else {
            DashboardPalette.subtleBorder.setStroke()
            NSBezierPath(ovalIn: rect).stroke()
            return
        }

        var startAngle: CGFloat = 90
        for (index, slice) in slices.enumerated() {
            let sweep = CGFloat(Double(slice.totalTokens) / total) * 360
            let path = NSBezierPath()
            let center = NSPoint(x: rect.midX, y: rect.midY)
            path.move(to: center)
            path.appendArc(
                withCenter: center,
                radius: min(rect.width, rect.height) / 2,
                startAngle: startAngle,
                endAngle: startAngle - sweep,
                clockwise: true
            )
            path.close()
            DashboardColors.modelColor(at: index).setFill()
            path.fill()
            startAngle -= sweep
        }

        DashboardPalette.panelBackground.setFill()
        NSBezierPath(ovalIn: rect.insetBy(dx: rect.width * 0.27, dy: rect.height * 0.27)).fill()
    }
}
