import Foundation

/// A schema-versioned, render-ready payload transferred from the host app to widgets.
///
/// `localDayKey` is the `yyyy-MM-dd` wall-calendar day derived with the same caller-
/// supplied `Calendar` and time zone used to build the charts; it is not a UTC day.
/// A valid payload uses `WidgetSharedConfiguration.schemaVersion` and has the same
/// `localDayKey` as `hourlyLine.dayKey`. `generatedAt` records freshness only, so it is
/// deliberately excluded from semantic content comparison.
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

/// Rendered copy frozen in the app language when the snapshot is generated.
///
/// Widgets display these strings verbatim until a newer snapshot arrives instead of
/// consulting their own current locale. `WidgetHourlyPoint.hourLabel` follows the same
/// frozen-localization rule.
struct WidgetLocalizedText: Codable, Equatable, Sendable {
    let heatmapTitle: String
    let todayUsageTitle: String
    let datedUsageTitle: String
    let updatedThroughTitle: String
    let notReadyMessage: String
}

/// A fixed 22-column by 7-row heatmap shared in column-major order.
///
/// `cells` contains exactly 154 entries. Indices `0...6` form the oldest week, then
/// subsequent week columns progress toward the newest week; within a column, rows follow
/// the builder calendar's `firstWeekday` order (`index = column * 7 + row`). Storage
/// validates the fixed shape but does not reorder cells, so the producer preserves this
/// ordering convention for the renderer.
///
/// `totalTokens`, every cell's `totalTokens`, and `maxDailyTokens` preserve the existing
/// `UsageSummary.totalTokens` semantics: reasoning tokens are included, never added again
/// as a separate amount. The maximum is computed from those same per-day totals.
struct WidgetHeatmapSnapshot: Codable, Equatable, Sendable {
    let totalTokens: Int
    let maxDailyTokens: Int
    let cells: [WidgetHeatmapCell]
}

/// One real local day or padding position in the fixed heatmap grid.
///
/// A placeholder has no `dateKey`, sets `isPlaceholder` to true, and carries zero tokens
/// and zero intensity. A real zero-usage day keeps its `dateKey` and is not a placeholder.
/// Valid real cells have nonnegative tokens and an intensity in `0...4`.
struct WidgetHeatmapCell: Codable, Equatable, Sendable {
    let dateKey: String?
    let totalTokens: Int
    let intensity: Int
    let isPlaceholder: Bool
}

/// A local civil-day line with exactly 24 wall-clock buckets ordered from hour 0 through 23.
///
/// The fixed wall-clock shape is retained on daylight-saving transition days rather than
/// representing 24 elapsed hours. A valid snapshot has `dayKey == localDayKey`, points in
/// ascending `hour` order, 24 unique nonempty keys, and exactly one current-hour marker.
/// `totalTokens`, every point's `totalTokens`, and `maxHourlyTokens` preserve the existing
/// `UsageSummary.totalTokens` semantics: reasoning tokens are included, never added again
/// as a separate amount. The maximum is computed from those same per-hour totals.
struct WidgetHourlyLineSnapshot: Codable, Equatable, Sendable {
    let dayKey: String
    let totalTokens: Int
    let maxHourlyTokens: Int
    let points: [WidgetHourlyPoint]
}

/// One local wall-clock hour and its frozen display state.
///
/// The producer forms `hourKey` as `<dayKey>T<HH>` for the point's zero-padded `hour`.
/// Storage currently treats that value as opaque and enforces only uniqueness/nonemptiness,
/// so consumers use `dayKey` plus `hour` for calendar meaning instead of parsing the key.
/// `hourLabel` is localized when generated. A valid payload contains exactly one point with
/// `isCurrentHour == true`; the producer selects the wall-clock bucket containing the
/// snapshot's `generatedAt` value, while storage validates the marker count only.
struct WidgetHourlyPoint: Codable, Equatable, Identifiable, Sendable {
    var id: String { hourKey }

    let hour: Int
    let hourKey: String
    let hourLabel: String
    let totalTokens: Int
    let isCurrentHour: Bool
}
