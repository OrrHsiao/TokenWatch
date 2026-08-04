import Foundation
import os.log
import WidgetKit

enum WidgetSnapshotPublishResult: Equatable, Sendable {
    case published
    case unchanged
    case skippedNoValidStats
    case failed
}

/// Publishes render-ready widget snapshots from the host app's aggregate provider states.
protocol WidgetSnapshotPublishing: Sendable {
    /// Builds and conditionally persists a snapshot before notifying widget timelines.
    /// - Parameters:
    ///   - states: Current aggregate states retained by the host app.
    ///   - language: Resolved app language frozen into the rendered snapshot.
    ///   - monthlyBudgetUSD: Optional user-selected USD limit embedded in the budget widget.
    /// - Returns: The publication outcome, including unchanged and unavailable-data cases.
    @discardableResult
    func publish(
        states: [ProviderID: TokenStatsViewModel.ProviderState],
        language: AppLanguage,
        monthlyBudgetUSD: Double?
    ) async -> WidgetSnapshotPublishResult
}

/// Minimal reload seam shared by the live publisher and deterministic tests.
protocol WidgetTimelineReloading: Sendable {
    /// Requests a timeline reload for one exact widget kind.
    /// - Parameter kind: The widget kind registered by the extension.
    func reloadTimelines(ofKind kind: String)
}

struct WidgetKitTimelineReloader: WidgetTimelineReloading, Sendable {
    func reloadTimelines(ofKind kind: String) {
        WidgetCenter.shared.reloadTimelines(ofKind: kind)
    }
}

/// Serializes cross-process snapshot comparison, persistence, and timeline notification.
actor WidgetSnapshotPublisher: WidgetSnapshotPublishing {
    private let store: any WidgetSnapshotStoring
    private let timelineReloader: any WidgetTimelineReloading
    private let now: @Sendable () -> Date
    private let calendar: @Sendable () -> Calendar
    private let logger = Logger(
        subsystem: "com.xiaoao.TokenWatch",
        category: "WidgetSnapshotPublisher"
    )

    init(
        store: any WidgetSnapshotStoring,
        timelineReloader: any WidgetTimelineReloading,
        now: @escaping @Sendable () -> Date = Date.init,
        calendar: @escaping @Sendable () -> Calendar = { .autoupdatingCurrent }
    ) {
        self.store = store
        self.timelineReloader = timelineReloader
        self.now = now
        self.calendar = calendar
    }

    /// Publishes only semantic changes, preserving old data when no aggregate is available.
    ///
    /// Persistence completes before all registered widget kinds are reloaded. Failure logs are
    /// intentionally categorical and omit paths, provider payloads, totals, and localized copy.
    @discardableResult
    func publish(
        states: [ProviderID: TokenStatsViewModel.ProviderState],
        language: AppLanguage,
        monthlyBudgetUSD: Double? = nil
    ) async -> WidgetSnapshotPublishResult {
        let currentDate = now()
        guard let candidate = WidgetSnapshotBuilder.build(
            states: states,
            now: currentDate,
            calendar: calendar(),
            language: language,
            monthlyBudgetUSD: monthlyBudgetUSD
        ) else {
            logger.info("No valid aggregate; preserving the existing widget snapshot")
            return .skippedNoValidStats
        }

        switch store.load() {
        case .available(let existing) where existing.hasSameContent(as: candidate):
            return .unchanged
        case .invalid(.unreadable):
            logger.error("Existing widget snapshot is unreadable; attempting replacement")
        case .invalid(.corrupt):
            logger.error("Existing widget snapshot is corrupt; attempting replacement")
        case .invalid(.unsupportedSchema):
            logger.error("Existing widget snapshot uses an unsupported schema; attempting replacement")
        case .available, .missing:
            break
        }

        do {
            try store.save(candidate)
        } catch {
            logger.error("Widget snapshot write failed")
            return .failed
        }

        timelineReloader.reloadTimelines(ofKind: WidgetSharedConfiguration.heatmapKind)
        timelineReloader.reloadTimelines(ofKind: WidgetSharedConfiguration.hourlyLineKind)
        timelineReloader.reloadTimelines(ofKind: WidgetSharedConfiguration.weeklySummaryKind)
        timelineReloader.reloadTimelines(ofKind: WidgetSharedConfiguration.monthlyBudgetKind)
        return .published
    }
}

enum WidgetSnapshotPublisherFactory {
    private static let logger = Logger(
        subsystem: "com.xiaoao.TokenWatch",
        category: "WidgetSnapshotPublisherFactory"
    )

    /// Creates the live publisher, or disables publication when App Group resolution fails.
    static func makeLive() -> (any WidgetSnapshotPublishing)? {
        do {
            return WidgetSnapshotPublisher(
                store: try JSONWidgetSnapshotStore.appGroupStore(),
                timelineReloader: WidgetKitTimelineReloader()
            )
        } catch {
            logger.error("App Group container unavailable; widget publication disabled")
            return nil
        }
    }
}
