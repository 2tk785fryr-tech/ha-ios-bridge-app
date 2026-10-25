import Foundation
import MapKit

/// Google Routes API. Driving routes only accept a departure time (arrival time is
/// transit-only), so DepartureSolver works backwards from the time you need to arrive.
struct GoogleDriveTime: DriveTimeProvider {
    let apiKey: String
    /// PESSIMISTIC plans for a bad-traffic day; BEST_GUESS for a typical one.
    var pessimistic: Bool
    var session: URLSession = .shared

    func drivingTime(from origin: MKMapItem, to destination: MKMapItem, arrivingBy arrival: Date) async throws -> TimeInterval {
        let from = try coordinate(of: origin)
        let to = try coordinate(of: destination)
        return try await DepartureSolver.travelTime(arrivingBy: arrival, now: .now) { departure in
            try await duration(from: from, to: to, departingAt: departure)
        }
    }

    private func duration(from: CLLocationCoordinate2D, to: CLLocationCoordinate2D, departingAt departure: Date) async throws -> TimeInterval {
        var request = URLRequest(url: URL(string: "https://routes.googleapis.com/directions/v2:computeRoutes")!)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(apiKey, forHTTPHeaderField: "X-Goog-Api-Key")
        request.setValue("routes.duration", forHTTPHeaderField: "X-Goog-FieldMask")

        let body: [String: Any] = [
            "origin": waypoint(from),
            "destination": waypoint(to),
            "travelMode": "DRIVE",
            "routingPreference": "TRAFFIC_AWARE_OPTIMAL",
            "trafficModel": pessimistic ? "PESSIMISTIC" : "BEST_GUESS",
            "departureTime": ISO8601DateFormatter().string(from: departure),
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await session.data(for: request)
        try checkHTTP(response, data: data, service: "Google")
        let decoded = try JSONDecoder().decode(Response.self, from: data)
        // Duration comes back as a string of seconds with an "s" suffix, e.g. "1534s".
        guard let text = decoded.routes?.first?.duration,
              let seconds = TimeInterval(text.trimmingCharacters(in: CharacterSet(charactersIn: "s"))) else {
            throw BridgeError.driveTimeService("Google", 200, "No route found")
        }
        return seconds
    }

    private func waypoint(_ coordinate: CLLocationCoordinate2D) -> [String: Any] {
        ["location": ["latLng": ["latitude": coordinate.latitude, "longitude": coordinate.longitude]]]
    }

    private struct Response: Decodable {
        struct Route: Decodable { let duration: String? }
        let routes: [Route]?
    }
}
