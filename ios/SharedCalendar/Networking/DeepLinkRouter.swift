import Foundation

/// Handles universal links like https://sc.gabrhelovi.cz/event/<id>. The
/// fetched event is published so any view (the tabs live in ContentView,
/// but a link can arrive while the user is anywhere in the app) can present
/// its detail as a sheet.
@MainActor
final class DeepLinkRouter: ObservableObject {
    static let shared = DeepLinkRouter()

    @Published var pendingEvent: Event?

    private init() {}

    func handle(url: URL) {
        let components = url.pathComponents // ["/", "event", "<id>"]
        guard components.count >= 3, components[1] == "event" else { return }
        let eventId = components[2]
        Task {
            pendingEvent = try? await APIClient.shared.fetchEvent(id: eventId)
        }
    }
}
