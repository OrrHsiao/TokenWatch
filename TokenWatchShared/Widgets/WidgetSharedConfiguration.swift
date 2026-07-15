import Foundation

/// Stable identifiers shared by the host app and its widget extension.
enum WidgetSharedConfiguration {
    static let schemaVersion = 1
    static let appGroupIdentifier = "group.com.xiaoao.tokenwatch"
    static let snapshotFilename = "widget-usage-v1.json"
    static let heatmapKind = "TokenHeatmapWidget"
    static let hourlyLineKind = "TokenHourlyLineWidget"
}
