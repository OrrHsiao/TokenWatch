import Foundation

/// A versioned, render-ready usage snapshot shared with widgets.
struct WidgetUsageSnapshot: Codable, Equatable, Sendable {
    let schemaVersion: Int
    let generatedAt: Date
    let localDayKey: String
    let localizedText: WidgetLocalizedText
    let heatmap: WidgetHeatmapSnapshot
    let hourlyLine: WidgetHourlyLineSnapshot

    /// Compares every render-relevant value while deliberately ignoring generation time.
    func hasSameContent(as other: WidgetUsageSnapshot) -> Bool {
        schemaVersion == other.schemaVersion
            && localDayKey == other.localDayKey
            && localizedText == other.localizedText
            && heatmap == other.heatmap
            && hourlyLine == other.hourlyLine
    }
}

/// Localized copy captured with a snapshot so widgets can render without app state.
struct WidgetLocalizedText: Codable, Equatable, Sendable {
    let heatmapTitle: String
    let todayUsageTitle: String
    let datedUsageTitle: String
    let updatedThroughTitle: String
    let notReadyMessage: String
}

/// Aggregate values and cells required to render the token heatmap.
struct WidgetHeatmapSnapshot: Codable, Equatable, Sendable {
    let totalTokens: Int
    let maxDailyTokens: Int
    let cells: [WidgetHeatmapCell]
}

/// One dated or placeholder cell in the widget heatmap.
struct WidgetHeatmapCell: Codable, Equatable, Sendable {
    let dateKey: String?
    let totalTokens: Int
    let intensity: Int
    let isPlaceholder: Bool
}

/// Aggregate values and hourly points required to render the line widget.
struct WidgetHourlyLineSnapshot: Codable, Equatable, Sendable {
    let dayKey: String
    let totalTokens: Int
    let maxHourlyTokens: Int
    let points: [WidgetHourlyPoint]
}

/// One hour in the line snapshot, identified by its stable local-hour key.
struct WidgetHourlyPoint: Codable, Equatable, Identifiable, Sendable {
    var id: String { hourKey }

    let hour: Int
    let hourKey: String
    let hourLabel: String
    let totalTokens: Int
    let isCurrentHour: Bool
}
