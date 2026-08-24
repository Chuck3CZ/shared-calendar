import Foundation

/// Parses the plain "yyyy-MM-dd HH:mm:ss" (UTC) timestamps SQLite's
/// datetime('now') produces — used for fields kept as String rather than
/// Date (created_at, etc.), since that format isn't real ISO 8601 and can't
/// go through APIClient's date-decoding strategy.
///
/// Locale matters here even with a fully fixed format string: without
/// en_US_POSIX, a device set to a non-Gregorian calendar (Buddhist,
/// Japanese, ...) can fail to parse this or silently produce the wrong
/// date — a well-documented DateFormatter pitfall.
enum ServerDate {
    static let formatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        formatter.timeZone = TimeZone(identifier: "UTC")
        formatter.locale = Locale(identifier: "en_US_POSIX")
        return formatter
    }()

    static func relative(_ raw: String) -> String {
        guard let date = formatter.date(from: raw) else { return raw }
        return date.formatted(.relative(presentation: .named))
    }
}
