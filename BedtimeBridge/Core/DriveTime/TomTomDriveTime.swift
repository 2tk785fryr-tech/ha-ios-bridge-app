import Foundation
import MapKit

/// TomTom Routing API. It accepts an arrival time directly (`arriveAt`) and uses its
/// historical traffic for that time of day, so one request is enough.
struct TomTomDriveTime: DriveTimeProvider {
    let apiKey: String
    var session: URLSession = .shared

    func drivingTime(from origin: MKMapItem, to destination: MKMapItem, arrivingBy arrival: Date) async throws -> TimeInterval {
        let from = try coordinate(of: origin)
        let to = try coordinate(of: destination)
        let path = "\(from.latitude),\(from.longitude):\(to.latitude),\(to.longitude)"

        var components = URLComponents(string: "https://api.tomtom.com/routing/1/calculateRoute/\(path)/json")!
        components.queryItems = [
            URLQueryItem(name: "key", value: apiKey),
            URLQueryItem(name: "travelMode", value: "car"),
            URLQueryItem(name: "routeType", value: "fastest"),
            URLQueryItem(name: "traffic", value: "true"),
            // UTC ("Z") so there is no "+hh:mm" offset to get mangled in the query string.
            URLQueryItem(name: "arriveAt", value: ISO8601DateFormatter().string(from: arrival)),
        ]

        let (data, response) = try await session.data(from: components.url!)
        try checkHTTP(response, data: data, service: "TomTom")
        let decoded = try JSONDecoder().decode(Response.self, from: data)
        guard let seconds = decoded.routes.first?.summary.travelTimeInSeconds else {
            throw BridgeError.driveTimeService("TomTom", 200, "No route found")
        }
        return TimeInterval(seconds)
    }

    private struct Response: Decodable {
        struct Route: Decodable {
            struct Summary: Decodable { let travelTimeInSeconds: Int }
            let summary: Summary
        }
        let routes: [Route]
    }
}
