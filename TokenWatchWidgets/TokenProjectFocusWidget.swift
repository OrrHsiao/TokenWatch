import SwiftUI
import WidgetKit

struct TokenProjectFocusWidgetView: View {
    let entry: WidgetUsageEntry

    var body: some View {
        let presentation = WidgetChartPresentationBuilder.projectFocus(for: entry.state)

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
                Text(presentation.totalText)
                    .font(.headline)
                    .fontWeight(.semibold)
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }

            if let projectName = presentation.projectName {
                Text(projectName)
                    .font(.title3)
                    .fontWeight(.semibold)
                    .lineLimit(1)
                HStack {
                    if let share = presentation.shareText {
                        Text(share)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    }
                    Spacer(minLength: 0)
                }
                progressBar(progress: presentation.progress)
            } else if let message = presentation.message {
                Text(message)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }

            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(presentation.accessibilityLabel)
    }

    private func progressBar(progress: Double) -> some View {
        GeometryReader { proxy in
            let width = proxy.size.width * min(max(progress, 0), 1)
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(.secondary.opacity(0.2))
                Capsule()
                    .fill(Color.accentColor)
                    .frame(width: width)
            }
        }
        .frame(height: 8)
    }
}

struct TokenProjectFocusWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(
            kind: WidgetSharedConfiguration.projectFocusKind,
            provider: WidgetTimelineProvider()
        ) { entry in
            TokenProjectFocusWidgetView(entry: entry)
                .containerBackground(.background, for: .widget)
        }
        .configurationDisplayName(LocalizedStringKey("widget.projectFocus.name"))
        .supportedFamilies([.systemMedium])
    }
}
