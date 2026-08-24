import SwiftUI

/// Pure display — the forecast itself is fetched and cached server-side
/// (once daily per event, plus right after it's created/edited), never by
/// the app calling WeatherKit directly. See backend/src/weather.js.
struct WeatherSummaryView: View {
    let condition: String?
    let temperature: Double?
    let temperatureMin: Double?
    let temperatureMax: Double?
    let isHourly: Bool

    var body: some View {
        LabeledContent("Počasí") {
            if let condition {
                HStack(spacing: 6) {
                    Image(systemName: WeatherConditionInfo.symbolName(for: condition))
                    Text("\(temperatureSummary) · \(WeatherConditionInfo.label(for: condition))")
                }
            } else {
                Text("Zatím není k dispozici")
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var temperatureSummary: String {
        if isHourly, let temperature {
            return temperatureText(temperature)
        }
        if let temperatureMin, let temperatureMax {
            return "\(temperatureText(temperatureMin))–\(temperatureText(temperatureMax))"
        }
        return "—"
    }

    private func temperatureText(_ celsius: Double) -> String {
        Measurement(value: celsius, unit: UnitTemperature.celsius)
            .formatted(.measurement(width: .abbreviated, numberFormatStyle: .number.precision(.fractionLength(0))))
    }
}
