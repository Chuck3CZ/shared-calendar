import Foundation

/// Phase 1 stand-in for Sign in with Apple: a random id generated once
/// per install and sent as X-Client-Id. Phase 2 replaces this with a
/// real Apple user identifier.
enum ClientIdentity {
    private static let key = "shared-calendar.client-id"

    static var current: String {
        if let existing = UserDefaults.standard.string(forKey: key) {
            return existing
        }
        let generated = UUID().uuidString
        UserDefaults.standard.set(generated, forKey: key)
        return generated
    }
}
