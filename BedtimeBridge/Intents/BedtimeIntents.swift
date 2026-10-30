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
        "Sets your own alarms (Settings → Alarms → Your own alarms; e.g. 3 alarms, 10 minutes apart) from the wake-up time you choose. By default it's the first alarm, so the others go off later."
    )

    @Parameter(title: "Wake-Up Time")
    var wakeTime: Date

    @Parameter(title: "Time Is", description: "Whether the time is your first or last alarm. Default: Your own alarms' setting in the app.")
    var timeIs: WakeTimeChoice?

    static var parameterSummary: some ParameterSummary {
        Summary("Set wake-up alarms for \(\.$wakeTime)") {
            \.$timeIs
        }
    }

    @MainActor
    func perform() async throws -> some IntentResult & ReturnsValue<WakePlanEntity> {
        // Your own alarms' series, like Wake at a different time (v0.4.7 item 7).
        let settings = SettingsStore.shared.settings
        let own = OwnAlarmSeries.replacement(wake: BedtimeCoordinator.nextOccurrence(ofTimeIn: wakeTime), wakeIs: timeIs?.wakeTimeAlarm, settings: settings)
        let plan = try await BedtimeCoordinator.shared.scheduleManual(
            wakeTime: wakeTime,
            wakeIs: own.wakeIs,
            exactly: own,
            settings: settings
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

/// Up again after bedtime ran: alarms off, house disarmed, Awake For Day back on, Sleep In
/// off. Bedtime runs again once you're back in bed.
struct UndoBedtimeIntent: AppIntent {
    static var title: LocalizedStringResource = "Undo Bedtime"
    static var description = IntentDescription(
        "For getting up again after bedtime ran: turns off the regular alarms (temporary ones stay), and Home Assistant disarms the house, turns Awake For Day back on and Sleep In off. Once you're back in bed for a while, it runs your bedtime shortcut again."
    )

    @MainActor
    func perform() async throws -> some IntentResult {
        try await BedtimeCoordinator.shared.undoBedtime(settings: SettingsStore.shared.settings)
        return .result()
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

/// Run by Home Assistant's RUN_LEAVE_CHECK push at each leave reminder (v0.4.1 item 17): a fresh
/// drive time, a notification, and the new leave-by back to Home Assistant.
struct CheckDriveAndRemindIntent: AppIntent {
    static var title: LocalizedStringResource = "Check Drive and Remind"
    static var description = IntentDescription(
        "Re-checks this morning's drive with current traffic, notifies you when to leave, and tells Home Assistant the new leave-by. Run it from a \"When I receive a notification from Home Assistant\" automation for RUN_LEAVE_CHECK."
    )

    @MainActor
    func perform() async throws -> some IntentResult {
        let settings = SettingsStore.shared.settings
        await BedtimeCoordinator.shared.recheckDrive(notify: true, settings: settings)
        await BedtimeCoordinator.shared.commandRan(PhoneCommand.leaveCheck.rawValue, settings: settings)
        return .result()
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

/// The shortcuts Home Assistant's phone commands run, by the marker in their push.
enum PhoneCommand: String, AppEnum {
    case disarm = "RUN_DISARM"
    case armStay = "RUN_ARM_STAY"
    case goodMorning = "RUN_GOOD_MORNING"
    case bedtime = "RUN_BEDTIME"
    case backToBed = "RUN_BACK_TO_BED"
    case leaveCheck = "RUN_LEAVE_CHECK"
    case napStart = "RUN_NAP_START"
    case napEnd = "RUN_NAP_END"
    // v0.4.3 item 5
    case planPreview = "RUN_PLAN_PREVIEW"
    case windDown = "RUN_WIND_DOWN"
    case windDownCancel = "RUN_CANCEL_WIND_DOWN"
    // v0.4.3 item 14
    case morningUpdate = "RUN_MORNING_UPDATE"

    static var typeDisplayRepresentation: TypeDisplayRepresentation = "Phone Command"
    static var caseDisplayRepresentations: [PhoneCommand: DisplayRepresentation] = [
        .disarm: "Disarm (RUN_DISARM)",
        .armStay: "Arm Stay (RUN_ARM_STAY)",
        .goodMorning: "Good Morning (RUN_GOOD_MORNING)",
        .bedtime: "Bedtime (RUN_BEDTIME)",
        .backToBed: "Back to bed (RUN_BACK_TO_BED)",
        .leaveCheck: "Leave check (RUN_LEAVE_CHECK)",
        .napStart: "Nap start (RUN_NAP_START)",
        .napEnd: "Nap end (RUN_NAP_END)",
        .planPreview: "Preview tomorrow (RUN_PLAN_PREVIEW)",
        .windDown: "Wind down on (RUN_WIND_DOWN)",
        .windDownCancel: "Wind down off (RUN_CANCEL_WIND_DOWN)",
        .morningUpdate: "Morning update (RUN_MORNING_UPDATE)",
    ]
}

/// Where the shortcut is: started (first step), completed (last step), or it found the job
/// already done (Good Morning runs once a night). "ran" is Started, kept for steps added before
/// Completed existed.
enum ShortcutOutcome: String, AppEnum {
    case ran
    case completed
    case alreadyDone = "already_done"

    static var typeDisplayRepresentation: TypeDisplayRepresentation = "Outcome"
    static var caseDisplayRepresentations: [ShortcutOutcome: DisplayRepresentation] = [
        .ran: "Started",
        .completed: "Completed",
        .alreadyDone: "Already done",
    ]
}

/// The last step of a shortcut a phone command runs: tells Home Assistant it ran, so the
/// command's notification is taken off the phone.
struct ReportShortcutRanIntent: AppIntent {
    static var title: LocalizedStringResource = "Report Shortcut Ran"
    static var description = IntentDescription(
        "Put this first (Started) and last (Completed) in a shortcut that a Home Assistant phone command runs. Home Assistant clears that command's notification, and warns you if it starts but never completes."
    )

    @Parameter(title: "Command")
    var command: PhoneCommand

    @Parameter(title: "Outcome", description: "Started as the first step, Completed as the last. Already done: the shortcut got the push but had nothing to do, e.g. Good Morning already ran tonight.", default: .ran)
    var outcome: ShortcutOutcome

    static var parameterSummary: some ParameterSummary {
        Summary("Report \(\.$command): \(\.$outcome)")
    }

    @MainActor
    func perform() async throws -> some IntentResult {
        await BedtimeCoordinator.shared.commandRan(command.rawValue, outcome: outcome.rawValue, settings: SettingsStore.shared.settings)
        return .result()
    }
}

/// RUN_PLAN_PREVIEW (v0.4.3 item 5): plans tomorrow in the background without setting any
/// alarms, and tells Home Assistant the first alarm for tonight's wind-down.
struct PreviewTomorrowIntent: AppIntent {
    static var title: LocalizedStringResource = "Preview Tomorrow"
    static var description = IntentDescription(
        "Works out tomorrow's wake-up without setting alarms and sends the first alarm, cause, event and leave-by to Home Assistant for the wind-down."
    )

    @MainActor
    func perform() async throws -> some IntentResult & ReturnsValue<WakePlanEntity> {
        let plan = try await BedtimeCoordinator.shared.previewTomorrow(settings: SettingsStore.shared.settings)
        return .result(value: WakePlanEntity(plan: plan))
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
        // v0.4.3 item 11
        AppShortcut(
            intent: NapIntent(),
            phrases: ["Nap \(\.$length) with \(.applicationName)", "Start a \(.applicationName) nap", "Nap with \(.applicationName)"],
            shortTitle: "Nap",
            systemImageName: "powersleep"
        )
        AppShortcut(
            intent: NoAlarmsTomorrowIntent(),
            phrases: ["No alarms tomorrow in \(.applicationName)", "No \(.applicationName) alarms tomorrow"],
            shortTitle: "No Alarms Tomorrow",
            systemImageName: "alarm.slash"
        )
        AppShortcut(
            intent: SleepLaterIntent(),
            phrases: ["Sleep later \(\.$amount) with \(.applicationName)", "Sleep later with \(.applicationName)"],
            shortTitle: "Sleep Later",
            systemImageName: "clock.arrow.circlepath"
        )
        AppShortcut(
            intent: StartWindDownIntent(),
            phrases: ["Start wind-down in \(.applicationName)", "Start winding down with \(.applicationName)"],
            shortTitle: "Start Wind-Down",
            systemImageName: "moon.zzz"
        )
        AppShortcut(
            intent: CancelWindDownIntent(),
            phrases: ["Cancel wind-down in \(.applicationName)"],
            shortTitle: "Cancel Wind-Down",
            systemImageName: "moon.zzz.fill"
        )
        AppShortcut(
            intent: AddLeaveIntent(),
            phrases: ["Add leave in \(.applicationName)", "Add a vacation in \(.applicationName)"],
            shortTitle: "Add Vacation",
            systemImageName: "beach.umbrella"
        )
        // v0.4.6 item 2
        AppShortcut(
            intent: ImAwakeIntent(),
            phrases: ["I'm awake in \(.applicationName)", "Good morning with \(.applicationName)", "\(.applicationName) I'm awake"],
            shortTitle: "I'm Awake",
            systemImageName: "sun.horizon"
        )
        AppShortcut(
            intent: AddWakeUpEventIntent(),
            phrases: ["Add a wake-up event in \(.applicationName)"],
            shortTitle: "Add Wake-Up Event",
            systemImageName: "calendar.badge.plus"
        )
    }
}
