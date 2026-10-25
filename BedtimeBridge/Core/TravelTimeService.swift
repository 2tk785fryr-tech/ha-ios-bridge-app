import CoreLocation
import MapKit

final class TravelTimeService {
    /// The drive-time service chosen in Settings, asked alongside the others you have keys
    /// for so the plan can compare them.
    func provider(for settings: BridgeSettings) throws -> DriveTimeComparison {
        let source = settings.driveTimeSource
        if source.needsAPIKey, KeychainStore.apiKey(for: source).isEmpty {
            throw BridgeError.apiKeyMissing(source.displayName)
        }
        return DriveTimeComparison(
            source: source,
            tomTomKey: KeychainStore.apiKey(for: .tomTom),
            googleKey: KeychainStore.apiKey(for: .google),
            googlePessimistic: settings.googlePessimisticTraffic
        )
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
            let item = MKMapItem(location: coordinates, address: nil)
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
