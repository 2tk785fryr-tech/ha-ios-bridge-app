import CoreLocation
import MapKit
import SwiftUI

/// Home address with Maps suggestions while you type, and a button that fills in the
/// address of where you are now.
struct HomeAddressField: View {
    @Binding var address: String
    @State private var completer = AddressCompleter()
    @State private var locating = false
    @State private var status: String?
    @FocusState private var focused: Bool

    var body: some View {
        TextField("Home address", text: $address, axis: .vertical)
            .textContentType(.fullStreetAddress)
            .focused($focused)
            .onChange(of: address) { _, text in
                if focused { completer.query = text }
            }
            .onChange(of: focused) { _, isFocused in
                completer.query = isFocused ? address : ""
            }

        ForEach(completer.suggestions, id: \.self) { suggestion in
            Button {
                Task { await choose(suggestion) }
            } label: {
                VStack(alignment: .leading, spacing: 2) {
                    Text(suggestion.title).foregroundStyle(Theme.text)
                    if !suggestion.subtitle.isEmpty {
                        Text(suggestion.subtitle)
                            .font(.footnote)
                            .foregroundStyle(Theme.textMuted)
                    }
                }
            }
        }

        VStack(alignment: .leading, spacing: 4) {
            Button {
                Task { await useCurrentLocation() }
            } label: {
                HStack {
                    Label("Use current location", systemImage: "location.fill")
                    if locating {
                        Spacer()
                        ProgressView()
                    }
                }
            }
            .disabled(locating)
            if let status {
                Text(status).font(.footnote).foregroundStyle(Theme.textMuted)
            }
        }
    }

    private func choose(_ suggestion: MKLocalSearchCompletion) async {
        focused = false
        let fallback = [suggestion.title, suggestion.subtitle].filter { !$0.isEmpty }.joined(separator: ", ")
        let item = try? await MKLocalSearch(request: MKLocalSearch.Request(completion: suggestion)).start().mapItems.first
        address = item.flatMap(Self.singleLine) ?? fallback
        completer.query = ""
    }

    private func useCurrentLocation() async {
        focused = false
        locating = true
        status = nil
        defer { locating = false }
        do {
            let location = try await CurrentLocation.fetch()
            guard let request = MKReverseGeocodingRequest(location: location),
                  let item = try await request.mapItems.first,
                  let found = Self.singleLine(item)
            else { throw BridgeError.locationNotFound("your current location") }
            address = found
        } catch {
            status = error.localizedDescription
        }
    }

    /// "1 Infinite Loop, Cupertino, CA 95014"
    private static func singleLine(_ item: MKMapItem) -> String? {
        item.addressRepresentations?.fullAddress(includingRegion: false, singleLine: true)
            ?? item.address?.fullAddress
    }
}

/// Wraps MKLocalSearchCompleter so suggestions update as the query changes.
@MainActor @Observable
private final class AddressCompleter: NSObject, MKLocalSearchCompleterDelegate {
    private(set) var suggestions: [MKLocalSearchCompletion] = []
    private let completer = MKLocalSearchCompleter()

    var query = "" {
        didSet {
            let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.count < 3 {
                completer.cancel()
                suggestions = []
            } else {
                completer.queryFragment = trimmed
            }
        }
    }

    override init() {
        super.init()
        completer.resultTypes = .address
        completer.delegate = self
    }

    nonisolated func completerDidUpdateResults(_ completer: MKLocalSearchCompleter) {
        MainActor.assumeIsolated { suggestions = Array(completer.results.prefix(4)) }
    }

    nonisolated func completer(_ completer: MKLocalSearchCompleter, didFailWithError error: Error) {
        MainActor.assumeIsolated { suggestions = [] }
    }
}

/// One location fix, asking for When In Use permission the first time.
private enum CurrentLocation {
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
