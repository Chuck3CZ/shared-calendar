import Foundation

enum APIError: Error {
    case server(String)
    case invalidResponse
}

final class APIClient {
    static let shared = APIClient()

    var baseURL = URL(string: "https://sc.gabrhelovi.cz")!

    private let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()

    private let encoder = JSONEncoder()

    private func request(_ path: String, queryItems: [URLQueryItem] = [], method: String = "GET", body: Data? = nil, authenticated: Bool = false, extraHeaders: [String: String] = [:]) async throws -> Data {
        var components = URLComponents(url: baseURL.appendingPathComponent(path), resolvingAgainstBaseURL: true)!
        if !queryItems.isEmpty {
            components.queryItems = queryItems
        }
        var request = URLRequest(url: components.url!)
        request.httpMethod = method
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if authenticated {
            request.setValue(ClientIdentity.current, forHTTPHeaderField: "X-Client-Id")
        }
        for (field, value) in extraHeaders {
            request.setValue(value, forHTTPHeaderField: field)
        }
        request.httpBody = body

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw APIError.invalidResponse }
        guard (200..<300).contains(http.statusCode) else {
            let message = String(data: data, encoding: .utf8) ?? "HTTP \(http.statusCode)"
            throw APIError.server(message)
        }
        return data
    }

    func fetchEvents(from: Date, to: Date) async throws -> [Event] {
        let formatter = ISO8601DateFormatter()
        let queryItems = [
            URLQueryItem(name: "from", value: formatter.string(from: from)),
            URLQueryItem(name: "to", value: formatter.string(from: to)),
        ]
        let data = try await request("events", queryItems: queryItems)
        return try decoder.decode([Event].self, from: data)
    }

    func fetchPending(viewAsMember: Bool = false) async throws -> [Event] {
        let headers = viewAsMember ? ["X-View-As": "member"] : [:]
        let data = try await request("events/pending", authenticated: true, extraHeaders: headers)
        return try decoder.decode([Event].self, from: data)
    }

    func fetchMe() async throws -> UserProfile {
        let data = try await request("me", authenticated: true)
        return try decoder.decode(UserProfile.self, from: data)
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

    @discardableResult
    func respond(eventId: String, status: String) async throws -> EventResponse {
        let body = try encoder.encode(["status": status])
        let data = try await request("events/\(eventId)/response", method: "POST", body: body, authenticated: true)
        return try decoder.decode(EventResponse.self, from: data)
    }
}
