import CoreLocation

/// One location fix, asking for When In Use permission the first time.
enum CurrentLocation {
    static func fetch() async throws -> CLLocation {
        let session = CLServiceSession(authorization: .whenInUse)
        defer { session.invalidate() }
        for try await update in CLLocationUpdate.liveUpdates() {
            if let location = update.location { return location }
            if update.authorizationDenied || update.authorizationDeniedGlobally || update.authorizationRestricted {
                throw BridgeError.locationAccessDenied
            }
        }
        throw BridgeError.locationNotFound("your current location")
    }
}
