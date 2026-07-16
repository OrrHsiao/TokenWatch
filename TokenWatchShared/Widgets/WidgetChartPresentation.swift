import Foundation

/// Render-ready heatmap cell state without any SwiftUI or WidgetKit dependency.
struct WidgetHeatmapPresentationCell: Equatable, Sendable {
    let intensity: Int
    let isVisible: Bool
}

/// Render-ready heatmap content and aggregate accessibility copy.
struct WidgetHeatmapPresentation: Equatable, Sendable {
    let title: String
    let subtitle: String?
    let totalText: String
    let cells: [WidgetHeatmapPresentationCell]
    let message: String?
    let accessibilityLabel: String
}

/// Render-ready hourly line content and aggregate accessibility copy.
struct WidgetHourlyLinePresentation: Equatable, Sendable {
    let title: String
    let totalText: String
    let points: [WidgetHourlyPoint]
    let maximumY: Double
    let currentPoint: WidgetHourlyPoint?
    let message: String?
    let accessibilityLabel: String
}

/// Derives framework-neutral chart presentations from widget timeline states.
enum WidgetChartPresentationBuilder {
    /// Builds a fixed 22-by-7 heatmap presentation for the supplied entry state.
    static func heatmap(
        for state: WidgetUsageEntryState
    ) -> WidgetHeatmapPresentation {
        switch state {
        case .placeholder(let snapshot), .current(let snapshot):
            return heatmap(snapshot: snapshot, isStale: false)
        case .stale(let snapshot):
            return heatmap(snapshot: snapshot, isStale: true)
        case .notReady(let text):
            let totalText = WidgetChartNumberFormatter.compact(0)
            let cells = Array(
                repeating: WidgetHeatmapPresentationCell(
                    intensity: 0,
                    isVisible: true
                ),
                count: WidgetChartVisualStyle.heatmapColumns
                    * WidgetChartVisualStyle.heatmapRows
            )
            return WidgetHeatmapPresentation(
                title: text.heatmapTitle,
                subtitle: nil,
                totalText: totalText,
                cells: cells,
                message: text.notReadyMessage,
                accessibilityLabel: aggregateLabel([
                    text.heatmapTitle,
                    text.notReadyMessage,
                    totalText,
                ])
            )
        }
    }

    /// Builds a fixed 24-hour line presentation for the supplied entry state.
    static func hourlyLine(
        for state: WidgetUsageEntryState
    ) -> WidgetHourlyLinePresentation {
        switch state {
        case .placeholder(let snapshot), .current(let snapshot):
            return hourlyLine(snapshot: snapshot, isStale: false)
        case .stale(let snapshot):
            return hourlyLine(snapshot: snapshot, isStale: true)
        case .notReady(let text):
            let totalText = WidgetChartNumberFormatter.compact(0)
            let points = (0...23).map { hour in
                WidgetHourlyPoint(
                    hour: hour,
                    hourKey: "not-ready-hour-\(hour)",
                    hourLabel: "\(hour)",
                    totalTokens: 0,
                    isCurrentHour: false
                )
            }
            return WidgetHourlyLinePresentation(
                title: text.todayUsageTitle,
                totalText: totalText,
                points: points,
                maximumY: WidgetChartVisualStyle.hourlyMaximumY(
                    maxHourlyTokens: 0
                ),
                currentPoint: nil,
                message: text.notReadyMessage,
                accessibilityLabel: aggregateLabel([
                    text.todayUsageTitle,
                    text.notReadyMessage,
                    totalText,
                ])
            )
        }
    }

    private static func heatmap(
        snapshot: WidgetUsageSnapshot,
        isStale: Bool
    ) -> WidgetHeatmapPresentation {
        let title = snapshot.localizedText.heatmapTitle
        let subtitle = isStale
            ? snapshot.localizedText.updatedThroughTitle
            : nil
        let totalText = WidgetChartNumberFormatter.compact(
            snapshot.heatmap.totalTokens
        )
        let cells = snapshot.heatmap.cells.map { cell in
            WidgetHeatmapPresentationCell(
                intensity: cell.intensity,
                isVisible: !cell.isPlaceholder
            )
        }
        return WidgetHeatmapPresentation(
            title: title,
            subtitle: subtitle,
            totalText: totalText,
            cells: cells,
            message: nil,
            accessibilityLabel: aggregateLabel([
                title,
                snapshot.localizedText.updatedThroughTitle,
                totalText,
            ])
        )
    }

    private static func hourlyLine(
        snapshot: WidgetUsageSnapshot,
        isStale: Bool
    ) -> WidgetHourlyLinePresentation {
        let title = isStale
            ? snapshot.localizedText.datedUsageTitle
            : snapshot.localizedText.todayUsageTitle
        let totalText = WidgetChartNumberFormatter.compact(
            snapshot.hourlyLine.totalTokens
        )
        let currentPoint = isStale
            ? nil
            : snapshot.hourlyLine.points.first(where: \.isCurrentHour)
        return WidgetHourlyLinePresentation(
            title: title,
            totalText: totalText,
            points: snapshot.hourlyLine.points,
            maximumY: WidgetChartVisualStyle.hourlyMaximumY(
                maxHourlyTokens: snapshot.hourlyLine.maxHourlyTokens
            ),
            currentPoint: currentPoint,
            message: nil,
            accessibilityLabel: aggregateLabel([
                title,
                isStale ? nil : snapshot.localizedText.datedUsageTitle,
                totalText,
            ])
        )
    }

    private static func aggregateLabel(_ values: [String?]) -> String {
        values
            .compactMap { $0 }
            .filter { !$0.isEmpty }
            .joined(separator: ", ")
    }
}
