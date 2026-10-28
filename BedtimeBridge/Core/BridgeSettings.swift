import Foundation
import Observation

/// When to wake for one shift type, keyed by a word in the event title. Each shift can have
/// its own timing and alarm series; appointments use the general settings.
struct ShiftRule: Codable, Identifiable, Hashable {
    enum Timing: String, Codable, CaseIterable, Identifiable {
        /// A set number of minutes before the shift starts (e.g. Days).
        case beforeShift
        /// The same clock time on the shift's day (e.g. Swings: 8:00 AM, whatever time you
        /// got to bed after the last one).
        case fixedTime

        var id: String { rawValue }
    }

    var id = UUID()
    /// Case-insensitive match against the calendar event title, e.g. "Days" or "Swings".
    /// Also sent to Home Assistant as the alarm cause, so spell it the way HA expects.
    var keyword: String
    var timing: Timing = .beforeShift
    /// `.beforeShift`: the set alarm time is this many minutes before the shift starts.
    var wakeMinutesBefore: Int = 60
    /// `.fixedTime`: the set alarm time, on the shift's day.
    var fixedHour: Int = 8
    var fixedMinute: Int = 0
    /// Overrides for this shift's alarm series; nil uses the general setting.
    var wakeIs: WakeTimeAlarm? = nil
    var alarmCount: Int? = nil
    var alarmSpacingMinutes: Int? = nil

    init(
        keyword: String,
        timing: Timing = .beforeShift,
        wakeMinutesBefore: Int = 60,
        fixedHour: Int = 8,
        fixedMinute: Int = 0,
        wakeIs: WakeTimeAlarm? = nil,
        alarmCount: Int? = nil,
        alarmSpacingMinutes: Int? = nil
    ) {
        self.keyword = keyword
        self.timing = timing
        self.wakeMinutesBefore = wakeMinutesBefore
        self.fixedHour = fixedHour
        self.fixedMinute = fixedMinute
        self.wakeIs = wakeIs
        self.alarmCount = alarmCount
        self.alarmSpacingMinutes = alarmSpacingMinutes
    }

    /// Reads rules saved by older versions, which only had keyword and minutes.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        keyword = try c.decode(String.self, forKey: .keyword)
        timing = try c.decodeIfPresent(Timing.self, forKey: .timing) ?? .beforeShift
        wakeMinutesBefore = try c.decodeIfPresent(Int.self, forKey: .wakeMinutesBefore) ?? 60
        fixedHour = try c.decodeIfPresent(Int.self, forKey: .fixedHour) ?? 8
        fixedMinute = try c.decodeIfPresent(Int.self, forKey: .fixedMinute) ?? 0
        wakeIs = try c.decodeIfPresent(WakeTimeAlarm.self, forKey: .wakeIs)
        alarmCount = try c.decodeIfPresent(Int.self, forKey: .alarmCount)
        alarmSpacingMinutes = try c.decodeIfPresent(Int.self, forKey: .alarmSpacingMinutes)
    }
}

