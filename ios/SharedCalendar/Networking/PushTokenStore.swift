import Foundation

/// Holds the device's current APNs token so it can be (re-)registered
/// with the backend once we also have a signed-in session — the two
/// arrive independently and in no particular order.
enum PushTokenStore {
    static var current: String?
}
