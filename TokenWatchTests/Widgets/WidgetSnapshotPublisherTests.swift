import Foundation
import Testing
@testable import TokenWatch

@Suite("Widget snapshot publisher")
struct WidgetSnapshotPublisherTests {
    @Test("changed content saves before reloading both exact kinds")
    func newContentSavesBeforeReloadingBothKinds() async {
        let events = LockedEventRecorder()
        let store = LockedSnapshotStore(loadResult: .missing, events: events)
        let reloader = RecordingTimelineReloader(events: events)
        let publisher = makePublisher(store: store, reloader: reloader)

        let result = await publisher.publish(states: validStates, language: .zhHans)

        #expect(result == .published)
        #expect(events.values == [
            "save",
            "reload:\(WidgetSharedConfiguration.heatmapKind)",
            "reload:\(WidgetSharedConfiguration.hourlyLineKind)",
        ])
        #expect(store.loadCount == 1)
        #expect(store.saveCount == 1)
        #expect(store.savedSnapshots.count == 1)
        #expect(reloader.kinds == [
            WidgetSharedConfiguration.heatmapKind,
            WidgetSharedConfiguration.hourlyLineKind,
        ])
    }

    @Test("generatedAt-only change neither writes nor reloads")
    func generatedAtOnlyChangeDoesNotSaveOrReload() async throws {
        let candidate = try #require(WidgetSnapshotBuilder.build(
            states: validStates,
            now: fixedNow,
            calendar: fixedCalendar,
            language: .zhHans
        ))
        let existing = replacingGeneratedAt(
            in: candidate,
            with: candidate.generatedAt.addingTimeInterval(-60)
        )
        let events = LockedEventRecorder()
        let store = LockedSnapshotStore(
            loadResult: .available(existing),
            events: events
        )
        let reloader = RecordingTimelineReloader(events: events)
        let publisher = makePublisher(store: store, reloader: reloader)

        let result = await publisher.publish(states: validStates, language: .zhHans)

        #expect(result == .unchanged)
        #expect(events.values.isEmpty)
        #expect(store.loadCount == 1)
        #expect(store.saveCount == 0)
        #expect(reloader.kinds.isEmpty)
    }

    @Test("no valid provider stats preserve the old file")
    func noValidStatsPreservesExistingSnapshot() async {
        let states: [ProviderID: TokenStatsViewModel.ProviderState] = [
            .claude: .init(
                stats: nil,
                isLoading: false,
                errorMessage: nil,
                needsAuthorization: true
            ),
        ]
        let events = LockedEventRecorder()
        let store = LockedSnapshotStore(loadResult: .missing, events: events)
        let reloader = RecordingTimelineReloader(events: events)
        let publisher = makePublisher(store: store, reloader: reloader)

        let result = await publisher.publish(states: states, language: .zhHans)

        #expect(result == .skippedNoValidStats)
        #expect(store.loadCount == 0)
        #expect(store.saveCount == 0)
        #expect(events.values.isEmpty)
        #expect(reloader.kinds.isEmpty)
    }

    @Test("write failure never reloads a timeline")
    func writeFailureDoesNotReload() async {
        let events = LockedEventRecorder()
        let store = LockedSnapshotStore(
            loadResult: .missing,
            shouldFailSave: true,
            events: events
        )
        let reloader = RecordingTimelineReloader(events: events)
        let publisher = makePublisher(store: store, reloader: reloader)

        let result = await publisher.publish(states: validStates, language: .zhHans)

        #expect(result == .failed)
        #expect(events.values == ["save"])
        #expect(store.saveCount == 1)
        #expect(store.savedSnapshots.isEmpty)
        #expect(reloader.kinds.isEmpty)
    }

    @Test("a corrupt old snapshot is replaced by a valid candidate")
    func corruptOldSnapshotIsReplaced() async {
        let events = LockedEventRecorder()
        let store = LockedSnapshotStore(
            loadResult: .invalid(.corrupt),
            events: events
        )
        let reloader = RecordingTimelineReloader(events: events)
        let publisher = makePublisher(store: store, reloader: reloader)

        let result = await publisher.publish(states: validStates, language: .en)

        #expect(result == .published)
        #expect(events.values == [
            "save",
            "reload:\(WidgetSharedConfiguration.heatmapKind)",
            "reload:\(WidgetSharedConfiguration.hourlyLineKind)",
        ])
        #expect(store.loadCount == 1)
        #expect(store.saveCount == 1)
        #expect(store.savedSnapshots.first?.localizedText.todayUsageTitle == "Today's Usage")
    }

    private var fixedCalendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Shanghai")!
        calendar.firstWeekday = 2
        return calendar
    }

    private var fixedNow: Date {
        fixedCalendar.date(from: DateComponents(
            year: 2026,
            month: 7,
            day: 15,
            hour: 13,
            minute: 30
        ))!
    }

    private var validStates: [ProviderID: TokenStatsViewModel.ProviderState] {
        [
            .claude: .init(
                stats: .zero,
                isLoading: false,
                errorMessage: nil,
                needsAuthorization: false
            ),
        ]
    }

    private func makePublisher(
        store: LockedSnapshotStore,
        reloader: RecordingTimelineReloader
    ) -> WidgetSnapshotPublisher {
        let now = fixedNow
        let calendar = fixedCalendar
        return WidgetSnapshotPublisher(
            store: store,
            timelineReloader: reloader,
            now: { now },
            calendar: { calendar }
        )
    }

    private func replacingGeneratedAt(
        in snapshot: WidgetUsageSnapshot,
        with generatedAt: Date
    ) -> WidgetUsageSnapshot {
        WidgetUsageSnapshot(
            schemaVersion: snapshot.schemaVersion,
            generatedAt: generatedAt,
            localDayKey: snapshot.localDayKey,
            localizedText: snapshot.localizedText,
            heatmap: snapshot.heatmap,
            hourlyLine: snapshot.hourlyLine
        )
    }
}

