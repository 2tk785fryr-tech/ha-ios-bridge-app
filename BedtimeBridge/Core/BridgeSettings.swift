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
    /// Whether the planned wake-up time is the last alarm of the series (the others go
    /// off earlier) or the first (the others go off later).
    var wakeTimeIs: WakeTimeAlarm = .last
    /// Only events starting within this many hours from now are considered.
    var lookAheadHours = 24
    /// Starting point for drive times. Empty means current location.
    var homeAddress = ""

    // MARK: Alarms

    var alarmStyle: AlarmStyle = .app
    /// App alarms only. Clock app snooze is fixed at 9 minutes by Apple.
    var snoozeMinutes = 9
    /// App alarms only: stopping one alarm cancels the rest of tonight's series.
    var stopCancelsRemaining = true

    // MARK: Home Assistant

    /// e.g. http://homeassistant.local:8123 or your Nabu Casa URL. The token is in the Keychain.
    var homeAssistantURL = ""
    /// Turned on when you tap Snooze (starts Wake Snooze Fade).
    var snoozeHelper = "input_boolean.wake_fade"
    /// Turned on when you tap Stop (starts Wake Sequence).
    var stopHelper = "input_boolean.wake_mike"
    /// "Off" skips the work alarm; "Days"/"Swings" overrides the shift type.
    var shiftOverrideEntity = "input_select.select_shift_override"
    /// Its next_shift_start is compared with the calendar as a sanity check.
    var shiftSensorEntity = "sensor.current_shift"
    /// Kept up to date with the next alarm time and cause.
    var nextAlarmSensor = "sensor.bedtime_bridge_next_alarm"
    /// Turned on by Start Bedtime Routine.
    var bedtimeHelper = "input_boolean.bedtime_routine"
    /// You, for "only when home". Unknown/unavailable counts as home.
    var presenceEntity = "person.michael_perschy"
    /// Skip the wake helpers and the bedtime routine while you're away.
    var homeOnly = true

    // MARK: Weather

    var weatherEntity = "weather.forecast_home"
    /// Added when the forecast between waking and arriving matches a bad-weather condition.
    var weatherExtraMinutes = 15
    var badWeatherConditions: Set<String> = ["pouring", "lightning-rainy", "snowy", "snowy-rainy", "hail"]
    /// Also count any rain or snow at or below freezing.
    var addTimeWhenFreezing = true

    // MARK: Leave-by reminder

    var leaveReminderEnabled = true
    /// Notify about "wake up" appointments with no location (answer from the notification).
    var askAboutMissingLocations = true
    /// Notification this many minutes before leave-by time.
    var leaveReminderLeadMinutes = 15
}

enum WakeTimeAlarm: String, Codable, CaseIterable, Identifiable {
    /// Default: e.g. wake-up 5:30 → alarms 5:10, 5:20, 5:30.
    case last
    /// e.g. wake-up 5:30 → alarms 5:30, 5:40, 5:50.
    case first

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .last: "Last alarm"
        case .first: "First alarm"
        }
    }
}

enum AlarmStyle: String, Codable, CaseIterable, Identifiable {
    /// AlarmKit alarms with adjustable snooze; Snooze/Stop tell Home Assistant directly.
    case app
    /// The app only works out the times; your shortcut creates Clock app alarms.
    case clock

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .app: "Bedtime Bridge alarms"
        case .clock: "Clock app (via shortcut)"
        }
    }
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
