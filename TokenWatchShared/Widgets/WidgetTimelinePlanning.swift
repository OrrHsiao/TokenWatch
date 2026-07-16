import Foundation

/// Framework-neutral widget entry data states shared by timeline and presentation logic.
enum WidgetUsageEntryState: Equatable, Sendable {
    case placeholder(WidgetUsageSnapshot)
    case current(WidgetUsageSnapshot)
    case stale(WidgetUsageSnapshot)
    case notReady(WidgetLocalizedText)
}

/// Classifies stored snapshots and plans calendar-aware widget refresh boundaries.
enum WidgetTimelinePlanner {
    /// Converts a validated store result into the rendering state for a local calendar day.
    /// - Parameters:
    ///   - result: The nonthrowing result returned by the shared snapshot store.
    ///   - date: The timeline entry date to classify.
    ///   - calendar: The calendar and time zone defining the local day.
    ///   - fallbackText: Localized copy shown when no valid snapshot is available.
    /// - Returns: A current, stale, or not-ready state ready for presentation derivation.
    static func state(
        for result: WidgetSnapshotReadResult,
        at date: Date,
        calendar: Calendar,
        fallbackText: WidgetLocalizedText
    ) -> WidgetUsageEntryState {
        switch result {
        case .available(let snapshot):
            return snapshot.localDayKey == dayKey(date, calendar: calendar)
                ? .current(snapshot)
                : .stale(snapshot)
        case .missing, .invalid:
            return .notReady(fallbackText)
        }
    }

    /// Returns the next local midnight using calendar-day arithmetic across DST changes.
    /// - Parameters:
    ///   - date: A reference instant within the current local day.
    ///   - calendar: The calendar and time zone that define local midnight.
    /// - Returns: The start of the following local day.
    static func nextLocalMidnight(after date: Date, calendar: Calendar) -> Date {
        let start = calendar.startOfDay(for: date)
        return calendar.date(byAdding: .day, value: 1, to: start)
            ?? date.addingTimeInterval(60 * 60)
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
