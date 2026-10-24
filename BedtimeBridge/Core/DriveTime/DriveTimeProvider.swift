import CoreLocation
import MapKit

enum DriveTimeSource: String, Codable, CaseIterable, Identifiable {
    case apple
    case tomTom
    case google

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .apple: "Apple Maps"
        case .tomTom: "TomTom"
        case .google: "Google"
        }
    }

    var needsAPIKey: Bool { self != .apple }
}

protocol DriveTimeProvider {
    /// Seconds to allow for the drive so you arrive no later than `arrival`, using the
    /// traffic expected at that time of day.
    func drivingTime(from origin: MKMapItem, to destination: MKMapItem, arrivingBy arrival: Date) async throws -> TimeInterval
}

extension DriveTimeProvider {
    /// Web services need coordinates, which "current location" doesn't have until it's resolved.
    func coordinate(of item: MKMapItem) throws -> CLLocationCoordinate2D {
        guard !item.isCurrentLocation else { throw BridgeError.homeAddressRequired }
        return item.placemark.coordinate
    }

    func checkHTTP(_ response: URLResponse, data: Data, service: String) throws {
        guard let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) else { return }
        let body = String(decoding: data.prefix(300), as: UTF8.self)
        throw BridgeError.driveTimeService(service, http.statusCode, body)
    }
}

/// Apple Maps takes an arrival date directly and predicts traffic for it. Free, no key.
struct AppleDriveTime: DriveTimeProvider {
    func drivingTime(from origin: MKMapItem, to destination: MKMapItem, arrivingBy arrival: Date) async throws -> TimeInterval {
        let request = MKDirections.Request()
        request.source = origin
        request.destination = destination
        request.transportType = .automobile
        request.arrivalDate = arrival
        return try await MKDirections(request: request).calculateETA().expectedTravelTime
    }
}

/// For services that only accept a departure time (Google's driving routes): keeps
/// asking "if I leave at X, how long?" and moving X until the trip lands on the target.
enum DepartureSolver {
    /// Returns the time to allow, i.e. `arrival − departure` for the latest departure
    /// found that still arrives by `arrival`.
    static func travelTime(
        arrivingBy arrival: Date,
        now: Date,
        maxRequests: Int = 4,
        tolerance: TimeInterval = 60,
        duration: (Date) async throws -> TimeInterval
    ) async throws -> TimeInterval {
        let earliest = now.addingTimeInterval(60)
        var departure = max(arrival.addingTimeInterval(-30 * 60), earliest)
        var latestOnTime: Date?
        var longest: TimeInterval = 0

        for _ in 0..<maxRequests {
            let trip = try await duration(departure)
            longest = max(longest, trip)
            let arrives = departure.addingTimeInterval(trip)
            if arrives <= arrival, latestOnTime.map({ departure > $0 }) ?? true {
                latestOnTime = departure
            }
            if abs(arrives.timeIntervalSince(arrival)) <= tolerance { break }
            let next = max(arrival.addingTimeInterval(-trip), earliest)
            if next == departure { break }
            departure = next
        }

        if let latestOnTime {
            return arrival.timeIntervalSince(latestOnTime)
        }
        // Never landed on time within the request budget: allow the longest trip seen plus slack.
        return longest + tolerance
    }
}
