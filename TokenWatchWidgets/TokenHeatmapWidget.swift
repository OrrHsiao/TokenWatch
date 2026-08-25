import SwiftUI
import WidgetKit

struct TokenHeatmapWidgetView: View {
    let entry: WidgetUsageEntry
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.widgetRenderingMode) private var widgetRenderingMode

    var body: some View {
        let presentation = WidgetChartPresentationBuilder.heatmap(for: entry.state)

        VStack(spacing: 6) {
            WidgetChartHeader(
                title: presentation.title,
                subtitle: presentation.subtitle,
                total: presentation.totalText
            )
            if presentation.message == nil {
                WidgetMetricStrip(items: metricItems(presentation))
            }
            ZStack {
                heatmapGrid(presentation)
                    .opacity(presentation.message == nil ? 1 : 0.35)
                if let message = presentation.message {
                    Text(message)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(presentation.accessibilityLabel)
    }

    private func metricItems(
        _ presentation: WidgetHeatmapPresentation
    ) -> [WidgetMetricItem] {
        var items: [WidgetMetricItem] = []
        if let dailyAverageText = presentation.dailyAverageText {
            items.append(WidgetMetricItem(
                symbolName: "calendar",
                text: dailyAverageText
            ))
        }
        if let peakText = presentation.peakText {
            items.append(WidgetMetricItem(
                symbolName: "arrow.up.to.line",
                text: peakText
            ))
        }
        return items
    }

    private func heatmapGrid(_ presentation: WidgetHeatmapPresentation) -> some View {
        GeometryReader { proxy in
            let side = CGFloat(WidgetChartVisualStyle.heatmapTileSide(
                availableWidth: Double(proxy.size.width),
                availableHeight: Double(proxy.size.height)
            ))
            let spacing = CGFloat(WidgetChartVisualStyle.heatmapSpacing)
            let radius = CGFloat(WidgetChartVisualStyle.heatmapCornerRadius)

            HStack(spacing: spacing) {
                ForEach(0..<WidgetChartVisualStyle.heatmapColumns, id: \.self) { column in
                    VStack(spacing: spacing) {
                        ForEach(0..<WidgetChartVisualStyle.heatmapRows, id: \.self) { row in
                            let index = WidgetChartVisualStyle.heatmapIndex(
                                column: column,
                                row: row
                            )
                            let cell = presentation.cells[index]
                            RoundedRectangle(cornerRadius: radius)
                                .fill(color(for: cell))
                                .frame(width: side, height: side)
                        }
                    }
                }
            }
            .frame(
                maxWidth: .infinity,
                maxHeight: .infinity,
                alignment: .center
            )
        }
    }

    private func color(for cell: WidgetHeatmapPresentationCell) -> Color {
        guard cell.isVisible else { return .clear }
        if widgetRenderingMode == .vibrant {
            // Vibrant mode derives material strength from opaque grayscale brightness.
            return Color(
                .sRGB,
                white: WidgetChartVisualStyle.heatmapVibrantWhiteLevel(
                    intensity: cell.intensity
                ),
                opacity: 1
            )
        }
        if widgetRenderingMode == .accented {
            return .primary.opacity(
                WidgetChartVisualStyle.heatmapAccentedOpacity(
                    intensity: cell.intensity
                )
            )
        }
        let rgba = WidgetChartVisualStyle.heatmapRGBA(
            intensity: cell.intensity,
            isDark: colorScheme == .dark
        )
        return Color(
            .sRGB,
            red: rgba.red,
            green: rgba.green,
            blue: rgba.blue,
            opacity: rgba.alpha
        )
    }
}

struct TokenHeatmapWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(
            kind: WidgetSharedConfiguration.heatmapKind,
            provider: WidgetTimelineProvider()
        ) { entry in
            TokenHeatmapWidgetView(entry: entry)
                .containerBackground(.background, for: .widget)
        }
        .configurationDisplayName(LocalizedStringKey("widget.heatmap.name"))
        .description(LocalizedStringKey("widget.heatmap.description"))
        .supportedFamilies([.systemMedium])
    }
}
