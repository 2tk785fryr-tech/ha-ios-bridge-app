import AppIntents
import Foundation

/// Step 1 of the bedtime shortcut: replaces the calendar, maps and alarm actions.
struct PlanWakeAlarmsIntent: AppIntent {
    static var title: LocalizedStringResource = "Plan Wake-Up Alarms"
    static var description = IntentDescription(
        "Finds your next shift and any appointment noted \"wake up\", works out drive time with expected traffic, and sets your alarms."
    )

    @Parameter(title: "Set Alarms", description: "Turn off to only preview the plan.", default: true)
    var setAlarms: Bool

    static var parameterSummary: some ParameterSummary {
        Summary("Plan wake-up alarms") {
            \.$setAlarms
        }
    }

    /// Never asks anything: the bedtime shortcut runs with nobody tapping. Questions (like a
    /// "wake up" appointment with no location) arrive as notifications instead.
    @MainActor
    func perform() async throws -> some IntentResult & ReturnsValue<WakePlanEntity> {
        let settings = SettingsStore.shared.settings
        let coordinator = BedtimeCoordinator.shared
        let plan = setAlarms
            ? try await coordinator.planAndSchedule(settings: settings)
            : try await coordinator.buildPlan(settings: settings)
        return .result(value: WakePlanEntity(plan: plan))
    }
}

/// The day-off path: the shortcut asks for a time, this sets the alarm series.
struct SetWakeAlarmsIntent: AppIntent {
    static var title: LocalizedStringResource = "Set Wake-Up Alarms"
    static var description = IntentDescription(
        "Sets your usual series of alarms (e.g. 3 alarms, 10 minutes apart) around the wake-up time you choose. By default it's the last alarm, so the others go off earlier."
    )

    @Parameter(title: "Wake-Up Time")
    var wakeTime: Date

    @Parameter(title: "Time Is", description: "Whether the time is your first or last alarm. Default: the setting in the app.")
    var timeIs: WakeTimeChoice?

    static var parameterSummary: some ParameterSummary {
        Summary("Set wake-up alarms for \(\.$wakeTime)") {
            \.$timeIs
        }
    }

    @MainActor
    func perform() async throws -> some IntentResult & ReturnsValue<WakePlanEntity> {
        let plan = try await BedtimeCoordinator.shared.scheduleManual(
            wakeTime: wakeTime,
            wakeIs: timeIs?.wakeTimeAlarm,
            settings: SettingsStore.shared.settings
        )
        return .result(value: WakePlanEntity(plan: plan))
    }
}

enum WakeTimeChoice: String, AppEnum {
    case first
    case last

    static var typeDisplayRepresentation: TypeDisplayRepresentation = "Time Is"
    static var caseDisplayRepresentations: [WakeTimeChoice: DisplayRepresentation] = [
        .first: "First alarm",
        .last: "Last alarm",
    ]

    var wakeTimeAlarm: WakeTimeAlarm { self == .first ? .first : .last }
}

/// An extra alarm that doesn't replace or turn off the regular ones: up early for the trash
/// or a call, then back to bed.
struct SetTemporaryAlarmIntent: AppIntent {
    static var title: LocalizedStringResource = "Set Temporary Alarm"
    static var description = IntentDescription(
        "One extra alarm beside your regular ones. Stopping it leaves Awake For Day, Sleep In and the regular alarms alone. With Disarm, Home Assistant disarms the house alarm and re-arms it once you're back in bed."
    )

    @Parameter(title: "Time")
    var time: Date

    @Parameter(title: "House Alarm", default: .disarm)
    var houseAlarm: TemporaryHouseAlarm

    static var parameterSummary: some ParameterSummary {
        Summary("Set a temporary alarm at \(\.$time) and \(\.$houseAlarm)")
    }

    @MainActor
    func perform() async throws -> some IntentResult & ReturnsValue<Date> {
        let alarm = try await BedtimeCoordinator.shared.setTemporaryAlarm(
            at: time,
            disarmHouse: houseAlarm == .disarm,
            settings: SettingsStore.shared.settings
        )
        return .result(value: alarm.time)
    }
}

/// Bedtime away from home: speaks your alarms, tomorrow's weather where you are and whether
/// everything at home is good. Runs nothing in the house.
struct AwayBedtimeSummaryIntent: AppIntent {
    static var title: LocalizedStringResource = "Away Bedtime Summary"
    static var description = IntentDescription(
        "For bedtime away from home: your alarms, tomorrow's weather where you are, and a check of the house (alarm still armed, doors and garage closed). Says \"Everything at home is good\" when it is. Changes nothing."
    )

    @Parameter(title: "House Alarm", description: "The house alarm's state, e.g. from your alarm app's Get State action.")
    var houseAlarm: String?

