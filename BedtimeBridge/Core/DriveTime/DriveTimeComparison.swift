import Foundation
import MapKit

/// One service's answer for a trip, so the plan can show how they compare.
struct DriveEstimate: Equatable {
    enum Service: String, CaseIterable {
        case apple, tomTom, googleTypical, googleWorst

        var displayName: String {
            switch self {
            case .apple: "Apple"
            case .tomTom: "TomTom"
            case .googleTypical: "Google"
            case .googleWorst: "Google worst case"
            }
        }
    }

    var service: Service
    var seconds: TimeInterval
    /// The answer the plan went with.
    var used = false
}

/// Asks Apple Maps and every service you've saved a key for at once, then uses the one
/// chosen in Settings, or the longest with "Longest of all". With a Google key, the
/// worst case is always asked too, so you can see how bad a bad day could be.
struct DriveTimeComparison: DriveTimeProvider {
    let source: DriveTimeSource
    var tomTomKey = ""
    var googleKey = ""
    /// Which Google answer counts: worst case, or a typical day.
    var googlePessimistic = false

    func drivingTime(from origin: MKMapItem, to destination: MKMapItem, arrivingBy arrival: Date) async throws -> TimeInterval {
        try await compare(from: origin, to: destination, arrivingBy: arrival).seconds
    }

    func compare(from origin: MKMapItem, to destination: MKMapItem, arrivingBy arrival: Date) async throws -> (seconds: TimeInterval, estimates: [DriveEstimate]) {
        var providers: [(DriveEstimate.Service, DriveTimeProvider)] = [(.apple, AppleDriveTime())]
        if !tomTomKey.isEmpty { providers.append((.tomTom, TomTomDriveTime(apiKey: tomTomKey))) }
        if !googleKey.isEmpty {
            providers.append((.googleTypical, GoogleDriveTime(apiKey: googleKey, pessimistic: false)))
            providers.append((.googleWorst, GoogleDriveTime(apiKey: googleKey, pessimistic: true)))
        }

        var results: [DriveEstimate.Service: Result<TimeInterval, Error>] = [:]
        await withTaskGroup(of: (DriveEstimate.Service, Result<TimeInterval, Error>).self) { group in
            for (service, provider) in providers {
                group.addTask {
                    do {
                        return (service, .success(try await provider.drivingTime(from: origin, to: destination, arrivingBy: arrival)))
                    } catch {
                        return (service, .failure(error))
                    }
                }
            }
            for await (service, result) in group { results[service] = result }
        }

        let answers = results.compactMapValues { try? $0.get() }
        guard let chosen = Self.choose(from: answers, source: source, googlePessimistic: googlePessimistic) else {
            // The chosen service failed: pass its error on, so the plan says why it fell back.
            let wanted = Self.counted(source: source, googlePessimistic: googlePessimistic)
            let error = wanted.lazy.compactMap { service -> Error? in
                if case .failure(let error) = results[service] { return error }
                return nil
            }.first
            throw error ?? BridgeError.driveTimeService(source.displayName, 0, "No drive time")
        }
        let estimates = DriveEstimate.Service.allCases.compactMap { service in
            answers[service].map { DriveEstimate(service: service, seconds: $0, used: service == chosen.service) }
        }
        return (chosen.seconds, estimates)
    }

    /// The services whose answers count for this setting.
    static func counted(source: DriveTimeSource, googlePessimistic: Bool) -> [DriveEstimate.Service] {
        let google: DriveEstimate.Service = googlePessimistic ? .googleWorst : .googleTypical
        return switch source {
        case .apple: [.apple]
        case .tomTom: [.tomTom]
        case .google: [google]
        case .longest: [.apple, .tomTom, google]
        }
    }

    /// The answer to plan with: the chosen service's, or the longest of those that count.
    static func choose(
        from answers: [DriveEstimate.Service: TimeInterval],
        source: DriveTimeSource,
        googlePessimistic: Bool
    ) -> (service: DriveEstimate.Service, seconds: TimeInterval)? {
        counted(source: source, googlePessimistic: googlePessimistic)
            .compactMap { service in answers[service].map { (service, $0) } }
            .max { $0.1 < $1.1 }
    }
}
