import Foundation
import Observation

/// How long before a shift starts you want the first alarm, keyed by a word in the event title.
struct ShiftRule: Codable, Identifiable, Hashable {
    var id = UUID()
    /// Case-insensitive match against the calendar event title, e.g. "Days" or "Nights".
    var keyword: String
    /// First alarm goes off this many minutes before the shift starts.
    var wakeMinutesBefore: Int
}

struct BridgeSettings: Codable, Equatable {
    var shiftRules: [ShiftRule] = [
        ShiftRule(keyword: "Days", wakeMinutesBefore: 60),
        ShiftRule(keyword: "Nights", wakeMinutesBefore: 60),
    ]
    /// Calendars searched for shifts. Empty means every calendar.
    var shiftCalendarIDs: Set<String> = []
    /// Calendars searched for appointments. Empty means every calendar.
    var appointmentCalendarIDs: Set<String> = []
    /// Appointments are only considered when their notes contain this text.
    var appointmentKeyword = "wake up"
    /// Time to get ready before leaving for an appointment.
    var getReadyMinutes = 60
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
        if let data = defaults.data(forKey: Self.key),
           let decoded = try? JSONDecoder().decode(BridgeSettings.self, from: data) {
            settings = decoded
        } else {
            settings = BridgeSettings()
        }
    }

    private func save() {
        if let data = try? JSONEncoder().encode(settings) {
            defaults.set(data, forKey: Self.key)
        }
    }
}