    @Parameter(title: "Sign-Off", default: "Good night.")
    var signOff: String

    static var parameterSummary: some ParameterSummary {
        Summary("Away bedtime summary with house alarm \(\.$houseAlarm)") {
            \.$signOff
        }
    }

    @MainActor
    func perform() async throws -> some IntentResult & ReturnsValue<String> {
        let text = await BedtimeCoordinator.shared.awaySummary(houseAlarm: houseAlarm, signOff: signOff, settings: SettingsStore.shared.settings)
        return .result(value: text)
    }
}

enum TemporaryHouseAlarm: String, AppEnum {
    case disarm
    case keepArmed

    static var typeDisplayRepresentation: TypeDisplayRepresentation = "House Alarm"
    static var caseDisplayRepresentations: [TemporaryHouseAlarm: DisplayRepresentation] = [
        .disarm: "disarm, then re-arm",
        .keepArmed: "keep it armed",
    ]
}

struct CancelWakeAlarmsIntent: AppIntent {
    static var title: LocalizedStringResource = "Cancel Wake-Up Alarms"
    static var description = IntentDescription("Removes every alarm Bedtime Bridge has set and the leave-by reminder.")

    @MainActor
    func perform() async throws -> some IntentResult {
        try await BedtimeCoordinator.shared.cancelAlarms(settings: SettingsStore.shared.settings)
        return .result()
    }
}

/// Standalone helper for other shortcuts: drive time with traffic predicted for a given arrival.
struct GetDriveTimeIntent: AppIntent {
    static var title: LocalizedStringResource = "Get Drive Time"
    static var description = IntentDescription(
        "Minutes of driving from home to a place, using the traffic Apple Maps expects when you'd be on the road."
    )

    @Parameter(title: "Destination")
    var destination: String

    @Parameter(title: "Arrive By")
    var arrival: Date

    static var parameterSummary: some ParameterSummary {
        Summary("Drive time to \(\.$destination) arriving by \(\.$arrival)")
    }

    @MainActor
    func perform() async throws -> some IntentResult & ReturnsValue<Int> {
        let minutes = try await BedtimeCoordinator.shared.drivingMinutes(
            to: destination, arrivingAt: arrival, settings: SettingsStore.shared.settings
        )
        return .result(value: minutes)
    }
}

/// Replaces the shortcut's HomeKit "turn on Bedtime Routine" step: Home Assistant runs the
/// bedtime routine only if you're home.
struct StartBedtimeRoutineIntent: AppIntent {
    static var title: LocalizedStringResource = "Start Bedtime Routine"
    static var description = IntentDescription(
        "Turns on your bedtime routine in Home Assistant, but only when you're home. Returns whether it started."
    )

    @MainActor
    func perform() async throws -> some IntentResult & ReturnsValue<Bool> {
        let result = try await BedtimeCoordinator.shared.startBedtime(settings: SettingsStore.shared.settings)
        return .result(value: result.started)
    }
}

enum ClockAlarmEvent: String, AppEnum {
    case snoozed
    case stopped

    static var typeDisplayRepresentation: TypeDisplayRepresentation = "Alarm Event"
    static var caseDisplayRepresentations: [ClockAlarmEvent: DisplayRepresentation] = [
        .snoozed: "Snoozed",
        .stopped: "Stopped",
    ]
}

/// Clock app mode: use in the "Alarm is snoozed/stopped" personal automations instead of
/// setting the helpers through HomeKit, so the home check and HA events still apply.
struct ReportAlarmEventIntent: AppIntent {
    static var title: LocalizedStringResource = "Report Alarm Event"
    static var description = IntentDescription(
        "Tells Home Assistant a Clock app alarm was snoozed or stopped. It runs your wake-up routine only if you're home."
    )

    @Parameter(title: "Event")
    var event: ClockAlarmEvent

    static var parameterSummary: some ParameterSummary {
        Summary("Report alarm \(\.$event)")
    }

    @MainActor
    func perform() async throws -> some IntentResult {
        await BedtimeCoordinator.shared.clockAlarmEvent(event == .snoozed ? .snoozed : .stopped, settings: SettingsStore.shared.settings)
        return .result()
    }
}

struct BedtimeBridgeShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: PlanWakeAlarmsIntent(),
            phrases: ["Plan my wake up with \(.applicationName)", "Set my \(.applicationName) alarms"],
            shortTitle: "Plan Wake-Up",
            systemImageName: "alarm"
        )
        AppShortcut(
            intent: CancelWakeAlarmsIntent(),
            phrases: ["Cancel my \(.applicationName) alarms"],
            shortTitle: "Cancel Alarms",
            systemImageName: "alarm.waves.left.and.right"
        )
    }
}
