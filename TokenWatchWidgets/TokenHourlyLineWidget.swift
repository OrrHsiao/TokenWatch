import Charts
import SwiftUI
import WidgetKit

struct TokenHourlyLineWidgetView: View {
    let entry: WidgetUsageEntry
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let presentation = WidgetChartPresentationBuilder.hourlyLine(for: entry.state)

        VStack(spacing: 6) {
            WidgetChartHeader(
                title: presentation.title,
                subtitle: nil,
                total: presentation.totalText
            )
            if presentation.message == nil {
                WidgetMetricStrip(items: metricItems(presentation))
            }
            ZStack {
                chart(presentation)
                    .opacity(presentation.message == nil ? 1 : 0.35)
                if let message = presentation.message {
                    Text(message)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(presentation.accessibilityLabel)
    }

    private func metricItems(
        _ presentation: WidgetHourlyLinePresentation
    ) -> [WidgetMetricItem] {
        var items: [WidgetMetricItem] = []
        if let currentHourText = presentation.currentHourText {
            items.append(WidgetMetricItem(
                symbolName: "clock",
                text: currentHourText
            ))
        }
        if let peakHourText = presentation.peakHourText {
            items.append(WidgetMetricItem(
                symbolName: "arrow.up.to.line",
                text: peakHourText
            ))
        }
        return items
    }

    private func chart(_ presentation: WidgetHourlyLinePresentation) -> some View {
        Chart {
            ForEach(presentation.points) { point in
                AreaMark(
                    x: .value(hourAxisValueName, point.hour),
                    y: .value(tokenAxisValueName, point.totalTokens)
                )
                .interpolationMethod(lineInterpolationMethod)
                .foregroundStyle(areaGradient)
            }
            ForEach(presentation.points) { point in
                LineMark(
                    x: .value(hourAxisValueName, point.hour),
                    y: .value(tokenAxisValueName, point.totalTokens)
                )
                .interpolationMethod(lineInterpolationMethod)
                .foregroundStyle(Color.accentColor)
                .lineStyle(StrokeStyle(
                    lineWidth: CGFloat(WidgetChartVisualStyle.lineWidth),
                    lineCap: .round,
                    lineJoin: .round
                ))
            }
            if let point = presentation.currentPoint {
                PointMark(
                    x: .value(hourAxisValueName, point.hour),
                    y: .value(tokenAxisValueName, point.totalTokens)
                )
                .foregroundStyle(Color.accentColor)
                .symbolSize(CGFloat(WidgetChartVisualStyle.currentPointSize))
            }
        }
        .chartLegend(.hidden)
        .chartXScale(domain: 0...23)
        .chartYScale(domain: 0...presentation.maximumY)
        .chartXAxis {
            AxisMarks(values: WidgetChartVisualStyle.hourAxisValues) { value in
                AxisTick()
                AxisValueLabel {
                    if let hour = value.as(Int.self) {
                        Text(verbatim: "\(hour)").font(.system(size: 8))
                    }
                }
            }
        }
        .chartYAxis {
            AxisMarks(position: .leading, values: .automatic(desiredCount: 3)) { value in
                AxisGridLine()
                    .foregroundStyle(.secondary.opacity(WidgetChartVisualStyle.gridOpacity))
                AxisTick()
                AxisValueLabel {
                    if let tokens = value.as(Double.self) {
                        Text(WidgetChartNumberFormatter.axis(tokens))
                            .font(.system(size: 8))
                    }
                }
            }
        }
        .padding(.top, 4)
    }

    private var lineInterpolationMethod: InterpolationMethod {
        switch WidgetChartRendering.lineInterpolationStyle {
        case .catmullRom:
            return .catmullRom
        }
    }

    private var hourAxisValueName: String {
        String(localized: "widget.hourly.name")
    }

    private var tokenAxisValueName: String {
        String(localized: "widget.today.title")
    }

    private var areaGradient: LinearGradient {
        let rgba = WidgetChartVisualStyle.heatmapRGBA(
            intensity: WidgetChartVisualStyle.heatmapMaximumIntensity,
            isDark: colorScheme == .dark
        )
        let green = Color(
            .sRGB,
            red: rgba.red,
            green: rgba.green,
            blue: rgba.blue,
            opacity: rgba.alpha
        )
        return LinearGradient(
            colors: [
                green.opacity(WidgetChartVisualStyle.areaPeakOpacity),
                green.opacity(WidgetChartVisualStyle.areaBaselineOpacity),
            ],
            startPoint: .top,
            endPoint: .bottom
        )
    }
}

struct TokenHourlyLineWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(
            kind: WidgetSharedConfiguration.hourlyLineKind,
            provider: WidgetTimelineProvider()
        ) { entry in
            TokenHourlyLineWidgetView(entry: entry)
                .containerBackground(.background, for: .widget)
        }
        .configurationDisplayName(LocalizedStringKey("widget.hourly.name"))
        .description(LocalizedStringKey("widget.hourly.description"))
        .supportedFamilies([.systemMedium])
    }
}
