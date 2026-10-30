import CoreLocation
import Foundation
import WeatherKit

/// Apple Weather (WeatherKit, available with the paid Developer Program since 29 Oct 2026). Its
/// conditions are turned into Home Assistant's condition names, so the bad-weather settings mean
/// the same thing whichever source is used.
struct AppleWeatherForecast {
    /// The next hours, in the phone's temperature unit.
    func hourly(at location: CLLocation) async throws -> (hours: [ForecastHour], temperatureUnit: String) {
        let forecast = try await WeatherService.shared.weather(for: location, including: .hourly)
        let fahrenheit = Locale.current.measurementSystem == .us
        let hours = forecast.forecast.map { hour in
            ForecastHour(
                start: hour.date,
                condition: Self.condition(hour.condition, gustsKPH: hour.wind.gust?.converted(to: .kilometersPerHour).value),
                temperature: hour.temperature.converted(to: fahrenheit ? .fahrenheit : .celsius).value
            )
        }
        return (hours, fahrenheit ? "°F" : "°C")
    }

    /// WeatherKit's condition as Home Assistant names it.
    static func condition(_ condition: WeatherCondition, gustsKPH: Double? = nil) -> String {
        switch condition {
        case .clear, .mostlyClear, .hot: "sunny"
        case .partlyCloudy: "partlycloudy"
        case .cloudy, .mostlyCloudy: "cloudy"
        case .foggy, .haze, .smoky: "fog"
        case .drizzle, .rain, .sunShowers: "rainy"
        case .heavyRain: "pouring"
        case .isolatedThunderstorms, .scatteredThunderstorms, .strongStorms, .thunderstorms: "lightning-rainy"
        case .flurries, .snow, .heavySnow, .sunFlurries, .blowingSnow, .blizzard: "snowy"
        case .sleet, .freezingRain, .freezingDrizzle, .wintryMix: "snowy-rainy"
        case .hail: "hail"
        case .breezy, .windy: "windy"
        case .tropicalStorm, .hurricane, .frigid, .blowingDust: "exceptional"
        @unknown default: (gustsKPH ?? 0) >= 50 ? "windy" : "cloudy"
        }
    }

    /// "Weather" with Apple's mark and its legal page, shown wherever this source is used.
    static func attribution() async -> (markURL: URL, legalURL: URL)? {
        guard let attribution = try? await WeatherService.shared.attribution else { return nil }
        return (attribution.combinedMarkLightURL, attribution.legalPageURL)
    }
}
