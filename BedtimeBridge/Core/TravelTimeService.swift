import CoreLocation
import MapKit

final class TravelTimeService {
    /// Driving time that arrives at `arrival`. Passing an arrival date makes Apple Maps use
    /// predicted traffic for that time of day instead of current or free-flow conditions.
    func drivingTime(from origin: MKMapItem, to destination: MKMapItem, arrivingAt arrival: Date) async throws -> TimeInterval {
        let request = MKDirections.Request()
        request.source = origin
        request.destination = destination
        request.transportType = .automobile
        request.arrivalDate = arrival
        let response = try await MKDirections(request: request).calculateETA()
        return response.expectedTravelTime
    }

    /// The home address from settings, or the current location when it is blank.
    func origin(homeAddress: String) async throws -> MKMapItem {
        let trimmed = homeAddress.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? MKMapItem.forCurrentLocation() : try await search(trimmed)
    }

    /// Prefers the coordinates EventKit stored when the location was picked from Maps,
    /// and falls back to searching the location text.
    func destination(locationText: String, coordinates: CLLocation?) async throws -> MKMapItem {
        if let coordinates {
            let item = MKMapItem(placemark: MKPlacemark(coordinate: coordinates.coordinate))
            item.name = locationText
            return item
        }
        return try await search(locationText)
    }

    private func search(_ query: String) async throws -> MKMapItem {
        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = query
        let response = try await MKLocalSearch(request: request).start()
        guard let item = response.mapItems.first else { throw BridgeError.locationNotFound(query) }
        return item
    }
}
