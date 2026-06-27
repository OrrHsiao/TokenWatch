import Foundation
import WidgetKit

struct TokenWatchWidgetEntry: TimelineEntry {
    let date: Date
    let snapshot: TokenWatchWidgetSnapshot
}

struct TokenWatchWidgetTimelineProvider: TimelineProvider {
    var store = TokenWatchWidgetSnapshotStore()

    func placeholder(in context: Context) -> TokenWatchWidgetEntry {
        TokenWatchWidgetEntry(date: Date(), snapshot: .sample())
    }

    func getSnapshot(in context: Context, completion: @escaping (TokenWatchWidgetEntry) -> Void) {
        let snapshot = store.read() ?? TokenWatchWidgetSnapshot.empty(status: .waitingForRefresh)
        completion(TokenWatchWidgetEntry(date: Date(), snapshot: snapshot))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<TokenWatchWidgetEntry>) -> Void) {
        let now = Date()
        let snapshot = store.read() ?? TokenWatchWidgetSnapshot.empty(generatedAt: now, status: .waitingForRefresh)
        let entry = TokenWatchWidgetEntry(date: now, snapshot: snapshot)
        let nextRefresh = Calendar.current.date(byAdding: .minute, value: 30, to: now) ?? now.addingTimeInterval(1_800)
        completion(Timeline(entries: [entry], policy: .after(nextRefresh)))
    }
}
