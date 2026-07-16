import SwiftUI
import WidgetKit

struct TokenHeatmapWidgetView: View {
    let entry: WidgetUsageEntry
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let presentation = WidgetChartPresentationBuilder.heatmap(for: entry.state)

        VStack(spacing: 8) {
            WidgetChartHeader(
                title: presentation.title,
                subtitle: presentation.subtitle,
                total: presentation.totalText
            )
            ZStack {
                heatmapGrid(presentation)
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
