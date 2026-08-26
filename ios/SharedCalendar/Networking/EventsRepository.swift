import Foundation

/// Single source of truth for events, shared by CalendarView and
/// UpcomingView so switching tabs doesn't trigger its own network fetch.
/// Fetched data is cached to disk and reused across app launches; a fresh
/// fetch only happens when the requested date range isn't covered yet, when
/// the cache has crossed the next noon/midnight checkpoint since it was last
/// fetched, or when the caller explicitly asks for one (pull-to-refresh, or
/// right after the user creates/edits/deletes an event).
@MainActor
final class EventsRepository: ObservableObject {
    static let shared = EventsRepository()

    @Published private(set) var events: [Event] = []
    private(set) var loadedFrom: Date?
    private(set) var loadedTo: Date?
    private(set) var lastFetchedAt: Date?

    private struct CachePayload: Codable {
        let events: [Event]
        let loadedFrom: Date
        let loadedTo: Date
        let fetchedAt: Date
    }

    private let cacheURL: URL = {
        let dir = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        return dir.appendingPathComponent("events_cache.json")
    }()

    private init() {
        loadFromDisk()
    }

    /// Fetches from the server only if the cached range doesn't cover
    /// [from, to], or the cache is past its next noon/midnight checkpoint,
    /// or `forceRefresh` is set. The actual fetch always widens to the
    /// calendar's own -1/+3 month window so both tabs end up sharing one cache.
    func ensureLoaded(from: Date, to: Date, forceRefresh: Bool = false) async throws {
        guard forceRefresh || !covers(from: from, to: to) || isStale() else { return }

        let calendar = Calendar.current
        let defaultFrom = calendar.date(byAdding: .month, value: -1, to: Date()) ?? from
        let defaultTo = calendar.date(byAdding: .month, value: 3, to: Date()) ?? to
        let widenedFrom = min(from, defaultFrom)
        let widenedTo = max(to, defaultTo)

        let fetched = try await APIClient.shared.fetchEvents(from: widenedFrom, to: widenedTo)
        events = fetched
        loadedFrom = widenedFrom
        loadedTo = widenedTo
        lastFetchedAt = Date()
        saveToDisk()
        WidgetDataStore.update(from: events)
    }

    private func covers(from: Date, to: Date) -> Bool {
        guard let loadedFrom, let loadedTo else { return false }
        return loadedFrom <= from && loadedTo >= to
    }

    private func isStale(for now: Date = Date()) -> Bool {
        guard let lastFetchedAt else { return true }
        return lastFetchedAt < mostRecentCheckpoint(before: now)
    }

    /// The most recent of today's 00:00/12:00 checkpoints that has already passed.
    private func mostRecentCheckpoint(before now: Date) -> Date {
        let calendar = Calendar.current
        let startOfDay = calendar.startOfDay(for: now)
        let noon = calendar.date(byAdding: .hour, value: 12, to: startOfDay) ?? startOfDay
        return now >= noon ? noon : startOfDay
    }

    private func loadFromDisk() {
        guard let data = try? Data(contentsOf: cacheURL),
              let payload = try? JSONDecoder().decode(CachePayload.self, from: data) else { return }
        events = payload.events
        loadedFrom = payload.loadedFrom
        loadedTo = payload.loadedTo
        lastFetchedAt = payload.fetchedAt
    }

    private func saveToDisk() {
        guard let loadedFrom, let loadedTo, let lastFetchedAt else { return }
        let payload = CachePayload(events: events, loadedFrom: loadedFrom, loadedTo: loadedTo, fetchedAt: lastFetchedAt)
        guard let data = try? JSONEncoder().encode(payload) else { return }
        try? data.write(to: cacheURL, options: .atomic)
    }
}
