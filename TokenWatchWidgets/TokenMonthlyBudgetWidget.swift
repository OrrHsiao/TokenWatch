import SwiftUI
import WidgetKit

struct TokenMonthlyBudgetWidgetView: View {
    let entry: WidgetUsageEntry

    var body: some View {
        let presentation = WidgetChartPresentationBuilder.monthlyBudget(for: entry.state)

        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                VStack(alignment: .leading, spacing: 1) {
                    Text(presentation.title)
                        .font(.headline)
                        .lineLimit(1)
                    if let subtitle = presentation.subtitle {
                        Text(subtitle)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
                Spacer(minLength: 4)
                Text(presentation.spentText)
                    .font(.headline)
                    .fontWeight(.semibold)
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }

            if let budgetText = presentation.budgetText,
               let progress = presentation.progress {
                Text("\(presentation.spentText) / \(budgetText)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
                    .lineLimit(1)
                progressBar(
                    progress: progress,
                    isOverBudget: presentation.isForecastOverBudget
                )
                if let forecastText = presentation.forecastText {
                    Text(forecastText)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }

            if let message = presentation.message {
                Text(message)
                    .font(.caption2)
                    .foregroundStyle(
                        presentation.isForecastOverBudget ? .red : .secondary
                    )
                    .lineLimit(2)
            }

            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(presentation.accessibilityLabel)
    }

    private func progressBar(progress: Double, isOverBudget: Bool) -> some View {
        GeometryReader { proxy in
            let width = proxy.size.width * min(max(progress, 0), 1)
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(.secondary.opacity(0.2))
                Capsule()
                    .fill(isOverBudget ? Color.red : Color.accentColor)
                    .frame(width: width)
            }
        }
        .frame(height: 8)
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
        .configurationDisplayName("Monthly Budget")
        .supportedFamilies([.systemMedium])
    }
}
