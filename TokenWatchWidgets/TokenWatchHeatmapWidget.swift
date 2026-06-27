import SwiftUI
import WidgetKit

struct TokenWatchHeatmapWidget: Widget {
    private let kind = "TokenWatchHeatmapWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: TokenWatchWidgetTimelineProvider()) { entry in
            Text(TokenWatchWidgetCopy.text(.tokenHeatmapDisplayName, languageIdentifier: entry.snapshot.languageIdentifier))
                .containerBackground(.background, for: .widget)
        }
        .configurationDisplayName(TokenWatchWidgetCopy.text(.tokenHeatmapDisplayName, languageIdentifier: "zh-Hans"))
        .description(TokenWatchWidgetCopy.text(.tokenHeatmapDescription, languageIdentifier: "zh-Hans"))
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}