struct BridgeSettings: Codable, Equatable {
    var shiftRules: [ShiftRule] = [
        // 6:30 AM shift → 4:20, 4:25, 4:30. HA's own 5:10 deadline (Wake Deadline Backstop)
        // is when you must be out of bed; that stays in Home Assistant.
        ShiftRule(keyword: "Days", wakeMinutesBefore: 120, wakeIs: .last, alarmCount: 3, alarmSpacingMinutes: 5),
        // First alarm at 8:00 AM on swing days, then the usual series after it.
        ShiftRule(keyword: "Swings", timing: .fixedTime, fixedHour: 8, fixedMinute: 0, wakeIs: .first),
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
    /// Arrive this long before a shift starts.
    var workArrivalBufferMinutes = 10
    /// Move a shift's alarms earlier when the drive (or bad weather) would leave less than
    /// the get-ready time before leaving.
    var wakeEarlyToGetReady = false
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
    /// When Home Assistant says you're away, drives start from where you are.
    var driveFromHereWhenAway = true

    // MARK: Alarms

    var alarmStyle: AlarmStyle = .app
    /// App alarms only. Clock app snooze is fixed at 9 minutes by Apple.
    var snoozeMinutes = 9
    /// App alarms only: what they ring with.
    var alarmSound: AlarmSound = .standard
    /// App alarms only: what Stop does to the rest of the series. Default keeps them until
    /// Home Assistant confirms you're up: stopping the first alarm and falling back asleep is
    /// exactly how Wake Deadline Backstop came to exist.
    var stopBehavior: StopBehavior = .keepUntilUp

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
    /// For "keep the rest until you're up" (token mode; the integration has its own).
    var bedSensor = "binary_sensor.master_bedroom_bed_presence_bed_occupied_left"
    var exitLatch = "input_boolean.bedroom_exited_today"

    // MARK: Weather

    /// Where the forecast comes from. Open-Meteo works without Home Assistant.
    var weatherSource: WeatherSource = .homeAssistant
    var weatherEntity = "weather.forecast_home"
    /// Added when the forecast between waking and arriving matches a bad-weather condition
    /// that has no amount of its own.
    var weatherExtraMinutes = 15
    var badWeatherConditions: Set<String> = ["pouring", "lightning-rainy", "snowy", "snowy-rainy", "hail"]
    /// Conditions that need more (or less) than the default, e.g. ["snowy": 30].
    /// "freezing" is rain or snow at or below freezing.
    var weatherConditionMinutes: [String: Int] = [:]
    /// Also count any rain or snow at or below freezing.
    var addTimeWhenFreezing = true

    /// Minutes for a condition: its own amount, or the default.
    func weatherMinutes(for condition: String) -> Int {
        weatherConditionMinutes[condition] ?? weatherExtraMinutes
    }

    /// Whether any ticked condition would add time, so the forecast is worth fetching.
    var checksWeather: Bool {
        badWeatherConditions.contains { weatherMinutes(for: $0) > 0 }
            || (addTimeWhenFreezing && weatherMinutes(for: PlanAdjustments.freezing) > 0)
    }

    // MARK: Leave-by reminder

    var leaveReminderEnabled = true
    /// Notify about "wake up" appointments with no location (answer from the notification).
    var askAboutMissingLocations = true
    /// Notification this many minutes before leave-by time.
    var leaveReminderLeadMinutes = 15
    /// The Lock Screen widget keeps showing leave-by this long after it, once the alarms are done.
    var widgetLeaveByMinutes = 30
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

enum StopBehavior: String, Codable, CaseIterable, Identifiable {
    /// Cancel the later alarms only if HA says you're up (door opened, or bed empty > 1 min).
    case keepUntilUp
    case cancelRest
    case keepAll

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .keepUntilUp: "Keep the rest until I'm up"
        case .cancelRest: "Cancel the rest"
        case .keepAll: "Keep them all"
        }
    }
}

/// What app alarms ring with: iOS's own alarm sound, or one of the sounds that ship in
/// BedtimeBridge/Sounds (AlarmKit can't use the system ringtones).
enum AlarmSound: String, Codable, CaseIterable, Identifiable {
    case standard
    case sunrise
    case chimes
    case marimba
    case harp
    case classic
    case pulse

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .standard: "iPhone alarm (default)"
        case .sunrise: "Sunrise (builds slowly)"
        case .chimes: "Chimes"
        case .marimba: "Marimba"
        case .harp: "Harp"
        case .classic: "Classic beeps"
        case .pulse: "Pulse (loud)"
        }
    }

    /// The bundled file, or nil for the system sound.
    var fileName: String? { self == .standard ? nil : "\(rawValue).caf" }
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

enum WeatherSource: String, Codable, CaseIterable, Identifiable {
    case homeAssistant
    case openMeteo

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .homeAssistant: "Home Assistant"
        case .openMeteo: "Open-Meteo (free)"
        }
    }
}
