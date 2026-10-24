import AppIntents
import Foundation

/// What the Shortcuts actions hand back. Each property shows up as a Magic Variable
/// field in Shortcuts (e.g. "Wake Plan › Has Alarm").
struct WakePlanEntity: TransientAppEntity {
    static var typeDisplayRepresentation: TypeDisplayRepresentation = "Wake Plan"

    @Property(title: "Has Alarm")
    var hasAlarm: Bool

    /// "Days", "Swings", "calendar", "automade" or "noalarm".
    @Property(title: "Alarm Cause")
    var alarmCause: String

    @Property(title: "First Alarm")
    var firstAlarm: Date?

    @Property(title: "Alarm Times")
    var alarmTimesText: String

    /// The individual times, for "Repeat with Each → Create Alarm" in Clock app mode.
    @Property(title: "Alarm Dates")
    var alarmDates: [Date]

    /// True when Settings uses Clock app alarms, so the shortcut should create them.
    @Property(title: "Needs Clock Alarms")
    var needsClockAlarms: Bool

    @Property(title: "Reason")
    var reason: String

    @Property(title: "Warnings")
    var warnings: String

    /// JSON ready to send to Home Assistant (webhook body or a Shortcuts dictionary).
    @Property(title: "Home Assistant JSON")
    var homeAssistantJSON: String

    init() {
        hasAlarm = false
        alarmCause = AlarmCause.none
        firstAlarm = nil
        alarmTimesText = ""
        alarmDates = []
        needsClockAlarms = false
        reason = ""
        warnings = ""
        homeAssistantJSON = "{}"
    }

    init(plan: WakePlan) {
        self.init()
        hasAlarm = plan.hasAlarm
        alarmCause = plan.cause
        firstAlarm = plan.firstAlarm
        alarmTimesText = plan.alarmTimes.map(WakePlanner.format).joined(separator: ", ")
        alarmDates = plan.alarmTimes
        needsClockAlarms = plan.hasAlarm && SettingsStore.shared.settings.alarmStyle == .clock
        reason = plan.reason
        warnings = plan.warnings.joined(separator: "\n")
        homeAssistantJSON = Self.homeAssistantJSON(for: plan)
    }

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(
            title: LocalizedStringResource(stringLiteral: hasAlarm ? "Alarms at \(alarmTimesText)" : "No alarm"),
            subtitle: LocalizedStringResource(stringLiteral: reason)
        )
    }

    static func homeAssistantJSON(for plan: WakePlan, buffer: Int = SettingsStore.shared.settings.arrivalBufferMinutes) -> String {
        let iso = ISO8601DateFormatter()
        iso.timeZone = .current
        var body: [String: Any] = [
            "has_alarm": plan.hasAlarm,
            "alarm_cause": plan.cause,
            "reason": plan.reason,
            "alarm_times": plan.alarmTimes.map { iso.string(from: $0) },
        ]
        if let first = plan.firstAlarm { body["alarm_time"] = iso.string(from: first) }
        if let appointment = plan.appointment {
            body["appointment"] = [
                "title": appointment.title,
                "start": iso.string(from: appointment.start),
                "location": appointment.location,
                "leave_by": iso.string(from: appointment.leaveBy(bufferMinutes: buffer)),
                "drive_minutes": Int((appointment.travelSeconds / 60).rounded()),
                "drive_time_estimated": appointment.usedFallbackTravel,
            ]
        }
        if let weather = plan.weather {
            body["weather_extra"] = ["minutes": weather.minutes, "reason": weather.reason]
        }
        if let shift = plan.shift {
            body["shift"] = ["title": shift.title, "start": iso.string(from: shift.start)]
        }
        guard let data = try? JSONSerialization.data(withJSONObject: body, options: [.sortedKeys]) else { return "{}" }
        return String(decoding: data, as: UTF8.self)
    }
}
