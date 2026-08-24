import Foundation

/// Handles universal links like https://sc.gabrhelovi.cz/event/<id>, and
/// tapping a push notification (widgetURL and APNs payload data both point
/// here). The fetched event is published so any view (the tabs live in
/// ContentView, but a link can arrive while the user is anywhere in the
/// app) can present its detail as a sheet.
@MainActor
final class DeepLinkRouter: ObservableObject {
    static let shared = DeepLinkRouter()

    @Published var pendingEvent: Event?
    @Published var showingAdminBugReports = false

    private init() {}

    func handle(url: URL) {
        let components = url.pathComponents // ["/", "event", "<id>"]
        guard components.count >= 3, components[1] == "event" else { return }
        handle(eventId: components[2])
    }

    func handle(eventId: String) {
        Task {
            pendingEvent = try? await APIClient.shared.fetchEvent(id: eventId)
        }
    }

    /// Routes a tapped push notification to the right screen. The custom
    /// fields (event_id, type) are spread at the top level of the APNs
    /// payload by the backend (see apns.js), landing directly in userInfo
    /// alongside "aps" — not nested under a "data" key.
    func handle(pushUserInfo: [AnyHashable: Any]) {
        if let eventId = pushUserInfo["event_id"] as? String {
            handle(eventId: eventId)
        } else if pushUserInfo["type"] as? String == "bug_report" {
            showingAdminBugReports = true
        }
    }
}
