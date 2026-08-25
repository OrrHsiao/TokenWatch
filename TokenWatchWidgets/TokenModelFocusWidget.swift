import SwiftUI
import WidgetKit

struct TokenModelFocusWidgetView: View {
    let entry: WidgetUsageEntry
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let presentation = WidgetChartPresentationBuilder.modelFocus(for: entry.state)

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

            if let modelName = presentation.modelName {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(modelName)
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
                        if let providerName = presentation.providerName {
                            Text(providerName)
                                .lineLimit(1)
                            Text(verbatim: "·")
                        }
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
                    .fill(modelColor)
                    .frame(width: width)
            }
        }
        .frame(height: 8)
    }

    private var modelColor: Color {
        colorScheme == .dark
            ? Color(red: 54.0 / 255.0, green: 198.0 / 255.0, blue: 217.0 / 255.0)
            : Color(red: 14.0 / 255.0, green: 116.0 / 255.0, blue: 144.0 / 255.0)
    }
}

struct TokenModelFocusWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(
            kind: WidgetSharedConfiguration.modelFocusKind,
            provider: WidgetTimelineProvider()
        ) { entry in
            TokenModelFocusWidgetView(entry: entry)
                .containerBackground(.background, for: .widget)
        }
        .configurationDisplayName(LocalizedStringKey("widget.modelFocus.name"))
        .supportedFamilies([.systemMedium])
    }
}
