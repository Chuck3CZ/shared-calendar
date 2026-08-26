import SwiftUI

/// Keep the raw values in sync with ALLOWED_CATEGORIES in the backend
/// (backend/src/routes/events.js).
enum EventCategory: String, Codable, CaseIterable, Identifiable {
    case jidlo, zabava, kultura, konference, ostatni

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .jidlo: return "Jídlo a pití"
        case .zabava: return "Zábava"
        case .kultura: return "Kultura"
        case .konference: return "Konference a sraz"
        case .ostatni: return "Ostatní"
        }
    }

    var icon: String {
        switch self {
        case .jidlo: return "fork.knife"
        case .zabava: return "theatermasks.fill"
        case .kultura: return "building.columns.fill"
        case .konference: return "person.3.fill"
        case .ostatni: return "calendar"
        }
    }

    var color: Color {
        switch self {
        case .jidlo: return .orange
        case .zabava: return .purple
        case .kultura: return .indigo
        case .konference: return .teal
        case .ostatni: return .gray
        }
    }

    /// Falls back to `.ostatni` for anything unrecognized (an older client,
    /// an event stored under a category slug that was later retired, or a
    /// category added on the server this build doesn't know about yet)
    /// instead of failing to decode the whole event.
    init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = EventCategory(rawValue: raw) ?? .ostatni
    }
}
