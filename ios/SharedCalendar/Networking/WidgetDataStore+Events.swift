import Foundation
import WidgetKit

/// Not part of the widget extension's sources (unlike WidgetDataStore.swift
/// itself) — this is where the `Event` dependency lives, kept out of the
/// extension target to avoid pulling in the rest of the app's model layer.
extension WidgetDataStore {
    /// Picks the soonest event the user is attending and not yet over, and
    /// stores it for the widget. Clears the widget back to its empty state
    /// if there's no such event.
    static func update(from events: [Event]) {
        let now = Date()
        let next = events
            .filter { $0.myStatus == "accepted" && $0.startAt >= now }
            .min { $0.startAt < $1.startAt }

        guard let next else {
            clear()
            return
        }
        let snapshot = UpcomingEventSnapshot(title: next.title, location: next.location, startAt: next.startAt)
        guard let data = try? JSONEncoder().encode(snapshot) else { return }
        defaults?.set(data, forKey: key)
        WidgetCenter.shared.reloadAllTimelines()
    }
}
