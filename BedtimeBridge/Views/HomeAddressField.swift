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
            SuggestionRow(suggestion: suggestion) {
                Task { await choose(suggestion) }
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
        let item = await suggestion.mapItem()
        address = item?.singleLineAddress ?? suggestion.singleLine
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
                  let found = item.singleLineAddress
            else { throw BridgeError.locationNotFound("your current location") }
            address = found
        } catch {
            status = error.localizedDescription
        }
    }
}

/// One Maps suggestion under a location field.
struct SuggestionRow: View {
    let suggestion: MKLocalSearchCompletion
    let choose: () -> Void

    var body: some View {
        Button(action: choose) {
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
}

extension MKLocalSearchCompletion {
    /// "1 Apple Park Way, Cupertino, CA, United States", for when the lookup fails.
    var singleLine: String {
        [title, subtitle].filter { !$0.isEmpty }.joined(separator: ", ")
    }

    func mapItem() async -> MKMapItem? {
        try? await MKLocalSearch(request: MKLocalSearch.Request(completion: self)).start().mapItems.first
    }
}

extension MKMapItem {
    /// "1 Infinite Loop, Cupertino, CA 95014"
    var singleLineAddress: String? {
        addressRepresentations?.fullAddress(includingRegion: false, singleLine: true)
            ?? address?.fullAddress
    }

    /// "Dr. Lee Dental, 12 Main St, Springfield, IL 62701": the place name, then where it is.
    var placeAndAddress: String? {
        guard let address = singleLineAddress else { return name }
        guard let name, !name.isEmpty, !address.localizedCaseInsensitiveContains(name) else { return address }
        return "\(name), \(address)"
    }
}

/// Wraps MKLocalSearchCompleter so suggestions update as the query changes.
@MainActor @Observable
final class AddressCompleter: NSObject, MKLocalSearchCompleterDelegate {
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

    init(resultTypes: MKLocalSearchCompleter.ResultType = .address) {
        super.init()
        completer.resultTypes = resultTypes
        completer.delegate = self
    }

    nonisolated func completerDidUpdateResults(_ completer: MKLocalSearchCompleter) {
        MainActor.assumeIsolated { suggestions = Array(completer.results.prefix(4)) }
    }

    nonisolated func completer(_ completer: MKLocalSearchCompleter, didFailWithError error: Error) {
        MainActor.assumeIsolated { suggestions = [] }
    }
}
