import Foundation

struct Event: Codable, Identifiable, Equatable {
    let id: String
    let ownerId: String
    let ownerName: String?
    let title: String
    let description: String?
    let location: String?
    let startAt: Date
    let endAt: Date?
    let createdAt: String

    enum CodingKeys: String, CodingKey {
        case id
        case ownerId = "owner_id"
        case ownerName = "owner_name"
        case title
        case description
        case location
        case startAt = "start_at"
        case endAt = "end_at"
        case createdAt = "created_at"
    }
}

struct EventResponse: Codable {
    let eventId: String
    let status: String

    enum CodingKeys: String, CodingKey {
        case eventId = "event_id"
        case status
    }
}

struct NewEventPayload: Codable {
    let title: String
    let description: String?
    let location: String?
    let startAt: String
    let endAt: String?

    enum CodingKeys: String, CodingKey {
        case title, description, location
        case startAt = "start_at"
        case endAt = "end_at"
    }
}
