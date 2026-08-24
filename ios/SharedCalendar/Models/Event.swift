import Foundation

struct Event: Codable, Identifiable, Equatable {
    let id: String
    let ownerId: String
    let ownerName: String?
    let ownerRole: String?
    let title: String
    let description: String?
    let location: String?
    let startAt: Date
    let endAt: Date?
    let createdAt: String
    /// "accepted" / "rejected" / nil (no response yet, or not signed in)
    let myStatus: String?
    let latitude: Double?
    let longitude: Double?
    /// How many people (besides a pending count of nobody) have swiped "accepted".
    let acceptedCount: Int?

    enum CodingKeys: String, CodingKey {
        case id
        case ownerId = "owner_id"
        case ownerName = "owner_name"
        case ownerRole = "owner_role"
        case title
        case description
        case location
        case startAt = "start_at"
        case endAt = "end_at"
        case createdAt = "created_at"
        case myStatus = "my_status"
        case latitude
        case longitude
        case acceptedCount = "accepted_count"
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

struct UserProfile: Codable, Equatable {
    let id: String
    let appleUserId: String?
    let displayName: String?
    let role: String
    let createdAt: String

    enum CodingKeys: String, CodingKey {
        case id
        case appleUserId = "apple_user_id"
        case displayName = "display_name"
        case role
        case createdAt = "created_at"
    }
}

struct AuthResponse: Codable {
    let token: String
    let user: UserProfile
}

struct VerificationRequest: Codable, Identifiable {
    let id: String
    let userId: String
    let reason: String?
    let status: String
    let createdAt: String
    let userDisplayName: String?

    enum CodingKeys: String, CodingKey {
        case id
        case userId = "user_id"
        case reason
        case status
        case createdAt = "created_at"
        case userDisplayName = "user_display_name"
    }
}

struct RespondedEvent: Codable, Identifiable {
    let id: String
    let ownerId: String
    let ownerName: String?
    let title: String
    let description: String?
    let location: String?
    let startAt: Date
    let endAt: Date?
    let status: String

    enum CodingKeys: String, CodingKey {
        case id
        case ownerId = "owner_id"
        case ownerName = "owner_name"
        case title, description, location
        case startAt = "start_at"
        case endAt = "end_at"
        case status
    }
}

struct ReminderSettings: Codable {
    let minutes: [Int]
}

struct AppNotification: Codable, Identifiable {
    let id: String
    let title: String
    let body: String
    let eventId: String?
    let createdAt: String
    let readAt: String?

    enum CodingKeys: String, CodingKey {
        case id, title, body
        case eventId = "event_id"
        case createdAt = "created_at"
        case readAt = "read_at"
    }
}

struct AdminUser: Codable, Identifiable {
    let id: String
    let displayName: String?
    let role: String
    let createdAt: String
    let latestVerificationStatus: String?

    enum CodingKeys: String, CodingKey {
        case id
        case displayName = "display_name"
        case role
        case createdAt = "created_at"
        case latestVerificationStatus = "latest_verification_status"
    }
}

struct BugReport: Codable, Identifiable {
    let id: String
    let userId: String?
    let userDisplayName: String?
    let description: String
    let appVersion: String?
    let osVersion: String?
    let deviceModel: String?
    let createdAt: String
    let githubIssueNumber: Int?
    let githubIssueUrl: String?

    enum CodingKeys: String, CodingKey {
        case id
        case userId = "user_id"
        case userDisplayName = "user_display_name"
        case description
        case appVersion = "app_version"
        case osVersion = "os_version"
        case deviceModel = "device_model"
        case createdAt = "created_at"
        case githubIssueNumber = "github_issue_number"
        case githubIssueUrl = "github_issue_url"
    }
}

struct EventReportPayload: Codable {
    let reason: String
}

struct EventReport: Codable, Identifiable {
    let id: String
    let eventId: String
    let reporterId: String?
    let reporterDisplayName: String?
    let eventTitle: String
    let eventDeletedAt: String?
    let reason: String
    let createdAt: String

    enum CodingKeys: String, CodingKey {
        case id
        case eventId = "event_id"
        case reporterId = "reporter_id"
        case reporterDisplayName = "reporter_display_name"
        case eventTitle = "event_title"
        case eventDeletedAt = "event_deleted_at"
        case reason
        case createdAt = "created_at"
    }
}

struct BugReportPayload: Codable {
    let description: String
    let appVersion: String?
    let osVersion: String?
    let deviceModel: String?

    enum CodingKeys: String, CodingKey {
        case description
        case appVersion = "app_version"
        case osVersion = "os_version"
        case deviceModel = "device_model"
    }
}

struct NewEventPayload: Codable {
    let title: String
    let description: String?
    let location: String?
    let startAt: String
    let endAt: String?
    let latitude: Double?
    let longitude: Double?

    enum CodingKeys: String, CodingKey {
        case title, description, location
        case startAt = "start_at"
        case endAt = "end_at"
        case latitude, longitude
    }
}
