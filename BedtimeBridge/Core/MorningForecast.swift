import Foundation

/// The plain forecast on Tonight's Morning weather row (v0.4.7 item 5): the condition and the
/// temperature at the moment that matters for tomorrow morning.
struct MorningForecast: Codable, Equatable {
    enum Moment: String, Codable {
        /// Leaving for a shift or an event with a location.
        case commute
        /// Alarms but no event.
        case wakeUp
        /// No alarms: Settings → Mornings → Good morning from.
        case goodMorning
    }

    var moment: Moment
    var at: Date
    /// Home Assistant's condition name ("rainy", "partlycloudy").
    var condition: String
    var temperature: Double?
    /// "°F" or "°C", as the forecast gave it.
    var unit: String?

    /// The hour of the forecast covering `at` (or the nearest one within 90 minutes).
    static func pick(hours: [ForecastHour], at: Date, moment: Moment, unit: String?) -> MorningForecast? {
        let covering = hours.last { $0.start <= at && at.timeIntervalSince($0.start) < 3600 }
        let nearest = hours.min { abs($0.start.timeIntervalSince(at)) < abs($1.start.timeIntervalSince(at)) }
        guard let hour = covering ?? nearest.flatMap({ abs($0.start.timeIntervalSince(at)) <= 5400 ? $0 : nil }) else { return nil }
        return MorningForecast(moment: moment, at: at, condition: hour.condition, temperature: hour.temperature, unit: unit)
    }

    /// When to look: leaving for the commute, else the wake-up, else Good morning from (the next
    /// one after `now`).
    static func moment(leaveBy: Date?, wakeUp: Date?, goodMorningFrom: String, now: Date, calendar: Calendar = .current) -> (Moment, Date) {
        if let leaveBy, leaveBy > now { return (.commute, leaveBy) }
        if let wakeUp, wakeUp > now { return (.wakeUp, wakeUp) }
        let parts = goodMorningFrom.split(separator: ":").compactMap { Int($0) }
        let components = DateComponents(hour: parts.first ?? 8, minute: parts.count > 1 ? parts[1] : 0)
        let next = calendar.nextDate(after: now, matching: components, matchingPolicy: .nextTime) ?? now.addingTimeInterval(12 * 3600)
        return (.goodMorning, next)
    }

    /// "Clear", "Partly cloudy", "Rain".
    static func conditionName(_ condition: String) -> String {
        switch condition {
        case "sunny": "Sunny"
        case "clear-night": "Clear"
        case "partlycloudy": "Partly cloudy"
        case "cloudy": "Cloudy"
        case "fog": "Fog"
        case "rainy": "Rain"
        case "pouring": "Heavy rain"
        case "lightning": "Thunder"
        case "lightning-rainy": "Thunderstorms"
        case "snowy": "Snow"
        case "snowy-rainy": "Sleet"
        case "hail": "Hail"
        case "windy", "windy-variant": "Windy"
        case "exceptional": "Severe weather"
        default: condition.isEmpty ? "Unknown" : condition.prefix(1).uppercased() + condition.dropFirst()
        }
    }

    /// The temperature in the phone's unit (°F in the US, else °C), rounded: "38°".
    func temperatureText(locale: Locale = .current) -> String? {
        guard let temperature else { return nil }
        let fromCelsius = (unit ?? "°C").contains("C")
        let wantsF = locale.measurementSystem == .us
        let value: Double = switch (fromCelsius, wantsF) {
        case (true, true): temperature * 9 / 5 + 32
        case (false, false): (temperature - 32) * 5 / 9
        default: temperature
        }
        return "\(Int(value.rounded()))°"
    }

    /// "Rain, 52° at 5:50" (commute), "Clear, 38° at 6:30" (wake-up or Good morning from).
    func text(locale: Locale = .current) -> String {
        let temperature = temperatureText(locale: locale).map { ", \($0)" } ?? ""
        return "\(Self.conditionName(condition))\(temperature) at \(WakePlanner.format(at))"
    }
}
