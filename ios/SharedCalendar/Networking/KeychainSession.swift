import Foundation
import Security

struct SessionInfo: Codable, Equatable {
    var token: String
    var profile: UserProfile
}

/// Persists the signed-in session (token + profile) in the Keychain,
/// which survives app reinstalls unlike UserDefaults and is the right
/// place for a credential. Reads/writes are synchronous and cheap
/// enough to call directly from APIClient on every authenticated request.
enum KeychainSession {
    private static let service = "cz.gabrhelovi.sharedcalendar.session"
    private static let account = "current"

    static func load() -> SessionInfo? {
        var query = baseQuery()
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess, let data = result as? Data else { return nil }
        return try? JSONDecoder().decode(SessionInfo.self, from: data)
    }

    static func save(_ session: SessionInfo) {
        guard let data = try? JSONEncoder().encode(session) else { return }
        SecItemDelete(baseQuery() as CFDictionary)

        var addQuery = baseQuery()
        addQuery[kSecValueData as String] = data
        addQuery[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        SecItemAdd(addQuery as CFDictionary, nil)
    }

    static func clear() {
        SecItemDelete(baseQuery() as CFDictionary)
    }

    private static func baseQuery() -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
    }
}
