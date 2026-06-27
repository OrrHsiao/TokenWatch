import Charts
import SwiftUI
import WidgetKit

struct TokenWatchTodayLineWidget: Widget {
    private let kind = "TokenWatchTodayLineWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: TokenWatchWidgetTimelineProvider()) { entry in
            TokenWatchTodayLineWidgetView(snapshot: entry.snapshot)
                .containerBackground(.background, for: .widget)
        }
        .configurationDisplayName(TokenWatchWidgetCopy.text(.todayLineDisplayName, languageIdentifier: "zh-Hans"))
        .description(TokenWatchWidgetCopy.text(.todayLineDescription, languageIdentifier: "zh-Hans"))
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
        .contentMarginsDisabled()
    }
}

struct TokenWatchTodayLineWidgetView: View {
    let snapshot: TokenWatchWidgetSnapshot

    @Environment(\.widgetFamily) private var widgetFamily
    @Environment(\.colorScheme) private var colorScheme

    private var layout: TokenWatchTodayLineWidgetLayout {
        TokenWatchTodayLineWidgetLayout.layout(for: widgetFamily.tokenWatchDisplayFamily)
    }

    var body: some View {
        Group {
            switch snapshot.status {
            case .ready:
                content
            case .needsAuthorization:
                statusView(.openAppToAuthorize)
            case .empty:
                statusView(.noTokenData)
            }
        }
        .padding(widgetPadding)
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: verticalSpacing) {
            header
            chart
            if layout == .expanded {
                footer
            }
        }
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 2) {
                Text(TokenWatchWidgetCopy.text(.today, languageIdentifier: snapshot.languageIdentifier))
                    .font(.system(size: layout == .expanded ? 12 : 11, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Text(TokenWatchWidgetCompactNumberFormatter.format(snapshot.todayLine.totalTokens))
                    .font(.system(size: layout == .expanded ? 24 : 22, weight: .bold))
                    .monospacedDigit()
                    .lineLimit(1)
            }
            Spacer(minLength: 4)
            if layout != .compact {
                Text(updatedText)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
    }

    private var chart: some View {
        Chart {
            ForEach(snapshot.todayLine.buckets) { bucket in
                AreaMark(
                    x: .value("Hour", bucket.hourKey),
                    y: .value("Tokens", Double(bucket.totalTokens))
                )
                .interpolationMethod(.catmullRom)
                .foregroundStyle(areaGradient)

                LineMark(
                    x: .value("Hour", bucket.hourKey),
                    y: .value("Tokens", Double(bucket.totalTokens))
                )
                .interpolationMethod(.catmullRom)
                .foregroundStyle(Color.accentColor)
                .lineStyle(StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))

                if bucket.isCurrentHour {
                    PointMark(
                        x: .value("Hour", bucket.hourKey),
                        y: .value("Tokens", Double(bucket.totalTokens))
                    )
                    .foregroundStyle(Color.accentColor)
                    .symbolSize(layout == .compact ? 14 : 22)
                }
            }
        }
        .chartLegend(.hidden)
        .chartYScale(domain: 0...Double(max(1, snapshot.todayLine.maxHourlyTokens)))
        .chartXAxis {
            AxisMarks(values: axisKeys) { value in
                if layout != .compact {
                    AxisTick()
                    AxisValueLabel {
                        if let key = value.as(String.self),
                           let bucket = snapshot.todayLine.buckets.first(where: { $0.hourKey == key }) {
                            Text(bucket.hourLabel)
                                .font(.system(size: 8))
                        }
                    }
                }
            }
        }
        .chartYAxis {
            AxisMarks(position: .leading, values: .automatic(desiredCount: layout == .expanded ? 3 : 2)) { value in
                if layout != .compact {
                    AxisGridLine()
                        .foregroundStyle(.secondary.opacity(0.16))
                    if let tokens = value.as(Double.self), layout == .expanded {
                        AxisValueLabel(TokenWatchWidgetCompactNumberFormatter.format(Int(tokens)))
                            .font(.system(size: 8))
                    }
                }
            }
        }
        .frame(height: chartHeight)
        .accessibilityLabel(TokenWatchWidgetCopy.text(.todayLineDisplayName, languageIdentifier: snapshot.languageIdentifier))
    }

    private var footer: some View {
        HStack {
            Text("\(TokenWatchWidgetCopy.text(.peakHour, languageIdentifier: snapshot.languageIdentifier)) \(TokenWatchWidgetCompactNumberFormatter.format(snapshot.todayLine.maxHourlyTokens))")
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.secondary)
            Spacer()
        }
    }

    private func statusView(_ key: TokenWatchWidgetCopyKey) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(TokenWatchWidgetCopy.text(.todayLineDisplayName, languageIdentifier: snapshot.languageIdentifier))
                .font(.system(size: 13, weight: .semibold))
            Text(TokenWatchWidgetCopy.text(key, languageIdentifier: snapshot.languageIdentifier))
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.secondary)
            Spacer(minLength: 0)
            chart
                .opacity(0.35)
        }
    }

    private var axisKeys: [String] {
        [0, 6, 12, 18, 23].compactMap { index in
            snapshot.todayLine.buckets.indices.contains(index)
                ? snapshot.todayLine.buckets[index].hourKey
                : nil
        }
    }

    private var areaGradient: LinearGradient {
        let color = heatmapMaxColor
        return LinearGradient(
            colors: [
                color.opacity(0.8),
                color.opacity(0.05),
            ],
            startPoint: .top,
            endPoint: .bottom
        )
    }

    private var heatmapMaxColor: Color {
        if colorScheme == .dark {
            return Color(red: 57 / 255, green: 211 / 255, blue: 83 / 255)
        }
        return Color(red: 33 / 255, green: 110 / 255, blue: 57 / 255)
    }

    private var updatedText: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        return "\(TokenWatchWidgetCopy.text(.updated, languageIdentifier: snapshot.languageIdentifier)) \(formatter.string(from: snapshot.generatedAt))"
    }

    private var widgetPadding: CGFloat {
        switch layout {
        case .compact:
            return 12
        case .chart:
            return 12
        case .expanded:
            return 16
        }
    }

    private var verticalSpacing: CGFloat {
        switch layout {
        case .compact:
            return 8
        case .chart:
            return 8
        case .expanded:
            return 12
        }
    }

    private var chartHeight: CGFloat {
        switch layout {
        case .compact:
            return 58
        case .chart:
            return 72
        case .expanded:
            return 150
        }
    }
}
