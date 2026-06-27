import SwiftUI
import WidgetKit

struct TokenWatchTodayLineWidget: Widget {
    private let kind = "TokenWatchTodayLineWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: TokenWatchWidgetTimelineProvider()) { entry in
            Text(TokenWatchWidgetCopy.text(.todayLineDisplayName, languageIdentifier: entry.snapshot.languageIdentifier))
                .containerBackground(.background, for: .widget)
        }
        .configurationDisplayName(TokenWatchWidgetCopy.text(.todayLineDisplayName, languageIdentifier: "zh-Hans"))
        .description(TokenWatchWidgetCopy.text(.todayLineDescription, languageIdentifier: "zh-Hans"))
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}
