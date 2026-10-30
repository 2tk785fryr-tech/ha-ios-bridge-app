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
    /// All-day events with one of these titles are leave (v0.4.3 item 12); the first titles new leave.
    var leaveTitles = ["Leave"]
    /// Where Add leave and Add a wake-up event save; empty is the calendar holding the shifts.
    var newEventsCalendarID = ""
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
    /// Tonight offers "Up before the alarms?" from this many hours before the first one.
    var endAlarmsEarlyHours = 2
    /// Not ready for bed shows this long after bedtime ran (v0.4.2 item 7).
    var notReadyForBedHours = 2
    /// Back to bed shows until this long after the wake-up or the last stop (v0.4.2 item 7).
    var backToBedHours = 3
    /// Why a morning changed, each with what it moves (v0.4.1 item 7). New reasons ask.
    var morningReasons: [MorningReason] = [
        MorningReason(name: "Snow delay", scope: .wakeUp),
        MorningReason(name: "Canceled", scope: .ask),
        MorningReason(name: "Postponed", scope: .wakeUp),
        MorningReason(name: "Not feeling well", scope: .ask),
        MorningReason(name: "Tired", scope: .alarms),
        MorningReason(name: "Other", scope: .ask),
    ]
    /// Shift alarms only: the early backstop moves to this long after the new last alarm when
    /// it would otherwise come before it.
    var earlyBackstopGapMinutes = 5
    /// Wake at a different time starts this many hours from now, then rounds (v0.4.2 item 2).
    var newAlarmHoursAhead = 6

    // MARK: Nap (v0.4.2 item 3)

    /// Off by default; the Nap button only shows when on.
    var napEnabled = false
    var napAlarmCount = 2
    var napSpacingMinutes = 10
    /// Get-ready before events with an address (shifts too).
    var napReadyWithAddressMinutes = 30
    /// Before events without an address: no get-ready, you may just get up and stay home.
    var napReadyNoAddressMinutes = 0
    /// The quick choices, in minutes.
    var napLengths = [20, 30, 45, 60, 90, 120]

    // MARK: Wind-down (v0.4.3 item 5)

    /// Off until the phone side is set up.
    var windDownEnabled = false
    /// Go to bed = tomorrow's first alarm − this.
    var sleepGoalMinutes = 390
    var windDownMinutes = 60
    /// Getting home late: at least this long free before wind-down starts…
    var freeAfterHomeMinutes = 30
    /// …and at least this much wind-down (bedtime moves later instead).
    var minimumWindDownMinutes = 30
    /// The warning before wind-down; 0 is off.
    var windDownWarningMinutes = 5
    /// The warning's "Later" button.
    var windDownLaterMinutes = 15
    var notInBedReminders = true
    var reminderFirstMinutes = 10
    var reminderEveryMinutes = 10
    var reminderStopMinutes = 60
    /// RUN_PLAN_PREVIEW this long before the wind-down the shift calendar gives…
    var planCheckBeforeMinutes = 120
    /// …or at this time ("HH:mm") when only an appointment might decide tomorrow.
    var planCheckFallback = "18:00"
    /// Wind-down for your own alarm on a day off.
    var windDownOwnAlarm = true
    /// "Start wind-down now" shows from this long before go to bed (also on When options show).
    var startWindDownHours = 2

    // MARK: Notifications

    /// Each notification's level by NotificationKind key; one not here uses its default.
    var notificationLevels: [String: String] = [:]

    // MARK: Shortcuts & controls (v0.4.3 item 16)

    /// Quick actions per moment ("daytime", "evening", "morning"); a moment not here uses its defaults.
    var quickActions: [String: [String]] = [:]
    /// The Wind-down control opens the app first instead of acting directly.
    var windDownControlOpensApp = false
    /// The Nap control naps with the first quick length straight away instead of opening the nap screen.
    var napControlNapsNow = false
    /// The Next alarm widget always opens Tonight instead of what matters now.
    var widgetTapAlwaysTonight = false

    // MARK: No-alarm mornings (v0.4.6 item 2)

    /// Leaving the bedroom disarms, back in bed re-arms, staying up asks Up for the day?
    var noAlarmMorningEnabled = true
    /// Good morning never runs by itself before this ("HH:mm").
    var noAlarmEarliest = "08:00"
    /// Up this long without getting back in bed counts as up for the day.
    var noAlarmUpMinutes = 15
    /// Up for the day? goes ahead this long after asking, if you're still up.
    var noAlarmWaitMinutes = 10

    var awakeForHomeAssistant: [String: Any] {
        ["enabled": noAlarmMorningEnabled, "earliest": noAlarmEarliest, "up_minutes": noAlarmUpMinutes, "wait_minutes": noAlarmWaitMinutes]
    }

    // MARK: Weekly summary (v0.4.3 item 15)

    var weeklySummaryEnabled = true
    /// 0 = Monday … 6 = Sunday.
    var weeklySummaryWeekday = 6
    var weeklySummaryTime = "18:00"

    // MARK: Plug in your phone (v0.4.3 item 10)

    /// At bedtime (and go to bed with wind-down on): under this battery and not charging, a reminder.
    var chargeWarningEnabled = true
    var chargeWarningThreshold = 30

    // MARK: Your own alarm's backstops (v0.4.1 item 14)

    /// Whether your own alarm on a day off, or on leave, starts with backstops on.
    var ownBackstopsDayOff = false
    var ownBackstopsLeave = false
    /// Minutes after the LAST alarm.
    var ownEarlyMinutes = 15
    var ownDeadlineMinutes = 30
    var ownLateMinutes = 45
    /// Full backstop actions instead of the gentle ones (push and early light ramp).
    var ownBackstopsFull = false

    // MARK: Wake at a different time (v0.4.1 item 18)

    /// The default time (6 hours from now) rounds UP to this many minutes; 0 is exact.
    var ownAlarmRoundingMinutes = 15
    /// The time picker only offers that interval (otherwise any minute).
    var ownAlarmPickerSnaps = true
    var ownAlarmCount = 3
    var ownAlarmSpacingMinutes = 10
    var ownAlarmWakeIs: WakeTimeAlarm = .first

    var ownOffsetsValid: Bool { 0 <= ownEarlyMinutes && ownEarlyMinutes < ownDeadlineMinutes && ownDeadlineMinutes < ownLateMinutes }
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
    /// Notification this many minutes before leave-by time (v0.4; Home Assistant's copy).
    var leaveReminderLeadMinutes = 15
    /// Leave reminders, minutes before leave-by; 0 is at leave time (v0.4.1 item 17).
    var leaveReminderOffsets = [15, 0]
    static let leaveReminderChoices = [0, 5, 10, 15, 20, 25, 30]
    /// The Lock Screen widget keeps showing leave-by this long after it, once the alarms are done.
    var widgetLeaveByMinutes = 30
}

