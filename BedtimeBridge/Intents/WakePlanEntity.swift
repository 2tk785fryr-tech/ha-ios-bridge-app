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

    /// When you need to be up (the last or first alarm, per Settings).
    @Property(title: "Wake-Up Time")
    var wakeTime: Date?

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
        wakeTime = nil
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
        wakeTime = plan.wakeTime
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

    static func homeAssistantJSON(for plan: WakePlan) -> String {
        let body = plan.homeAssistantPayload(settings: SettingsStore.shared.settings)
        guard let data = try? JSONSerialization.data(withJSONObject: body, options: [.sortedKeys]) else { return "{}" }
        return String(decoding: data, as: UTF8.self)
    }
}
