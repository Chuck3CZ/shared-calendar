import Foundation

enum APIError: Error {
    case server(String)
    case invalidResponse
}

final class APIClient {
    static let shared = APIClient()

    /// Change to your Cloudflare Tunnel / NAS URL once deployed.
    var baseURL = URL(string: "http://localhost:3000")!

    private let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()

    private let encoder = JSONEncoder()

    private func request(_ path: String, method: String = "GET", body: Data? = nil, authenticated: Bool = false) async throws -> Data {
        var request = URLRequest(url: baseURL.appendingPathComponent(path))
        request.httpMethod = method
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if authenticated {
            request.setValue(ClientIdentity.current, forHTTPHeaderField: "X-Client-Id")
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
        let path = "events?from=\(formatter.string(from: from))&to=\(formatter.string(from: to))"
        let data = try await request(path)
        return try decoder.decode([Event].self, from: data)
    }

    func fetchPending() async throws -> [Event] {
        let data = try await request("events/pending", authenticated: true)
        return try decoder.decode([Event].self, from: data)
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
