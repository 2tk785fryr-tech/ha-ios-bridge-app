import SwiftUI

/// v0.4.3 item 8: each setting shows its default when it differs ("5 alarms · default 3"), and
/// each page ends with "Reset this page to defaults".
struct DefaultNote: View {
    let text: String

    var body: some View {
        Text("default \(text)")
            .font(.caption)
            .foregroundStyle(Theme.textFaint)
    }
}

/// A stepper whose label shows the value, plus " · default 3" in grey when it differs.
struct DefaultStepper: View {
    @Binding var value: Int
    let range: ClosedRange<Int>
    var step = 1
    let defaultValue: Int
    let label: (Int) -> String
    /// How the default reads; the value alone ("3", "30 min") unless given.
    var note: (Int) -> String = { "\($0)" }

    init(value: Binding<Int>, in range: ClosedRange<Int>, step: Int = 1, defaultValue: Int,
         note: @escaping (Int) -> String = { "\($0)" }, label: @escaping (Int) -> String) {
        _value = value
        self.range = range
        self.step = step
        self.defaultValue = defaultValue
        self.label = label
        self.note = note
    }

    init(title: String, value: Binding<Int>, range: ClosedRange<Int>, step: Int = 1, defaultValue: Int,
         format: @escaping (Int) -> String = { "\($0)" }) {
        self.init(value: value, in: range, step: step, defaultValue: defaultValue, note: format) { "\(title): \(format($0))" }
    }

    var body: some View {
        Stepper(value: $value, in: range, step: step) {
            WithDefault(text: label(value), defaultText: value == defaultValue ? nil : note(defaultValue))
        }
    }
}

/// "5 alarms · default 3": the default in small grey text next to the value.
struct WithDefault: View {
    let text: String
    let defaultText: String?

    var body: some View {
        if let defaultText {
            Text("\(text) ") + Text("· default \(defaultText)").font(.caption).foregroundStyle(Theme.textFaint)
        } else {
            Text(text)
        }
    }
}

/// A switch with its default in grey when it differs.
struct DefaultToggle: View {
    let title: String
    @Binding var isOn: Bool
    let defaultValue: Bool

    var body: some View {
        Toggle(isOn: $isOn) {
            WithDefault(text: title, defaultText: isOn == defaultValue ? nil : (defaultValue ? "on" : "off"))
        }
    }
}

extension BridgeSettings {
    /// Puts these settings (by name) back to their defaults, for "Reset this page to defaults".
    mutating func resetToDefaults(_ keys: [String]) {
        guard let defaults = try? JSONSerialization.jsonObject(with: JSONEncoder().encode(BridgeSettings())) as? [String: Any],
              var current = try? JSONSerialization.jsonObject(with: JSONEncoder().encode(self)) as? [String: Any] else { return }
        for key in keys { current[key] = defaults[key] }
        if let data = try? JSONSerialization.data(withJSONObject: current),
           let reset = try? JSONDecoder().decode(BridgeSettings.self, from: data) {
            self = reset
        }
    }
}

/// "Reset this page to defaults" at the bottom of a settings page, with a confirm.
struct ResetPageSection: View {
    var detail = "Only this page's settings go back to their defaults."
    let reset: () -> Void
    @State private var confirming = false

    var body: some View {
        Section {
            Button("Reset this page to defaults", role: .destructive) { confirming = true }
                .confirmationDialog("Reset this page to defaults?", isPresented: $confirming, titleVisibility: .visible) {
                    Button("Reset", role: .destructive, action: reset)
                    Button("Cancel", role: .cancel) {}
                } message: {
                    Text(detail)
                }
        }
    }
}

enum DurationText {
    /// 390 → "6.5 h", 60 → "60 min"
    static func hours(_ minutes: Int) -> String {
        minutes % 60 == 0 ? "\(minutes / 60) h" : String(format: "%.2g h", Double(minutes) / 60).replacingOccurrences(of: ".0 ", with: " ")
    }

    static func minutes(_ minutes: Int) -> String { "\(minutes) min" }
}

/// Which settings each page shows, for "Reset this page to defaults" (v0.4.3 item 8).
enum SettingsPages {
    static let main = ["shiftRules", "getReadyMinutes", "workArrivalBufferMinutes", "wakeEarlyToGetReady", "homeAddress"]
    static let alarms = ["alarmStyle", "alarmCount", "alarmSpacingMinutes", "wakeTimeIs", "snoozeMinutes", "alarmSound", "stopBehavior", "lookAheadHours"]
    static let ownAlarms = ["newAlarmHoursAhead", "ownAlarmRoundingMinutes", "ownAlarmPickerSnaps", "ownAlarmCount", "ownAlarmSpacingMinutes", "ownAlarmWakeIs", "ownBackstopsDayOff", "ownBackstopsLeave", "ownEarlyMinutes", "ownDeadlineMinutes", "ownLateMinutes", "ownBackstopsFull"]
    static let optionWindows = ["endAlarmsEarlyHours", "notReadyForBedHours", "backToBedHours", "startWindDownHours"]
    static let morningChange = ["morningReasons", "earlyBackstopGapMinutes"]
    static let nap = ["napEnabled", "napAlarmCount", "napSpacingMinutes", "napReadyWithAddressMinutes", "napReadyNoAddressMinutes", "napLengths"]
    static let windDown = ["windDownEnabled", "sleepGoalMinutes", "windDownMinutes", "freeAfterHomeMinutes", "minimumWindDownMinutes", "windDownWarningMinutes", "windDownLaterMinutes", "notInBedReminders", "reminderFirstMinutes", "reminderEveryMinutes", "reminderStopMinutes", "planCheckBeforeMinutes", "planCheckFallback", "windDownOwnAlarm", "startWindDownHours"]
    static let appointments = ["appointmentKeyword", "arrivalBufferMinutes", "askAboutMissingLocations"]
    static let driveTime = ["driveTimeSource", "googlePessimisticTraffic", "fallbackTravelMinutes", "driveFromHereWhenAway", "leaveReminderEnabled", "leaveReminderOffsets", "widgetLeaveByMinutes"]
    static let homeAssistant = ["homeAssistantURL", "snoozeHelper", "stopHelper", "shiftOverrideEntity", "shiftSensorEntity", "nextAlarmSensor", "bedtimeHelper", "presenceEntity", "homeOnly", "bedSensor", "exitLatch"]
    static let weather = ["weatherSource", "weatherEntity", "weatherExtraMinutes", "badWeatherConditions", "weatherConditionMinutes", "addTimeWhenFreezing"]
    static let calendars = ["shiftCalendarIDs", "appointmentCalendarIDs"]

    static let all = [main, alarms, ownAlarms, optionWindows, morningChange, nap, windDown, appointments, driveTime, homeAssistant, weather, calendars]
}
