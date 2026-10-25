import CoreLocation
import MapKit

final class TravelTimeService {
    /// The drive-time service chosen in Settings.
    func provider(for settings: BridgeSettings) throws -> DriveTimeProvider {
        let source = settings.driveTimeSource
        guard source.needsAPIKey else { return AppleDriveTime() }
        let key = KeychainStore.apiKey(for: source)
        guard !key.isEmpty else { throw BridgeError.apiKeyMissing(source.displayName) }
        switch source {
        case .tomTom: return TomTomDriveTime(apiKey: key)
        case .google: return GoogleDriveTime(apiKey: key, pessimistic: settings.googlePessimisticTraffic)
        case .apple: return AppleDriveTime()
        }
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
