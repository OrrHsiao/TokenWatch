import Foundation
import os.log
import WidgetKit

struct WidgetUsageEntry: TimelineEntry, Equatable, Sendable {
    let date: Date
    let state: WidgetUsageEntryState
}

private struct MissingWidgetSnapshotStore: WidgetSnapshotStoring, Sendable {
    func load() -> WidgetSnapshotReadResult {
        .missing
    }

    func save(_ snapshot: WidgetUsageSnapshot) throws {
        throw WidgetSnapshotStoreError.invalidSnapshot
    }
}

struct WidgetTimelineProvider: TimelineProvider {
    typealias Entry = WidgetUsageEntry

    private static let logger = Logger(
        subsystem: "com.xiaoao.TokenWatch.widgets",
        category: "WidgetTimelineProvider"
    )

    private let store: any WidgetSnapshotStoring
    private let now: @Sendable () -> Date
    private let calendar: @Sendable () -> Calendar

    init(
        store: any WidgetSnapshotStoring = WidgetTimelineProvider.liveStore(),
        now: @escaping @Sendable () -> Date = Date.init,
        calendar: @escaping @Sendable () -> Calendar = { .autoupdatingCurrent }
    ) {
        self.store = store
        self.now = now
        self.calendar = calendar
    }

    static func liveStore() -> any WidgetSnapshotStoring {
        do {
            return try JSONWidgetSnapshotStore.appGroupStore()
        } catch {
            logger.error("App Group container unavailable; showing not-ready widget state")
            return MissingWidgetSnapshotStore()
        }
    }

    func placeholder(in context: Context) -> WidgetUsageEntry {
        let date = now()
        let calendar = calendar()
        let text = WidgetFallbackLocalization.make(date: date, calendar: calendar)
        return WidgetUsageEntry(
            date: date,
            state: .placeholder(WidgetSampleSnapshotFactory.make(
                date: date,
                calendar: calendar,
                localizedText: text
            ))
        )
    }

    func getSnapshot(
        in context: Context,
        completion: @escaping @Sendable (WidgetUsageEntry) -> Void
    ) {
        if context.isPreview {
            completion(placeholder(in: context))
            return
        }
        let date = now()
        let calendar = calendar()
        completion(currentEntry(date: date, calendar: calendar))
    }

    func getTimeline(
        in context: Context,
        completion: @escaping @Sendable (Timeline<WidgetUsageEntry>) -> Void
    ) {
        let date = now()
        let calendar = calendar()
        let entry = currentEntry(date: date, calendar: calendar)
        let refreshDate = WidgetTimelinePlanner.nextLocalMidnight(
            after: date,
            calendar: calendar
        )
        completion(Timeline(entries: [entry], policy: .after(refreshDate)))
    }

    private func currentEntry(date: Date, calendar: Calendar) -> WidgetUsageEntry {
        let fallback = WidgetFallbackLocalization.make(date: date, calendar: calendar)
        let result = store.load()
        switch result {
        case .invalid(.unreadable):
            Self.logger.error("Shared widget snapshot is unreadable")
        case .invalid(.corrupt):
            Self.logger.error("Shared widget snapshot is corrupt")
        case .invalid(.unsupportedSchema(_)):
            Self.logger.error("Shared widget snapshot uses an unsupported schema")
        case .available, .missing:
            break
        }
        return WidgetUsageEntry(
            date: date,
            state: WidgetTimelinePlanner.state(
                for: result,
                at: date,
                calendar: calendar,
                fallbackText: fallback
            )
        )
    }
}
