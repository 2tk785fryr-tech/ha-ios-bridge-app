import CoreLocation
import Foundation

/// The free Open-Meteo forecast (open-meteo.com, no key), for when the weather shouldn't come
/// from Home Assistant. Its WMO weather codes are turned into Home Assistant's condition
/// names, so the bad-weather settings mean the same thing whichever source is used.
struct OpenMeteoForecast {
    var session: URLSession = .shared

    /// The next two days, hour by hour, in °C.
    func hourly(at location: CLLocation) async throws -> [ForecastHour] {
        var components = URLComponents(string: "https://api.open-meteo.com/v1/forecast")!
        components.queryItems = [
            URLQueryItem(name: "latitude", value: String(location.coordinate.latitude)),
            URLQueryItem(name: "longitude", value: String(location.coordinate.longitude)),
            URLQueryItem(name: "hourly", value: "weather_code,temperature_2m,wind_gusts_10m"),
            URLQueryItem(name: "forecast_days", value: "2"),
            URLQueryItem(name: "timeformat", value: "unixtime"),
            URLQueryItem(name: "timezone", value: "GMT"),
        ]
        let (data, response) = try await session.data(from: components.url!)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw BridgeError.weatherService("Open-Meteo", http.statusCode)
        }
        return try Self.hours(from: data)
    }

    static func hours(from data: Data) throws -> [ForecastHour] {
        let hourly = try JSONDecoder().decode(Response.self, from: data).hourly
        return hourly.time.indices.compactMap { index in
            guard let code = hourly.weatherCode[safe: index] ?? nil else { return nil }
            let gusts = hourly.windGusts[safe: index] ?? nil
            return ForecastHour(
                start: Date(timeIntervalSince1970: hourly.time[index]),
                condition: condition(code: code, gustsKPH: gusts),
                temperature: hourly.temperature[safe: index] ?? nil
            )
        }
    }

    /// WMO code (and gusts, which the codes don't cover) to Home Assistant's condition name.
    static func condition(code: Int, gustsKPH: Double?) -> String {
        let condition: String = switch code {
        case 0: "sunny"
        case 1, 2: "partlycloudy"
        case 3: "cloudy"
        case 45, 48: "fog"
        case 51, 53, 55, 61, 63, 80, 81: "rainy"
        case 65, 82: "pouring"
        // Freezing drizzle and freezing rain: icy, closest to sleet.
        case 56, 57, 66, 67: "snowy-rainy"
        case 71, 73, 75, 77, 85, 86: "snowy"
        case 95: "lightning-rainy"
        case 96, 99: "hail"
        default: "exceptional"
        }
        // Strong gusts (~40 mph) count as windy when nothing worse is going on.
        let calm: Set<String> = ["sunny", "partlycloudy", "cloudy"]
        if calm.contains(condition), let gustsKPH, gustsKPH >= 64 { return "windy" }
        return condition
    }

    private struct Response: Decodable {
        struct Hourly: Decodable {
            let time: [TimeInterval]
            let weatherCode: [Int?]
            let temperature: [Double?]
            let windGusts: [Double?]

            enum CodingKeys: String, CodingKey {
                case time
                case weatherCode = "weather_code"
                case temperature = "temperature_2m"
                case windGusts = "wind_gusts_10m"
            }
        }
        let hourly: Hourly
    }
}

private extension Array {
    subscript(safe index: Int) -> Element? { indices.contains(index) ? self[index] : nil }
}
