import Foundation

enum APIError: Error {
    case server(String)
    case invalidResponse
    case notAuthenticated
    case invalidRequest
}

extension APIError: LocalizedError {
    var errorDescription: String? {
        switch self {
        case .server(let message): return message
        case .invalidResponse: return "Neplatná odpověď serveru."
        case .notAuthenticated: return "Nejsi přihlášený."
        case .invalidRequest: return "Neplatný požadavek."
        }
    }
}

private struct ServerErrorBody: Decodable {
    let error: String?
    let message: String?
}

extension Notification.Name {
    /// Posted when a request comes back 401 with a session token attached,
    /// meaning the server no longer recognizes it (revoked/expired).
    static let sessionExpired = Notification.Name("sessionExpired")
}

extension Error {
    /// True when this error is just a superseded/cancelled request (e.g. an
    /// incomplete pull-to-refresh gesture, or a reload triggered again before
    /// the previous one finished) rather than a real failure worth showing.
    var isCancellation: Bool {
        if self is CancellationError { return true }
        if let urlError = self as? URLError, urlError.code == .cancelled { return true }
        return false
    }
}

final class APIClient {
    static let shared = APIClient()

    var baseURL = URL(string: "https://sc.gabrhelovi.cz")!

    private let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        // Plain .iso8601 has no fractional-seconds support at all — one date
        // string like "...12:00:00.500Z" would fail to decode and take the
        // whole response down with it. Try with fractional seconds first,
        // fall back to without.
        let withFractional = ISO8601DateFormatter()
        withFractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let standard = ISO8601DateFormatter()
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let string = try container.decode(String.self)
            if let date = withFractional.date(from: string) ?? standard.date(from: string) {
                return date
            }
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Invalid ISO8601 date: \(string)")
        }
        return decoder
    }()

    private let encoder = JSONEncoder()

    private func request(_ path: String, queryItems: [URLQueryItem] = [], method: String = "GET", body: Data? = nil, authenticated: Bool = false, optionalAuth: Bool = false, bearerOverride: String? = nil, extraHeaders: [String: String] = [:]) async throws -> Data {
        guard var components = URLComponents(url: baseURL.appendingPathComponent(path), resolvingAgainstBaseURL: true) else {
            throw APIError.invalidRequest
        }
        if !queryItems.isEmpty {
            components.queryItems = queryItems
        }
        guard let url = components.url else {
            throw APIError.invalidRequest
        }
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let bearerOverride {
            request.setValue("Bearer \(bearerOverride)", forHTTPHeaderField: "Authorization")
        } else if authenticated {
            guard let token = KeychainSession.load()?.token else {
                throw APIError.notAuthenticated
            }
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        } else if optionalAuth, let token = KeychainSession.load()?.token {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        for (field, value) in extraHeaders {
            request.setValue(value, forHTTPHeaderField: field)
        }
        request.httpBody = body

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw APIError.invalidResponse }
        guard (200..<300).contains(http.statusCode) else {
            if http.statusCode == 401 && authenticated {
                NotificationCenter.default.post(name: .sessionExpired, object: nil)
            }
            let serverError = try? JSONDecoder().decode(ServerErrorBody.self, from: data)
            let message = serverError?.message ?? serverError?.error
                ?? String(data: data, encoding: .utf8) ?? "HTTP \(http.statusCode)"
            throw APIError.server(message)
        }
        return data
    }

    /// Revokes a session server-side. Takes the token explicitly rather than
    /// reading it from Keychain, since this is called right as sign-out is
    /// clearing that same Keychain entry.
    func revokeSession(token: String) async throws {
        _ = try await request("auth/session", method: "DELETE", bearerOverride: token)
    }

    func authenticateWithApple(identityToken: String, fullName: String?, nonce: String) async throws -> AuthResponse {
        struct Payload: Codable {
            let identityToken: String
            let fullName: String?
            let nonce: String
        }
        let body = try encoder.encode(Payload(identityToken: identityToken, fullName: fullName, nonce: nonce))
        let data = try await request("auth/apple", method: "POST", body: body)
        return try decoder.decode(AuthResponse.self, from: data)
    }

    func fetchVerificationStatus() async throws -> VerificationRequest? {
        let data = try await request("me/verification-request", authenticated: true)
        if data.isEmpty || String(data: data, encoding: .utf8) == "null" { return nil }
        return try decoder.decode(VerificationRequest.self, from: data)
    }

    @discardableResult
    func requestVerification(reason: String?) async throws -> VerificationRequest {
        let body = try encoder.encode(["reason": reason])
        let data = try await request("me/verification-request", method: "POST", body: body, authenticated: true)
        return try decoder.decode(VerificationRequest.self, from: data)
    }

    func fetchPendingVerificationRequests() async throws -> [VerificationRequest] {
        let data = try await request("admin/verification-requests", authenticated: true)
        return try decoder.decode([VerificationRequest].self, from: data)
    }

    func approveVerificationRequest(id: String) async throws {
        _ = try await request("admin/verification-requests/\(id)/approve", method: "POST", authenticated: true)
    }

    func rejectVerificationRequest(id: String) async throws {
        _ = try await request("admin/verification-requests/\(id)/reject", method: "POST", authenticated: true)
    }

    func fetchEvent(id: String) async throws -> Event {
        let data = try await request("events/\(id)", optionalAuth: true)
        return try decoder.decode(Event.self, from: data)
    }

    func fetchEvents(from: Date, to: Date) async throws -> [Event] {
        let formatter = ISO8601DateFormatter()
        let queryItems = [
            URLQueryItem(name: "from", value: formatter.string(from: from)),
            URLQueryItem(name: "to", value: formatter.string(from: to)),
        ]
        let data = try await request("events", queryItems: queryItems, optionalAuth: true)
        return try decoder.decode([Event].self, from: data)
    }

    func fetchPending(viewAsMember: Bool = false) async throws -> [Event] {
        let headers = viewAsMember ? ["X-View-As": "member"] : [:]
        let data = try await request("events/pending", authenticated: true, extraHeaders: headers)
        return try decoder.decode([Event].self, from: data)
    }

    /// Every visible event regardless of a prior swipe response, so it can be re-decided.
    func fetchReview(viewAsMember: Bool = false) async throws -> [Event] {
        let headers = viewAsMember ? ["X-View-As": "member"] : [:]
        let data = try await request("events/review", authenticated: true, extraHeaders: headers)
        return try decoder.decode([Event].self, from: data)
    }

    func fetchNotifications() async throws -> [AppNotification] {
        let data = try await request("me/notifications", authenticated: true)
        return try decoder.decode([AppNotification].self, from: data)
    }

    func markNotificationsRead() async throws {
        _ = try await request("me/notifications/read", method: "POST", authenticated: true)
    }

    func deleteNotification(id: String) async throws {
        _ = try await request("me/notifications/\(id)", method: "DELETE", authenticated: true)
    }

    func clearNotifications() async throws {
        _ = try await request("me/notifications", method: "DELETE", authenticated: true)
    }

    func submitBugReport(_ payload: BugReportPayload) async throws {
        let body = try encoder.encode(payload)
        _ = try await request("bug-reports", method: "POST", body: body, optionalAuth: true)
    }

    func fetchAllUsers() async throws -> [AdminUser] {
        let data = try await request("admin/users", authenticated: true)
        return try decoder.decode([AdminUser].self, from: data)
    }

    @discardableResult
    func setUserRole(id: String, role: String) async throws -> AdminUser {
        let body = try encoder.encode(["role": role])
        let data = try await request("admin/users/\(id)/role", method: "PATCH", body: body, authenticated: true)
        return try decoder.decode(AdminUser.self, from: data)
    }

    func fetchBugReports() async throws -> [BugReport] {
        let data = try await request("admin/bug-reports", authenticated: true)
        return try decoder.decode([BugReport].self, from: data)
    }

    func reportEvent(id: String, reason: String) async throws {
        let body = try encoder.encode(EventReportPayload(reason: reason))
        _ = try await request("events/\(id)/report", method: "POST", body: body, authenticated: true)
    }

    func fetchEventReports() async throws -> [EventReport] {
        let data = try await request("admin/event-reports", authenticated: true)
        return try decoder.decode([EventReport].self, from: data)
    }

    /// Permanently deletes the signed-in account and everything tied to it.
    /// The caller is still responsible for the local sign-out afterward.
    func deleteAccount() async throws {
        _ = try await request("me", method: "DELETE", authenticated: true)
    }

    func fetchMe() async throws -> UserProfile {
        let data = try await request("me", authenticated: true)
        return try decoder.decode(UserProfile.self, from: data)
    }

    func registerDeviceToken(_ token: String) async throws {
        let body = try encoder.encode(["token": token])
        _ = try await request("me/device-token", method: "POST", body: body, authenticated: true)
    }

    func fetchCreatedByMe() async throws -> [Event] {
        let data = try await request("me/created", authenticated: true)
        return try decoder.decode([Event].self, from: data)
    }

    func fetchMyResponses() async throws -> [RespondedEvent] {
        let data = try await request("me/responses", authenticated: true)
        return try decoder.decode([RespondedEvent].self, from: data)
    }

    func createEvent(_ payload: NewEventPayload) async throws -> Event {
        let body = try encoder.encode(payload)
        let data = try await request("events", method: "POST", body: body, authenticated: true)
        return try decoder.decode(Event.self, from: data)
    }

    func updateEvent(id: String, _ payload: NewEventPayload) async throws -> Event {
        let body = try encoder.encode(payload)
        let data = try await request("events/\(id)", method: "PATCH", body: body, authenticated: true)
        return try decoder.decode(Event.self, from: data)
    }

    func fetchReminders(eventId: String) async throws -> ReminderSettings {
        let data = try await request("events/\(eventId)/reminders", authenticated: true)
        return try decoder.decode(ReminderSettings.self, from: data)
    }

    @discardableResult
    func setReminders(eventId: String, minutes: [Int]) async throws -> ReminderSettings {
        let body = try encoder.encode(["minutes": minutes])
        let data = try await request("events/\(eventId)/reminders", method: "PUT", body: body, authenticated: true)
        return try decoder.decode(ReminderSettings.self, from: data)
    }

    func deleteEvent(id: String) async throws {
        _ = try await request("events/\(id)", method: "DELETE", authenticated: true)
    }

    @discardableResult
    func respond(eventId: String, status: String) async throws -> EventResponse {
        let body = try encoder.encode(["status": status])
        let data = try await request("events/\(eventId)/response", method: "POST", body: body, authenticated: true)
        return try decoder.decode(EventResponse.self, from: data)
    }
}
