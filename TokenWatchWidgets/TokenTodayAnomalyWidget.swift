import Charts
import SwiftUI
import WidgetKit

struct TokenTodayAnomalyWidgetView: View {
    let entry: WidgetUsageEntry
    @Environment(\.widgetFamily) private var family
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let presentation = WidgetChartPresentationBuilder.todayAnomaly(for: entry.state)

        VStack(alignment: .leading, spacing: 8) {
            if let message = presentation.message {
                WidgetChartHeader(
                    title: presentation.title,
                    subtitle: presentation.subtitle,
                    total: presentation.totalText
                )
                Spacer(minLength: 0)
                Text(message)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                Spacer(minLength: 0)
            } else if family == .systemMedium {
                mediumContent(presentation)
            } else {
                smallContent(presentation)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(presentation.accessibilityLabel)
    }

    private func smallContent(
        _ presentation: WidgetTodayAnomalyPresentation
    ) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            contextHeader(presentation)
            Text(presentation.totalText)
                .font(.system(.title, design: .rounded, weight: .bold))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.72)
            comparison(presentation)
            Spacer(minLength: 2)
            baseline(presentation)
        }
    }

    private func mediumContent(
        _ presentation: WidgetTodayAnomalyPresentation
    ) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            contextHeader(presentation)

            HStack(alignment: .bottom, spacing: 16) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(presentation.totalText)
                        .font(.system(.title2, design: .rounded, weight: .bold))
                        .monospacedDigit()
                        .lineLimit(1)
                        .minimumScaleFactor(0.72)
                    comparison(presentation)
                    Spacer(minLength: 2)
                    baseline(presentation)
                }
                .frame(minWidth: 104, maxWidth: 120, maxHeight: .infinity, alignment: .leading)

                chart(presentation)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }

    @ViewBuilder
    private func contextHeader(
        _ presentation: WidgetTodayAnomalyPresentation
    ) -> some View {
        if family == .systemSmall {
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(presentation.title)
                        .font(.headline)
                        .fixedSize(horizontal: true, vertical: false)
                    if let subtitle = presentation.subtitle {
                        Text(subtitle)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: true, vertical: false)
                    }
                }
                Text(presentation.title)
                    .font(.headline)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
        } else {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(presentation.title)
                    .font(.headline)
                    .lineLimit(1)
                Spacer(minLength: 4)
                if let subtitle = presentation.subtitle {
                    Text(subtitle)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }
            }
        }
    }

    @ViewBuilder
    private func comparison(
        _ presentation: WidgetTodayAnomalyPresentation
    ) -> some View {
        HStack(spacing: 4) {
            Image(systemName: statusSymbol(for: presentation))
                .font(.caption)
            if let difference = presentation.differenceText {
                Text(difference)
                    .font(.headline)
                    .monospacedDigit()
            } else if let multiplier = presentation.multiplierText {
                Text(multiplier)
                    .font(.headline)
                    .monospacedDigit()
            } else {
                Text(verbatim: "—")
                    .font(.headline)
            }
        }
        .foregroundStyle(statusColor(for: presentation))
        .lineLimit(1)
        .minimumScaleFactor(0.7)
    }

    @ViewBuilder
    private func baseline(
        _ presentation: WidgetTodayAnomalyPresentation
    ) -> some View {
        if let baseline = presentation.baselineText {
            VStack(alignment: .leading, spacing: 1) {
                if let baselineTitle = presentation.baselineTitle {
                    Text(baselineTitle)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Text(baseline)
                    .font(.title3)
                    .fontWeight(.semibold)
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)
            }
        }
    }

    private func chart(
        _ presentation: WidgetTodayAnomalyPresentation
    ) -> some View {
        Chart(presentation.points) { point in
                BarMark(
                    x: .value(
                        String(localized: "widget.weekly.axis.day"),
                        point.position
                    ),
                    y: .value(
                        String(localized: "widget.weekly.axis.tokens"),
                        point.totalTokens
                    ),
                    width: .fixed(13)
                )
                .foregroundStyle(color(for: point, presentation: presentation))
                .clipShape(RoundedRectangle(cornerRadius: 2))
        }
        .chartLegend(.hidden)
        .chartXScale(domain: -0.5...7.5)
        .chartYScale(domain: 0...presentation.maximumY)
        .chartXAxis(.hidden)
        .chartYAxis(.hidden)
        .chartOverlay { chartProxy in
            baselineGuide(
                for: presentation,
                chartProxy: chartProxy
            )
        }
    }

    @ViewBuilder
    private func baselineGuide(
        for presentation: WidgetTodayAnomalyPresentation,
        chartProxy: ChartProxy
    ) -> some View {
        if let baseline = presentation.baselineValue {
            GeometryReader { proxy in
                if let plotFrame = chartProxy.plotFrame,
                   let y = chartProxy.position(forY: baseline) {
                    let frame = proxy[plotFrame]
                    Path { path in
                        path.move(
                            to: CGPoint(x: frame.minX, y: frame.minY + y)
                        )
                        path.addLine(
                            to: CGPoint(x: frame.maxX, y: frame.minY + y)
                        )
                    }
                    .stroke(
                        Color.primary.opacity(0.65),
                        style: StrokeStyle(lineWidth: 1.2, dash: [4, 3])
                    )
                }
            }
            .allowsHitTesting(false)
        }
    }

    private func statusSymbol(
        for presentation: WidgetTodayAnomalyPresentation
    ) -> String {
        if presentation.isElevated {
            return "arrow.up"
        }
        return presentation.hasComparableBaseline
            ? "checkmark"
            : "circle.dashed"
    }

    private func statusColor(
        for presentation: WidgetTodayAnomalyPresentation
    ) -> Color {
        presentation.isElevated ? .red : usageBlue
    }

    private func color(
        for point: WidgetTodayAnomalyPoint,
        presentation: WidgetTodayAnomalyPresentation
    ) -> Color {
        guard point.isToday else {
            return usageBlue.opacity(colorScheme == .dark ? 0.55 : 0.7)
        }
        return presentation.isElevated ? .red : usageBlue
    }

    private var usageBlue: Color {
        colorScheme == .dark
            ? Color(red: 90.0 / 255.0, green: 162.0 / 255.0, blue: 1)
            : Color(red: 37.0 / 255.0, green: 99.0 / 255.0, blue: 235.0 / 255.0)
    }
}

struct TokenTodayAnomalyWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(
            kind: WidgetSharedConfiguration.todayAnomalyKind,
            provider: WidgetTimelineProvider()
        ) { entry in
            TokenTodayAnomalyWidgetView(entry: entry)
                .containerBackground(.background, for: .widget)
        }
        .configurationDisplayName(LocalizedStringKey("widget.today.title"))
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}
