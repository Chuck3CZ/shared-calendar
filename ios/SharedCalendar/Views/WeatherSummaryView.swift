import SwiftUI
import WeatherKit
import CoreLocation

/// Shows the forecast closest to an event's start time at its location.
/// Tries the hourly forecast first (precise, but only reaches a handful of
/// days out); for anything further away falls back to that calendar day's
/// daily forecast (a high/low range, but reaches much further out) before
/// giving up and showing "not available yet".
struct WeatherSummaryView: View {
    let latitude: Double
    let longitude: Double
    let date: Date

    @State private var hour: HourWeather?
    @State private var day: DayWeather?
    @State private var isLoading = true

    var body: some View {
        LabeledContent("Počasí") {
            if let hour {
                HStack(spacing: 6) {
                    Image(systemName: hour.symbolName)
                    Text("\(temperatureText(hour.temperature)) · \(hour.condition.description)")
                }
            } else if let day {
                HStack(spacing: 6) {
                    Image(systemName: day.symbolName)
                    Text("\(temperatureText(day.lowTemperature))–\(temperatureText(day.highTemperature)) · \(day.condition.description)")
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

    private func temperatureText(_ measurement: Measurement<UnitTemperature>) -> String {
        measurement.formatted(.measurement(width: .abbreviated, numberFormatStyle: .number.precision(.fractionLength(0))))
    }

    private func load() async {
        isLoading = true
        defer { isLoading = false }
        let location = CLLocation(latitude: latitude, longitude: longitude)

        if let hourly = try? await WeatherService.shared.weather(for: location, including: .hourly),
           let closest = hourly.min(by: { abs($0.date.timeIntervalSince(date)) < abs($1.date.timeIntervalSince(date)) }),
           abs(closest.date.timeIntervalSince(date)) < 90 * 60 {
            hour = closest
            return
        }

        if let daily = try? await WeatherService.shared.weather(for: location, including: .daily),
           let matchingDay = daily.first(where: { Calendar.current.isDate($0.date, inSameDayAs: date) }) {
            day = matchingDay
        }
    }
}
