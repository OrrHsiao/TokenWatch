import SwiftUI
import WidgetKit

@main
struct TokenWatchWidgetsBundle: WidgetBundle {
    var body: some Widget {
        TokenWatchHeatmapWidget()
        TokenWatchTodayLineWidget()
    }
}
