import Charts
import SwiftUI
import WidgetKit

struct TokenTodayAnomalyWidgetView: View {
    let entry: WidgetUsageEntry
    @Environment(\.widgetFamily) private var family

    var body: some View {
        let presentation = WidgetChartPresentationBuilder.todayAnomaly(for: entry.state)

        VStack(alignment: .leading, spacing: 8) {
            WidgetChartHeader(
                title: presentation.title,
                subtitle: presentation.subtitle,
                total: presentation.totalText
            )
            if let message = presentation.message {
                Spacer(minLength: 0)
                Text(message)
                    .font(.caption2)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)
                    .padding(6)
                    .background(
                        .regularMaterial,
                        in: RoundedRectangle(cornerRadius: 6)
                    )
                Spacer(minLength: 0)
            } else {
                status(presentation)
                if family == .systemMedium {
                    chart(presentation)
                } else {
                    Spacer(minLength: 0)
                }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(presentation.accessibilityLabel)
    }

    private func status(
        _ presentation: WidgetTodayAnomalyPresentation
    ) -> some View {
        HStack(spacing: 6) {
            Image(systemName: statusSymbol(for: presentation))
                .foregroundStyle(statusColor(for: presentation))
            if let multiplier = presentation.multiplierText {
                Text(multiplier)
                    .font(.title3)
                    .fontWeight(.semibold)
                    .monospacedDigit()
            } else {
                Text("—")
                    .font(.title3)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 2)
            if let baseline = presentation.baselineText {
                Text(baseline)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
                    .lineLimit(1)
            }
        }
    }

    private func chart(
        _ presentation: WidgetTodayAnomalyPresentation
    ) -> some View {
        Chart(presentation.points) { point in
            BarMark(
                x: .value("Day", point.position),
                y: .value("Tokens", point.totalTokens)
            )
            .foregroundStyle(color(for: point, presentation: presentation))
            .clipShape(RoundedRectangle(cornerRadius: 2))
        }
        .chartLegend(.hidden)
        .chartXScale(domain: -0.5...7.5)
        .chartYScale(domain: 0...presentation.maximumY)
        .chartXAxis(.hidden)
        .chartYAxis(.hidden)
    }

    private func statusSymbol(
        for presentation: WidgetTodayAnomalyPresentation
    ) -> String {
        if presentation.isElevated {
            return "exclamationmark.triangle.fill"
        }
        return presentation.hasComparableBaseline
            ? "checkmark.circle.fill"
            : "circle.dashed"
    }

    private func statusColor(
        for presentation: WidgetTodayAnomalyPresentation
    ) -> Color {
        presentation.isElevated ? .red : .accentColor
    }

    private func color(
        for point: WidgetTodayAnomalyPoint,
        presentation: WidgetTodayAnomalyPresentation
    ) -> Color {
        guard point.isToday else { return Color.accentColor.opacity(0.38) }
        return presentation.isElevated ? .red : .accentColor
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
