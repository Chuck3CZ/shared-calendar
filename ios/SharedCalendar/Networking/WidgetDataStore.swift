import Foundation
import WidgetKit

/// The widget extension can't make its own network calls on a useful
/// schedule (Apple budgets timeline refreshes tightly and discourages
/// network fetches from the provider), so instead the main app writes a
/// small snapshot of "what to show" into an App Group container every time
/// it has fresh data, and the widget just reads that back.
struct UpcomingEventSnapshot: Codable {
    let id: String
    let title: String
    let location: String?
    let startAt: Date
}

/// Shared with the widget extension target (see project.yml) — keep this
/// file free of dependencies on the rest of the app's types (like `Event`)
/// since the extension only compiles this one file from the main target.
enum WidgetDataStore {
    static let appGroupId = "group.cz.gabrhelovi.sharedcalendar"
    static let key = "upcomingEventSnapshot"

    static var defaults: UserDefaults? {
        UserDefaults(suiteName: appGroupId)
    }

    static func clear() {
        defaults?.removeObject(forKey: key)
        WidgetCenter.shared.reloadAllTimelines()
    }

    static func load() -> UpcomingEventSnapshot? {
        guard let data = defaults?.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(UpcomingEventSnapshot.self, from: data)
    }
}