private final class LockedEventRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var storedValues: [String] = []

    var values: [String] {
        withLock { storedValues }
    }

    func append(_ value: String) {
        withLock { storedValues.append(value) }
    }

    private func withLock<T>(_ body: () -> T) -> T {
        lock.lock()
        defer { lock.unlock() }
        return body()
    }
}

private final class LockedSnapshotStore: WidgetSnapshotStoring, @unchecked Sendable {
    private struct InjectedSaveError: Error {}

    private let lock = NSLock()
    private let loadResult: WidgetSnapshotReadResult
    private let shouldFailSave: Bool
    private let events: LockedEventRecorder
    private var storedLoadCount = 0
    private var storedSaveCount = 0
    private var storedSnapshots: [WidgetUsageSnapshot] = []

    init(
        loadResult: WidgetSnapshotReadResult,
        shouldFailSave: Bool = false,
        events: LockedEventRecorder
    ) {
        self.loadResult = loadResult
        self.shouldFailSave = shouldFailSave
        self.events = events
    }

    var loadCount: Int { withLock { storedLoadCount } }
    var saveCount: Int { withLock { storedSaveCount } }
    var savedSnapshots: [WidgetUsageSnapshot] { withLock { storedSnapshots } }

    func load() -> WidgetSnapshotReadResult {
        withLock { storedLoadCount += 1 }
        return loadResult
    }

    func save(_ snapshot: WidgetUsageSnapshot) throws {
        events.append("save")
        withLock { storedSaveCount += 1 }
        if shouldFailSave {
            throw InjectedSaveError()
        }
        withLock { storedSnapshots.append(snapshot) }
    }

    private func withLock<T>(_ body: () -> T) -> T {
        lock.lock()
        defer { lock.unlock() }
        return body()
    }
}

private final class RecordingTimelineReloader: WidgetTimelineReloading, @unchecked Sendable {
    private let lock = NSLock()
    private let events: LockedEventRecorder
    private var storedKinds: [String] = []

    init(events: LockedEventRecorder) {
        self.events = events
    }

    var kinds: [String] {
        lock.lock()
        defer { lock.unlock() }
        return storedKinds
    }

    func reloadTimelines(ofKind kind: String) {
        lock.lock()
        storedKinds.append(kind)
        lock.unlock()
        events.append("reload:\(kind)")
    }
}
