import Foundation
import UIKit
import UserNotifications

@MainActor
final class AuthManager: ObservableObject {
    static let shared = AuthManager()

    @Published private(set) var session: SessionInfo?

    var isSignedIn: Bool { session != nil }

    private init() {
        session = KeychainSession.load()
        NotificationCenter.default.addObserver(forName: .sessionExpired, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in
                self?.signOut()
            }
        }
    }

    func signIn(identityToken: String, fullName: String?) async throws {
        let response = try await APIClient.shared.authenticateWithApple(identityToken: identityToken, fullName: fullName)
        let info = SessionInfo(token: response.token, profile: response.user)
        KeychainSession.save(info)
        session = info
        if let existingToken = PushTokenStore.current {
            try? await APIClient.shared.registerDeviceToken(existingToken)
        }
        await registerForPushNotifications()
    }

    /// Asks for notification permission (a no-op if already answered) and,
    /// once granted, triggers APNs registration. The resulting device token
    /// arrives asynchronously in AppDelegate and gets sent to the backend
    /// from there — it isn't available yet at the point this returns.
    /// Called after every fresh sign-in, and also on every launch while
    /// already signed in (registerForRemoteNotifications should be called
    /// on every launch per Apple's guidance, and an existing session from
    /// before push support shipped never got a first chance to ask).
    func registerForPushNotifications() async {
        let granted = (try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge])) ?? false
        print("[push] notification permission granted: \(granted)")
        guard granted else { return }
        UIApplication.shared.registerForRemoteNotifications()
    }

    func signOut() {
        if let token = session?.token {
            Task { try? await APIClient.shared.revokeSession(token: token) }
        }
        KeychainSession.clear()
        session = nil
    }

    /// Re-fetches the profile (role may have changed, e.g. a verification
    /// request got approved) and keeps the Keychain copy in sync.
    func refreshProfile() async {
        guard let current = session, let profile = try? await APIClient.shared.fetchMe() else { return }
        apply(profile)
    }

    private func apply(_ profile: UserProfile) {
        guard let current = session else { return }
        let updated = SessionInfo(token: current.token, profile: profile)
        guard updated != current else { return }
        KeychainSession.save(updated)
        session = updated
    }
}