extension BridgeSettings {
    /// Sent with every message, so Home Assistant always has the current wind-down settings.
    var windDownForHomeAssistant: [String: Any] {
        [
            "enabled": windDownEnabled, "sleep_goal_minutes": sleepGoalMinutes, "length_minutes": windDownMinutes,
            "free_minutes": freeAfterHomeMinutes, "minimum_minutes": minimumWindDownMinutes,
            "warning_minutes": windDownWarningMinutes, "later_minutes": windDownLaterMinutes,
            "reminders": notInBedReminders, "reminder_first_minutes": reminderFirstMinutes,
            "reminder_every_minutes": reminderEveryMinutes, "reminder_stop_minutes": reminderStopMinutes,
            "preview_before_minutes": planCheckBeforeMinutes, "preview_fallback": planCheckFallback,
            "own_alarm": windDownOwnAlarm, "start_hours": startWindDownHours,
        ]
    }

    /// The settings a plan depends on (shifts, alarm series, timings, drive, weather, calendars,
    /// home), so Tonight can tell the plan changed after the alarms were set (v0.4.1 item 10).
    var planFingerprint: String {
        let parts: [Any] = [
            (try? JSONEncoder().encode(shiftRules)).map { String(decoding: $0, as: UTF8.self) } ?? "",
            alarmCount, alarmSpacingMinutes, wakeTimeIs.rawValue, getReadyMinutes, arrivalBufferMinutes,
            workArrivalBufferMinutes, homeAddress, driveTimeSource.rawValue, weatherExtraMinutes,
            badWeatherConditions.sorted(), weatherConditionMinutes.sorted { $0.key < $1.key }.map { "\($0.key)=\($0.value)" },
            shiftCalendarIDs.sorted(), appointmentCalendarIDs.sorted(), alarmStyle.rawValue,
        ]
        return parts.map { "\($0)" }.joined(separator: "|")
    }
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

/// What a change this morning moves (v0.4.1 item 7).
enum MorningChangeScope: String, Codable, CaseIterable, Identifiable {
    /// Sleep longer, same start: only the alarms (the early backstop follows them).
    case alarms
    /// The start is later (a snow delay): alarms, leave-by and all three backstops.
    case wakeUp = "wake_up"
    /// Ask each time.
    case ask

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .alarms: "Shift alarms only"
        case .wakeUp: "Shift entire wake-up"
        case .ask: "Ask"
        }
    }
}

struct MorningReason: Codable, Equatable, Hashable, Identifiable {
    var id = UUID()
    var name: String
    var scope: MorningChangeScope = .ask
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
        HomeAssistantLinks.everyMessage = Self.everyMessage(settings)
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
        HomeAssistantLinks.everyMessage = Self.everyMessage(settings)
        UserDefaults.standard.set(settings.notificationLevels, forKey: NotificationKind.savedKey)
        // The controls and the widget's tap read these from the shared snapshot (v0.4.3 item 16).
        var snapshot = NextAlarmSnapshot.load()
        snapshot.windDownControlOpensApp = settings.windDownControlOpensApp
        snapshot.napControlNapsNow = settings.napControlNapsNow
        snapshot.widgetTapAlwaysTonight = settings.widgetTapAlwaysTonight
        snapshot.startWindDownHours = settings.startWindDownHours
        snapshot.save()
        ControlRefresh.reload()
    }

    /// Wind-down settings (v0.4.3 item 5) and when this install expires (item 9).
    static func everyMessage(_ settings: BridgeSettings) -> [String: Any] {
        var message: [String: Any] = [
            "wind_down_settings": settings.windDownForHomeAssistant,
            "awake_settings": settings.awakeForHomeAssistant,
            "charge_warning": ["enabled": settings.chargeWarningEnabled, "threshold": settings.chargeWarningThreshold],
            "weekly_summary": ["enabled": settings.weeklySummaryEnabled, "weekday": settings.weeklySummaryWeekday, "time": settings.weeklySummaryTime],
            "notification_levels": NotificationKind.forHomeAssistant(settings),
        ]
        if let expires = AppExpiry.iso { message["app_expires"] = expires }
        return message
    }
}

enum WeatherSource: String, Codable, CaseIterable, Identifiable {
    case homeAssistant
    case openMeteo
    /// WeatherKit, with the paid Developer Program.
    case apple

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .homeAssistant: "Home Assistant"
        case .openMeteo: "Open-Meteo (free)"
        case .apple: "Apple Weather"
        }
    }
}
