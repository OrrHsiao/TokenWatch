import SwiftUI
import WidgetKit

struct TokenMonthlyBudgetWidgetView: View {
    let entry: WidgetUsageEntry
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.layoutDirection) private var layoutDirection

    var body: some View {
        let presentation = WidgetChartPresentationBuilder.monthlyBudget(for: entry.state)

        VStack(
            alignment: .leading,
            spacing: presentation.isForecastOverBudget ? 5 : 7
        ) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(presentation.title)
                    .font(.headline)
                    .lineLimit(1)
                Spacer(minLength: 4)
                if let progressText = presentation.progressText {
                    Text(progressText)
                        .font(.title3)
                        .fontWeight(.semibold)
                        .monospacedDigit()
                        .lineLimit(1)
                }
            }

            if let budgetText = presentation.budgetText,
               let progress = presentation.progress {
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text(presentation.spentText)
                        .font(.system(
                            presentation.isForecastOverBudget ? .title2 : .title,
                            design: .rounded,
                            weight: .bold
                        ))
                        .monospacedDigit()
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                    Text(verbatim: "/ \(budgetText)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                        .lineLimit(1)
                    Spacer(minLength: 6)
                    if let forecastText = presentation.forecastText {
                        Text(forecastText)
                            .font(.caption2)
                            .fontWeight(.semibold)
                            .foregroundStyle(forecastColor)
                            .lineLimit(2)
                            .multilineTextAlignment(.trailing)
                            .frame(maxWidth: 112, alignment: .trailing)
                    }
                }

                progressBar(
                    progress: progress,
                    forecastProgress: presentation.forecastProgress,
                    isCompact: presentation.isForecastOverBudget
                )

                if let subtitle = presentation.subtitle {
                    Text(subtitle)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            } else {
                Text(presentation.spentText)
                    .font(.system(.title, design: .rounded, weight: .bold))
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }

            if let message = presentation.message {
                if presentation.budgetText == nil,
                   let subtitle = presentation.subtitle {
                    Text(subtitle)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Text(message)
                    .font(.caption2)
                    .foregroundStyle(
                        presentation.isForecastOverBudget ? .red : .secondary
                    )
                    .lineLimit(presentation.budgetText == nil ? 2 : 1)
            }

            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(presentation.accessibilityLabel)
    }

    private func progressBar(
        progress: Double,
        forecastProgress: Double?,
        isCompact: Bool
    ) -> some View {
        GeometryReader { proxy in
            let width = proxy.size.width * min(max(progress, 0), 1)
            let markerProgress = forecastProgress.map { min(max($0, 0), 1) }
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(.primary.opacity(0.1))
                    .frame(height: 8)
                Capsule()
                    .fill(actualColor)
                    .frame(width: width, height: 8)

                if let markerProgress {
                    // Keep the forecast marker visible at both ends of the budget track.
                    let leadingMarkerX = min(
                        max(proxy.size.width * markerProgress, 1),
                        max(proxy.size.width - 1, 1)
                    )
                    let markerX = layoutDirection == .rightToLeft
                        ? proxy.size.width - leadingMarkerX
                        : leadingMarkerX
                    Path { path in
                        path.move(to: CGPoint(x: markerX, y: 0))
                        path.addLine(
                            to: CGPoint(x: markerX, y: proxy.size.height)
                        )
                    }
                    .stroke(
                        forecastColor,
                        style: StrokeStyle(
                            lineWidth: 2,
                            lineCap: .round,
                            dash: [4, 4]
                        )
                    )
                }
            }
        }
        .frame(height: isCompact ? 18 : 22)
    }

    private var actualColor: Color {
        colorScheme == .dark
            ? Color(red: 90.0 / 255.0, green: 162.0 / 255.0, blue: 1)
            : Color(red: 37.0 / 255.0, green: 99.0 / 255.0, blue: 235.0 / 255.0)
    }

    private var forecastColor: Color {
        colorScheme == .dark
            ? Color(red: 245.0 / 255.0, green: 196.0 / 255.0, blue: 81.0 / 255.0)
            : Color(red: 154.0 / 255.0, green: 87.0 / 255.0, blue: 0)
    }
}

struct TokenMonthlyBudgetWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(
            kind: WidgetSharedConfiguration.monthlyBudgetKind,
            provider: WidgetTimelineProvider()
        ) { entry in
            TokenMonthlyBudgetWidgetView(entry: entry)
                .containerBackground(.background, for: .widget)
        }
        .configurationDisplayName(
            String(localized: "widget.monthlyBudget.name")
        )
        .supportedFamilies([.systemMedium])
    }
}
