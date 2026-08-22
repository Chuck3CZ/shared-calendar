import Foundation

@MainActor
final class AuthManager: ObservableObject {
    static let shared = AuthManager()

    @Published private(set) var session: SessionInfo?

    var isSignedIn: Bool { session != nil }

    private init() {
        session = KeychainSession.load()
        NotificationCenter.default.addObserver(forName: .sessionExpired, object: nil, queue: .main) { [weak self] _ in
            self?.signOut()
        }
    }

    func signIn(identityToken: String, fullName: String?) async throws {
        let response = try await APIClient.shared.authenticateWithApple(identityToken: identityToken, fullName: fullName)
        let info = SessionInfo(token: response.token, profile: response.user)
        KeychainSession.save(info)
        session = info
    }

    func signOut() {
        KeychainSession.clear()
        session = nil
    }

    /// Re-fetches the profile (role may have changed, e.g. a verification
    /// request got approved) and keeps the Keychain copy in sync.
    func refreshProfile() async {
        guard let current = session, let profile = try? await APIClient.shared.fetchMe() else { return }
        let updated = SessionInfo(token: current.token, profile: profile)
        guard updated != current else { return }
        KeychainSession.save(updated)
        session = updated
    }
}
