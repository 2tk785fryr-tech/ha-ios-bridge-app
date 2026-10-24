import Foundation
import Observation

/// How long before a shift starts you want the first alarm, keyed by a word in the event title.
struct ShiftRule: Codable, Identifiable, Hashable {
    var id = UUID()
    /// Case-insensitive match against the calendar event title, e.g. "Days" or "Swings".
    /// Also sent to Home Assistant as the alarm cause, so spell it the way HA expects.
    var keyword: String
    /// First alarm goes off this many minutes before the shift starts.
    var wakeMinutesBefore: Int
}

struct BridgeSettings: Codable, Equatable {
    var shiftRules: [ShiftRule] = [
        ShiftRule(keyword: "Days", wakeMinutesBefore: 60),
        ShiftRule(keyword: "Swings", wakeMinutesBefore: 60),
    ]
    /// Calendars searched for shifts. Empty means every calendar.
    var shiftCalendarIDs: Set<String> = []
    /// Calendars searched for appointments. Empty means every calendar.
    var appointmentCalendarIDs: Set<String> = []
    /// Appointments are only considered when their notes contain this text.
    var appointmentKeyword = "wake up"
    /// Time to get ready before leaving for an appointment.
    var getReadyMinutes = 60
    /// Arrive this long before an appointment starts.
    var arrivalBufferMinutes = 10
    var driveTimeSource: DriveTimeSource = .apple
    /// Google only: plan for a bad-traffic day instead of a typical one.
    var googlePessimisticTraffic = false
    /// Used when a drive time cannot be calculated (no signal, unknown address).
    var fallbackTravelMinutes = 30
    var alarmCount = 3
    var alarmSpacingMinutes = 10
    /// Only events starting within this many hours from now are considered.
    var lookAheadHours = 24
    /// Starting point for drive times. Empty means current location.
    var homeAddress = ""
}

@Observable
final class SettingsStore {
    static let shared = SettingsStore()

    private static let key = "bridgeSettings.v1"
    private let defaults: UserDefaults

    var settings: BridgeSettings {
        didSet { save() }
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        settings = defaults.data(forKey: Self.key).flatMap(Self.decode) ?? BridgeSettings()
    }

    /// Lays saved values over the defaults, so settings added in a later version don't
    /// make the decode fail and wipe everything you'd already set.
    private static func decode(_ data: Data) -> BridgeSettings? {
        guard let saved = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let defaultsData = try? JSONEncoder().encode(BridgeSettings()),
              var merged = try? JSONSerialization.jsonObject(with: defaultsData) as? [String: Any] else { return nil }
        merged.merge(saved) { _, saved in saved }
        guard let mergedData = try? JSONSerialization.data(withJSONObject: merged) else { return nil }
        return try? JSONDecoder().decode(BridgeSettings.self, from: mergedData)
    }

    private func save() {
        if let data = try? JSONEncoder().encode(settings) {
            defaults.set(data, forKey: Self.key)
        }
    }
}
