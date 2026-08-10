import SwiftUI
import WidgetKit

struct TokenProjectFocusWidgetView: View {
    let entry: WidgetUsageEntry
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let presentation = WidgetChartPresentationBuilder.projectFocus(for: entry.state)

        VStack(alignment: .leading, spacing: 7) {
            HStack(alignment: .top, spacing: 6) {
                Text(presentation.title)
                    .font(.headline)
                    .lineLimit(1)
                Spacer(minLength: 4)
                VStack(alignment: .trailing, spacing: 0) {
                    if let windowTotalText = presentation.windowTotalText {
                        Text(windowTotalText)
                            .font(.title3)
                            .fontWeight(.semibold)
                            .monospacedDigit()
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                    }
                    if let subtitle = presentation.subtitle {
                        Text(subtitle)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
            }

            if let projectName = presentation.projectName {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(projectName)
                        .font(.system(.title2, design: .rounded, weight: .bold))
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                    Spacer(minLength: 4)
                    Text(presentation.totalText)
                        .font(.title3)
                        .fontWeight(.semibold)
                        .monospacedDigit()
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                }
                if let share = presentation.shareText {
                    HStack(spacing: 4) {
                        if let shareTitle = presentation.shareTitle {
                            Text(shareTitle)
                        }
                        Text(share)
                            .monospacedDigit()
                        Spacer(minLength: 0)
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
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
                    .fill(.primary.opacity(0.1))
                Capsule()
                    .fill(projectColor)
                    .frame(width: width)
            }
        }
        .frame(height: 8)
    }

    private var projectColor: Color {
        colorScheme == .dark
            ? Color(red: 167.0 / 255.0, green: 139.0 / 255.0, blue: 250.0 / 255.0)
            : Color(red: 124.0 / 255.0, green: 58.0 / 255.0, blue: 237.0 / 255.0)
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
