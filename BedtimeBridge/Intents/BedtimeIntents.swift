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
        "Sets your usual series of alarms (e.g. 3 alarms, 10 minutes apart) starting at the time you choose."
    )

    @Parameter(title: "First Alarm")
    var firstAlarm: Date

    static var parameterSummary: some ParameterSummary {
        Summary("Set wake-up alarms starting at \(\.$firstAlarm)")
    }

    @MainActor
    func perform() async throws -> some IntentResult & ReturnsValue<WakePlanEntity> {
        let plan = try await BedtimeCoordinator.shared.scheduleManual(firstAlarm: firstAlarm, settings: SettingsStore.shared.settings)
        return .result(value: WakePlanEntity(plan: plan))
    }
}

struct CancelWakeAlarmsIntent: AppIntent {
    static var title: LocalizedStringResource = "Cancel Wake-Up Alarms"
    static var description = IntentDescription("Removes every alarm Bedtime Bridge has set.")

    @MainActor
    func perform() async throws -> some IntentResult {
        try BedtimeCoordinator.shared.alarms.cancelAll()
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
