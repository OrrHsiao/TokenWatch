import Charts
import SwiftUI
import WidgetKit

struct TokenWeeklySummaryWidgetView: View {
    let entry: WidgetUsageEntry
    @Environment(\.widgetFamily) private var family
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let presentation = WidgetChartPresentationBuilder.weeklySummary(for: entry.state)

        VStack(alignment: .leading, spacing: family == .systemSmall ? 8 : 6) {
            header(presentation)
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

    @ViewBuilder
    private func header(_ presentation: WidgetWeeklySummaryPresentation) -> some View {
        if family == .systemSmall {
            VStack(alignment: .leading, spacing: 2) {
                Text(presentation.title)
                    .font(.headline)
                    .lineLimit(1)
                if let subtitle = presentation.subtitle {
                    Text(subtitle)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Text(presentation.totalText)
                    .font(.system(.title, design: .rounded, weight: .bold))
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)
            }
        } else {
            WidgetChartHeader(
                title: presentation.title,
                subtitle: presentation.subtitle,
                total: presentation.totalText
            )
        }
    }

    private func chart(_ presentation: WidgetWeeklySummaryPresentation) -> some View {
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
                width: .fixed(family == .systemSmall ? 9 : 13)
            )
            .foregroundStyle(
                point.isCurrentDay
                    ? usageBlue
                    : usageBlue.opacity(colorScheme == .dark ? 0.58 : 0.72)
            )
            .clipShape(RoundedRectangle(cornerRadius: 2))
        }
        .chartLegend(.hidden)
        .chartXScale(domain: -0.5...6.5)
        .chartYScale(domain: 0...presentation.maximumY)
        .chartXAxis {
            if family == .systemMedium {
                AxisMarks(
                    position: .bottom,
                    values: presentation.points.map(\.position)
                ) { value in
                    AxisValueLabel(verticalSpacing: 3) {
                        if let position = value.as(Int.self),
                           let point = presentation.points.first(where: {
                               $0.position == position
                           }) {
                            Text(point.dayLabel)
                                .font(.caption2)
                                .fontWeight(point.isCurrentDay ? .semibold : .regular)
                                .foregroundStyle(
                                    point.isCurrentDay ? usageBlue : .secondary
                                )
                        }
                    }
                }
            }
        }
        .chartYAxis(.hidden)
    }

    private var usageBlue: Color {
        colorScheme == .dark
            ? Color(red: 90.0 / 255.0, green: 162.0 / 255.0, blue: 1)
            : Color(red: 37.0 / 255.0, green: 99.0 / 255.0, blue: 235.0 / 255.0)
    }
}

struct TokenWeeklySummaryWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(
            kind: WidgetSharedConfiguration.weeklySummaryKind,
            provider: WidgetTimelineProvider()
        ) { entry in
            TokenWeeklySummaryWidgetView(entry: entry)
                .containerBackground(.background, for: .widget)
        }
        .configurationDisplayName(
            String(localized: "widget.weekly.name")
        )
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}
