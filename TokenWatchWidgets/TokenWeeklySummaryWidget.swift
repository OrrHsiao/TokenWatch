import Charts
import SwiftUI
import WidgetKit

struct TokenWeeklySummaryWidgetView: View {
    let entry: WidgetUsageEntry

    var body: some View {
        let presentation = WidgetChartPresentationBuilder.weeklySummary(for: entry.state)

        VStack(spacing: 7) {
            WidgetChartHeader(
                title: presentation.title,
                subtitle: presentation.subtitle,
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

    private func chart(_ presentation: WidgetWeeklySummaryPresentation) -> some View {
        Chart(presentation.points) { point in
            BarMark(
                x: .value("Day", point.position),
                y: .value("Tokens", point.totalTokens)
            )
            .foregroundStyle(
                point.isCurrentDay
                    ? Color.accentColor
                    : Color.accentColor.opacity(0.45)
            )
            .clipShape(RoundedRectangle(cornerRadius: 2))
        }
        .chartLegend(.hidden)
        .chartXScale(domain: -0.5...6.5)
        .chartYScale(domain: 0...presentation.maximumY)
        .chartXAxis(.hidden)
        .chartYAxis(.hidden)
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
        .configurationDisplayName("Last 7 Days")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}
