import Foundation

enum WidgetFallbackLocalization {
    static func make(date: Date, calendar: Calendar) -> WidgetLocalizedText {
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.locale = .autoupdatingCurrent
        formatter.setLocalizedDateFormatFromTemplate("Md")
        let dateText = formatter.string(from: date)

        return WidgetLocalizedText(
            heatmapTitle: String(localized: "widget.heatmap.title"),
            todayUsageTitle: String(localized: "widget.today.title"),
            datedUsageTitle: String(
                format: String(localized: "widget.dated.format"),
                dateText
            ),
            updatedThroughTitle: String(
                format: String(localized: "widget.updated.format"),
                dateText
            ),
            notReadyMessage: String(localized: "widget.notReady"),
            projectFocusTitle: String(localized: "widget.projectFocus.name"),
            projectFocusNoDataMessage: String(localized: "widget.notReady"),
            modelFocusTitle: String(localized: "widget.modelFocus.name"),
            modelFocusNoDataMessage: String(localized: "widget.notReady")
        )
    }
}

enum WidgetSampleSnapshotFactory {
    static func make(
        date: Date,
        calendar: Calendar,
        localizedText: WidgetLocalizedText
    ) -> WidgetUsageSnapshot {
        let cells = (0..<(WidgetChartVisualStyle.heatmapColumns
            * WidgetChartVisualStyle.heatmapRows)).map { index in
            let intensity = index % (WidgetChartVisualStyle.heatmapMaximumIntensity + 1)
            return WidgetHeatmapCell(
                dateKey: "sample-\(index)",
                totalTokens: intensity * 100_000,
                intensity: intensity,
                isPlaceholder: false
            )
        }
        let currentHour = calendar.component(.hour, from: date)
        let points = (0...23).map { hour in
            let total = max(0, 18 - abs(14 - hour) * 2) * 100_000
            return WidgetHourlyPoint(
                hour: hour,
                hourKey: "sample-hour-\(hour)",
                hourLabel: "\(hour)",
                totalTokens: total,
                isCurrentHour: hour == currentHour
            )
        }
        let localDayKey = dayKey(date, calendar: calendar)

        return WidgetUsageSnapshot(
            schemaVersion: WidgetSharedConfiguration.schemaVersion,
            generatedAt: date,
            localDayKey: localDayKey,
            localizedText: localizedText,
            heatmap: WidgetHeatmapSnapshot(
                totalTokens: cells.reduce(0) { $0 + $1.totalTokens },
                maxDailyTokens: cells.map(\.totalTokens).max() ?? 0,
                cells: cells
            ),
            hourlyLine: WidgetHourlyLineSnapshot(
                dayKey: localDayKey,
                totalTokens: points.reduce(0) { $0 + $1.totalTokens },
                maxHourlyTokens: points.map(\.totalTokens).max() ?? 0,
                points: points
            ),
            projectFocus: WidgetProjectFocusSnapshot(
                windowStartDayKey: localDayKey,
                windowEndDayKey: localDayKey,
                windowTotalTokens: 1_800_000,
                topProjectName: "TokenWatch",
                topProjectTokens: 1_100_000
            ),
            modelFocus: WidgetModelFocusSnapshot(
                windowStartDayKey: localDayKey,
                windowEndDayKey: localDayKey,
                windowTotalTokens: 1_800_000,
                providerName: "Claude",
                modelName: "claude-sonnet",
                modelTokens: 1_000_000
            )
        )
    }

    private static func dayKey(_ date: Date, calendar: Calendar) -> String {
        let components = calendar.dateComponents([.year, .month, .day], from: date)
        return String(
            format: "%04d-%02d-%02d",
            components.year ?? 0,
            components.month ?? 0,
            components.day ?? 0
        )
    }
}
