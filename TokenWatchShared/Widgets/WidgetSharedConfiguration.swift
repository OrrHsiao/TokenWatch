import Foundation

/// Cross-process wire identifiers shared by the host app and widget extension.
///
/// `schemaVersion` versions the JSON shape and rendering semantics, not the app release.
/// Readers accept only an exact version match before decoding the full payload. An
/// incompatible contract change therefore requires a coordinated host/widget version
/// bump and a new versioned snapshot filename instead of reinterpreting existing bytes.
/// The App Group, filename, and widget kinds are persisted system identifiers and must
/// likewise change only as part of a coordinated migration.
enum WidgetSharedConfiguration {
    static let schemaVersion = 1
    static let appGroupIdentifier = "group.com.xiaoao.tokenwatch"
    static let snapshotFilename = "widget-usage-v1.json"
    static let heatmapKind = "TokenHeatmapWidget"
    static let hourlyLineKind = "TokenHourlyLineWidget"
}
