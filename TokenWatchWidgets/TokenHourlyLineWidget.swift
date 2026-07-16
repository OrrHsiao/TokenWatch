import Charts
import SwiftUI
import WidgetKit

struct TokenHourlyLineWidgetView: View {
    let entry: WidgetUsageEntry
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let presentation = WidgetChartPresentationBuilder.hourlyLine(for: entry.state)

        VStack(spacing: 8) {
            WidgetChartHeader(
                title: presentation.title,
                subtitle: nil,
                total: presentation.totalText
            )
            ZStack {
                chart(presentation)
                    .opacity(presentation.message == nil ? 1 : 0.35)
                if let message = presentation.message {
                    Text(message)
                        .font(.caption2)
                        .multilineTextAlignment(.center)
                        .padding(6)
                        .background(
                            .regularMaterial,
                            in: RoundedRectangle(cornerRadius: 6)
                        )
                }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(presentation.accessibilityLabel)
    }

    private func chart(_ presentation: WidgetHourlyLinePresentation) -> some View {
        Chart {
            ForEach(presentation.points) { point in
                AreaMark(
                    x: .value("Hour", point.hour),
                    y: .value("Tokens", point.totalTokens)
                )
                .interpolationMethod(lineInterpolationMethod)
                .foregroundStyle(areaGradient)
            }
            ForEach(presentation.points) { point in
                LineMark(
                    x: .value("Hour", point.hour),
                    y: .value("Tokens", point.totalTokens)
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
                    x: .value("Hour", point.hour),
                    y: .value("Tokens", point.totalTokens)
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
                        Text("\(hour)").font(.system(size: 8))
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
