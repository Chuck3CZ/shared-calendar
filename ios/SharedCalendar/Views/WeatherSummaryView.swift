import SwiftUI
import WeatherKit
import CoreLocation

/// Shows the forecast closest to an event's start time at its location.
/// WeatherKit's hourly forecast only reaches a limited number of days out,
/// so far-future events just show "not available yet" rather than an error.
struct WeatherSummaryView: View {
    let latitude: Double
    let longitude: Double
    let date: Date

    @State private var hour: HourWeather?
    @State private var isLoading = true

    var body: some View {
        LabeledContent("Počasí") {
            if let hour {
                HStack(spacing: 6) {
                    Image(systemName: hour.symbolName)
                    Text("\(hour.temperature.formatted(.measurement(width: .abbreviated, numberFormatStyle: .number.precision(.fractionLength(0))))) · \(hour.condition.description)")
                }
            } else if isLoading {
                ProgressView()
            } else {
                Text("Zatím není k dispozici")
                    .foregroundStyle(.secondary)
            }
        }
        .task { await load() }
    }

    private func load() async {
        isLoading = true
        defer { isLoading = false }
        let location = CLLocation(latitude: latitude, longitude: longitude)
        do {
            let hourly = try await WeatherService.shared.weather(for: location, including: .hourly)
            let closest = hourly.min { abs($0.date.timeIntervalSince(date)) < abs($1.date.timeIntervalSince(date)) }
            if let closest, abs(closest.date.timeIntervalSince(date)) < 90 * 60 {
                hour = closest
            }
        } catch {
            // Non-fatal: the row just shows "not available yet".
        }
    }
}
