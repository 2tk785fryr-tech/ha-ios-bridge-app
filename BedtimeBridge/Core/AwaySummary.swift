import Foundation

/// What bedtime says when you're away: your alarms, tomorrow's weather where you are, and
/// whether everything at home is all right. No house steps run (no disarming, no routine).
enum AwaySummary {
    struct Weather: Equatable {
        /// Fahrenheit.
        var high: Double
        /// Home Assistant's condition name ("snowy", "partlycloudy").
        var condition: String
        /// The day it's for is today (after midnight) rather than tomorrow.
        var isToday: Bool
    }

    static func text(
        alarms: [Date],
        temporary: [Date],
        weather: Weather?,
        houseAlarm: String?,
        homeIssues: [String]?,
        signOff: String
    ) -> String {
        var lines: [String] = []
        if let first = alarms.min() {
            lines.append("First alarm \(WakePlanner.format(first)).")
        } else {
            lines.append("No alarms are set.")
        }
        for time in temporary.sorted() {
            lines.append("Temporary alarm at \(WakePlanner.format(time)).")
        }
        if let weather, let sentence = sentence(for: weather) {
            lines.append(sentence)
        }
        lines.append(home(houseAlarm: houseAlarm, issues: homeIssues))
        let sign = signOff.trimmingCharacters(in: .whitespacesAndNewlines)
        if !sign.isEmpty { lines.append(sign) }
        return lines.joined(separator: " ")
    }

    /// "Everything at home is good." unless the house alarm is off or something is open.
    static func home(houseAlarm: String?, issues: [String]?) -> String {
        var problems: [String] = []
        let alarm = (houseAlarm ?? "").lowercased()
        if alarm.contains("disarm") || alarm == "off" {
            problems.append("the house alarm is disarmed")
        }
        problems += issues ?? []
        if problems.isEmpty {
            return issues == nil ? "Couldn't check the house." : "Everything at home is good."
        }
        let list = problems.count == 1
            ? problems[0]
            : problems.dropLast().joined(separator: ", ") + " and " + problems.last!
        return "At home, " + list + "."
    }

    /// "Tomorrow will be warm and rainy." Same words as the home readout.
    static func sentence(for weather: Weather) -> String? {
        let temp = switch weather.high {
        case 90...: "hot"
        case 75..<90: "warm"
        case 60..<75: "mild"
        case 45..<60: "cool"
        default: "cold"
        }
        let sky: String? = switch weather.condition {
        case "sunny", "clear-night": "sunny"
        case "partlycloudy": "partly cloudy"
        case "cloudy": "cloudy"
        case "fog": "foggy"
        case "rainy", "pouring": "rainy"
        case "lightning", "lightning-rainy", "exceptional": "stormy"
        case "snowy", "snowy-rainy", "hail": "snowy"
        case "windy", "windy-variant": "windy"
        default: nil
        }
        let words = [temp, sky].compactMap { $0 }.joined(separator: " and ")
        return "\(weather.isToday ? "Today" : "Tomorrow") will be \(words)."
    }

    /// The high and the worst daytime sky for the day you wake into, from hourly forecast
    /// hours in Celsius.
    static func weather(from hours: [ForecastHour], wakeDay: Date, today: Date = .now, calendar: Calendar = .current) -> Weather? {
        let day = hours.filter { calendar.isDate($0.start, inSameDayAs: wakeDay) }
        guard let highC = day.compactMap(\.temperature).max() else { return nil }
        let daytime = day.filter { (6...21).contains(calendar.component(.hour, from: $0.start)) }
        let worst = (daytime.isEmpty ? day : daytime).map(\.condition).max { severity($0) < severity($1) } ?? ""
        return Weather(high: highC * 9 / 5 + 32, condition: worst, isToday: calendar.isDate(wakeDay, inSameDayAs: today))
    }

    private static func severity(_ condition: String) -> Int {
        ["sunny", "clear-night", "partlycloudy", "cloudy", "windy", "fog", "rainy", "lightning", "pouring",
         "lightning-rainy", "snowy-rainy", "snowy", "hail", "exceptional"].firstIndex(of: condition) ?? 0
    }
}
