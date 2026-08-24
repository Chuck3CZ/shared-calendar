import Foundation

/// Apple's WeatherKit REST API returns a raw condition code string (e.g.
/// "MostlyClear") with no localization of its own — this maps every
/// documented code to an SF Symbol and a Czech label.
enum WeatherConditionInfo {
    private static let table: [String: (symbol: String, label: String)] = [
        "Clear": ("sun.max.fill", "Jasno"),
        "MostlyClear": ("sun.max.fill", "Skoro jasno"),
        "PartlyCloudy": ("cloud.sun.fill", "Polojasno"),
        "MostlyCloudy": ("cloud.fill", "Skoro zataženo"),
        "Cloudy": ("cloud.fill", "Zataženo"),
        "Foggy": ("cloud.fog.fill", "Mlha"),
        "Haze": ("sun.haze.fill", "Opar"),
        "Smoky": ("smoke.fill", "Kouř"),
        "BlowingDust": ("sun.dust.fill", "Prach ve vzduchu"),
        "Breezy": ("wind", "Vítr"),
        "Windy": ("wind", "Silný vítr"),
        "Drizzle": ("cloud.drizzle.fill", "Mrholení"),
        "Rain": ("cloud.rain.fill", "Déšť"),
        "HeavyRain": ("cloud.heavyrain.fill", "Vydatný déšť"),
        "SunShowers": ("cloud.sun.rain.fill", "Přeháňky"),
        "Sleet": ("cloud.sleet.fill", "Déšť se sněhem"),
        "FreezingDrizzle": ("cloud.sleet.fill", "Mrznoucí mrholení"),
        "FreezingRain": ("cloud.sleet.fill", "Mrznoucí déšť"),
        "WintryMix": ("cloud.sleet.fill", "Přeháňky se sněhem"),
        "Flurries": ("wind.snow", "Sněhové přeháňky"),
        "SunFlurries": ("sun.snow.fill", "Sněžení za slunce"),
        "Snow": ("cloud.snow.fill", "Sníh"),
        "HeavySnow": ("snowflake", "Vydatné sněžení"),
        "BlowingSnow": ("wind.snow", "Sněhová vánice"),
        "Blizzard": ("wind.snow", "Sněhová bouře"),
        "Hail": ("cloud.hail.fill", "Kroupy"),
        "Thunderstorms": ("cloud.bolt.rain.fill", "Bouřky"),
        "IsolatedThunderstorms": ("cloud.bolt.rain.fill", "Ojedinělé bouřky"),
        "ScatteredThunderstorms": ("cloud.bolt.rain.fill", "Přeháňky s bouřkami"),
        "StrongStorms": ("cloud.bolt.rain.fill", "Silné bouřky"),
        "TropicalStorm": ("tropicalstorm", "Tropická bouře"),
        "Hurricane": ("hurricane", "Hurikán"),
        "Frigid": ("thermometer.snowflake", "Extrémní mráz"),
        "Hot": ("thermometer.sun.fill", "Horko"),
    ]

    static func symbolName(for condition: String) -> String {
        table[condition]?.symbol ?? "questionmark.circle"
    }

    static func label(for condition: String) -> String {
        table[condition]?.label ?? condition
    }
}
