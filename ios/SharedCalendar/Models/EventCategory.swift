import SwiftUI

/// Keep the raw values in sync with ALLOWED_CATEGORIES in the backend
/// (backend/src/routes/events.js).
enum EventCategory: String, Codable, CaseIterable, Identifiable {
    case rodina, prace, sport, oslava, cestovani, ostatni

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .rodina: return "Rodina"
        case .prace: return "Práce"
        case .sport: return "Sport"
        case .oslava: return "Oslava"
        case .cestovani: return "Cestování"
        case .ostatni: return "Ostatní"
        }
    }

    var icon: String {
        switch self {
        case .rodina: return "house.fill"
        case .prace: return "briefcase.fill"
        case .sport: return "figure.run"
        case .oslava: return "party.popper.fill"
        case .cestovani: return "airplane"
        case .ostatni: return "calendar"
        }
    }

    var color: Color {
        switch self {
        case .rodina: return .pink
        case .prace: return .blue
        case .sport: return .green
        case .oslava: return .purple
        case .cestovani: return .orange
        case .ostatni: return .gray
        }
    }

    /// Falls back to `.ostatni` for anything unrecognized (an older client,
    /// or a category added on the server this build doesn't know about yet)
    /// instead of failing to decode the whole event.
    init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = EventCategory(rawValue: raw) ?? .ostatni
    }
}
