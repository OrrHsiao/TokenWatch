import Foundation
import os.log
import WidgetKit

/// Publishes settled ViewModel state into the shared Widget snapshot.
@MainActor
protocol WidgetSnapshotPublishing: AnyObject, Sendable {
    /// Builds and publishes a snapshot for the current provider states.
    /// - Parameter states: Settled provider states from `TokenStatsViewModel`.
    func publish(states: [ProviderID: TokenStatsViewModel.ProviderState])
}

/// Abstraction over WidgetKit timeline reloads.
@MainActor
protocol WidgetTimelineReloading: AnyObject, Sendable {
    /// Reloads all widget timelines after a new snapshot is available.
    func reloadAllTimelines()
}

@MainActor
final class SystemWidgetTimelineReloader: WidgetTimelineReloading {
    func reloadAllTimelines() {
        WidgetCenter.shared.reloadAllTimelines()
    }
}

/// Builds the latest widget snapshot, writes it to the App Group, and asks WidgetKit to reload.
@MainActor
final class WidgetSnapshotPublisher: WidgetSnapshotPublishing, @unchecked Sendable {
    static let shared = WidgetSnapshotPublisher()

    private let store: TokenWatchWidgetSnapshotStore
    private let timelineReloader: any WidgetTimelineReloading
    private let dateProvider: () -> Date
    private let calendar: Calendar
    private let languageSettings: AppLanguageSettings
    private let logger = Logger(subsystem: "com.xiaoao.TokenWatch", category: "WidgetSnapshotPublisher")

    init(
        store: TokenWatchWidgetSnapshotStore = TokenWatchWidgetSnapshotStore(),
        timelineReloader: any WidgetTimelineReloading = SystemWidgetTimelineReloader(),
        dateProvider: @escaping () -> Date = Date.init,
        calendar: Calendar = .current,
        languageSettings: AppLanguageSettings = .shared
    ) {
        self.store = store
        self.timelineReloader = timelineReloader
        self.dateProvider = dateProvider
        self.calendar = calendar
        self.languageSettings = languageSettings
    }

    func publish(states: [ProviderID: TokenStatsViewModel.ProviderState]) {
        let snapshot = WidgetSnapshotBuilder.build(
            states: states,
            now: dateProvider(),
            calendar: calendar,
            language: languageSettings.resolvedLanguage
        )

        do {
            try store.write(snapshot)
            logger.info("Widget 快照已写入,status=\(snapshot.status.rawValue),generatedAt=\(snapshot.generatedAt.ISO8601Format())")
            timelineReloader.reloadAllTimelines()
        } catch {
            logger.error("Widget 快照写入失败: \(error.localizedDescription)")
        }
    }
}
