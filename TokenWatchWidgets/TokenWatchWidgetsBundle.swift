import SwiftUI
import WidgetKit

@main
struct TokenWatchWidgetsBundle: WidgetBundle {
    @WidgetBundleBuilder
    var body: some Widget {
        TokenHeatmapWidget()
    }
}
