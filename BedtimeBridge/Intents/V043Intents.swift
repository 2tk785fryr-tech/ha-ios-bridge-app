import AppIntents
import Foundation

/// v0.4.3 item 11: Siri and Shortcuts actions for the new features. Anything that turns alarms
/// off or changes them asks for confirmation first.

/// A nap length from Settings → Nap's quick choices.
struct NapLengthEntity: AppEntity {
    static var typeDisplayRepresentation: TypeDisplayRepresentation = "Nap Length"
    static var defaultQuery = NapLengthQuery()
    let minutes: Int
    var id: Int { minutes }
    var displayRepresentation: DisplayRepresentation { DisplayRepresentation(title: "\(NapPlanner.lengthName(minutes))") }
}

struct NapLengthQuery: EntityQuery {
    func entities(for identifiers: [Int]) async throws -> [NapLengthEntity] { identifiers.map(NapLengthEntity.init) }

    @MainActor
    func suggestedEntities() async throws -> [NapLengthEntity] { SettingsStore.shared.settings.napLengths.map(NapLengthEntity.init) }
}

struct NapIntent: AppIntent {
    static var title: LocalizedStringResource = "Nap"
    static var description = IntentDescription("Sets nap alarms for this length, checked against what's later today.")

    @Parameter(title: "Length")
    var length: NapLengthEntity

    static var parameterSummary: some ParameterSummary { Summary("Nap \(\.$length)") }

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let settings = SettingsStore.shared.settings
        let coordinator = BedtimeCoordinator.shared
        let limit = await coordinator.napLimit(settings: settings)
        // The same check as the nap screen: the last nap alarm by the latest wake.
        guard NapPlanner.fits(minutes: length.minutes, now: .now, count: settings.napAlarmCount, spacing: settings.napSpacingMinutes, limit: limit) else {
            return .result(dialog: "That's too long. \(limit?.text ?? "")")
        }
        try await coordinator.startNap(minutes: length.minutes, settings: settings)
        let times = coordinator.napAlarms.map { WakePlanner.format($0.time) }.joined(separator: " and ")
        return .result(dialog: "Nap set. Alarms at \(times).")
    }
}

struct NoAlarmsTomorrowIntent: AppIntent {
    static var title: LocalizedStringResource = "No Alarms Tomorrow"
    static var description = IntentDescription("Clears tomorrow's alarms (temporary and nap alarms stay). Undo in the app until bedtime runs.")

    @Parameter(title: "Sleep In", default: true)
    var sleepIn: Bool

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let coordinator = BedtimeCoordinator.shared
        let settings = SettingsStore.shared.settings
        let plan = try? await coordinator.buildPlan(settings: settings)
        let morning = coordinator.noAlarmsMorning(plan: plan)
        let day = morning.formatted(.dateTime.weekday(.wide))
        let shift = coordinator.shiftOnCalendar(morning: morning, settings: settings)
        try await requestConfirmation(dialog: "Turn off \(day)'s alarms? \(NoAlarmsSheet.backstopNote(shift: shift))")
        try await coordinator.noAlarmsTomorrow(morning: morning, sleepIn: sleepIn, settings: settings)
        return .result(dialog: "No alarms \(day) morning. Undo in Bedtime Bridge until bedtime runs.")
    }
}

enum SleepLaterAmount: String, AppEnum {
    case thirty, hour, twoHours, eightHours

    static var typeDisplayRepresentation: TypeDisplayRepresentation = "Sleep Later"
    static var caseDisplayRepresentations: [SleepLaterAmount: DisplayRepresentation] = [
        .thirty: "30 minutes", .hour: "an hour", .twoHours: "2 hours", .eightHours: "8 hours from now",
    ]

    var choice: MorningChangeChoice {
        switch self {
        case .thirty: .later(minutes: 30)
        case .hour: .later(minutes: 60)
        case .twoHours: .later(minutes: 120)
        case .eightHours: .at(Date.now.addingTimeInterval(8 * 3600))
        }
    }
}

struct SleepLaterIntent: AppIntent {
    static var title: LocalizedStringResource = "Sleep Later"
    static var description = IntentDescription("Moves tonight's alarms later in the same pattern, before bed. Leave-by and the deadline and late backstops stay.")

    @Parameter(title: "Amount")
    var amount: SleepLaterAmount

    static var parameterSummary: some ParameterSummary { Summary("Sleep later \(\.$amount)") }

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let coordinator = BedtimeCoordinator.shared
        let settings = SettingsStore.shared.settings
        guard coordinator.sleepLaterAvailable(settings: settings), let wake = coordinator.currentWake(settings: settings) else {
            return .result(dialog: "There are no alarms to move tonight.")
        }
        var change = MorningChange.make(amount.choice, currentWake: wake, pattern: coordinator.seriesPattern(settings: settings))
        change.scope = .alarms
        let context = await coordinator.morningContext(firstAlarm: change.alarmTimes.first, settings: settings)
        let limit = context?.ladderArmed == true && !(context?.backstops.isEmpty ?? true)
            ? change.limit(backstops: context!.backstops)
            : change.limit(leaveBy: NextAlarmSnapshot.load().leaveBy, getReadyMinutes: settings.getReadyMinutes)
        if case .afterLate(let late) = limit {
            return .result(dialog: "That's after the late backstop at \(WakePlanner.format(late)). Pick less, or change the morning in the app.")
        }
        let first = change.alarmTimes.first.map(WakePlanner.format) ?? ""
        try await requestConfirmation(dialog: "Move tonight's alarms to start at \(first)?")
        try await coordinator.sleepLater(change, reason: nil, settings: settings)
        return .result(dialog: "Alarms moved. First alarm \(first).")
    }
}

struct StartWindDownIntent: AppIntent {
    static var title: LocalizedStringResource = "Start Wind-Down"
    static var description = IntentDescription("Starts tonight's wind-down now. Go to bed stays the same.")

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let state = try await BedtimeCoordinator.shared.windDownAction("start", settings: SettingsStore.shared.settings)
        guard state.status == .windingDown else { return .result(dialog: "There's no wind-down to start tonight.") }
        return .result(dialog: "Winding down. Bed at \(state.goToBed.map(WakePlanner.format) ?? "the usual time").")
    }
}

struct CancelWindDownIntent: AppIntent {
    static var title: LocalizedStringResource = "Cancel Wind-Down"
    static var description = IntentDescription("Cancels tonight's wind-down: the helper goes off and there's no go to bed notification or reminders.")

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        try await requestConfirmation(dialog: "Cancel tonight's wind-down?")
        try await BedtimeCoordinator.shared.windDownAction("cancel", settings: SettingsStore.shared.settings)
        return .result(dialog: "Tonight's wind-down is cancelled.")
    }
}

struct AddLeaveIntent: AppIntent {
    static var title: LocalizedStringResource = "Add Vacation"
    static var description = IntentDescription("Adds one all-day vacation event (one of your vacation titles), first day through last, to the Calendar for new events.")

    @Parameter(title: "First Day")
    var first: Date

    @Parameter(title: "Last Day")
    var last: Date

    /// v0.4.7 item 6: which vacation title; asked when there's more than one.
    @Parameter(title: "Kind", optionsProvider: VacationTitleOptions())
    var kind: String?

    @Parameter(title: "Travelling", default: false)
    var travelling: Bool

    static var parameterSummary: some ParameterSummary {
        Summary("Add \(\.$kind) from \(\.$first) to \(\.$last)") { \.$travelling }
    }

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let settings = SettingsStore.shared.settings
        let service = BedtimeCoordinator.shared.calendar
        try await service.ensureAccess()
        let titles = settings.leaveTitles.isEmpty ? ["Leave"] : settings.leaveTitles
        let title: String
        if let kind, titles.contains(kind) {
            title = kind
        } else if titles.count == 1 {
            title = titles[0]
        } else {
            title = try await $kind.requestDisambiguation(among: titles, dialog: "Which kind?")
        }
        let text = LeaveDays.describe(title: title, first: first, last: last,
                                      calendarName: service.newEventsCalendar(settings: settings)?.title ?? "your calendar") + (travelling ? ", travelling" : "")
        try await requestConfirmation(dialog: "Add \(text)?")
        _ = try service.addVacation(title: title, first: first, last: last, travelling: travelling, settings: settings)
        await BedtimeCoordinator.shared.scheduleBackToWork(settings: settings)
        return .result(dialog: "Added: \(text).")
    }
}

/// The vacation titles from Settings → Vacations, for Siri and Shortcuts.
struct VacationTitleOptions: DynamicOptionsProvider {
    func results() async throws -> [String] {
        let titles = SettingsStore.shared.settings.leaveTitles
        return titles.isEmpty ? ["Leave"] : titles
    }
}

struct AddWakeUpEventIntent: AppIntent {
    static var title: LocalizedStringResource = "Add a Wake-Up Event"
    static var description = IntentDescription("Adds an event marked with the wake-up keyword, so it decides the wake-up, and shows the new plan.")

    @Parameter(title: "Title")
    var title: String

    @Parameter(title: "Starts")
    var start: Date

    @Parameter(title: "Length (minutes)", default: 60)
    var minutes: Int

    @Parameter(title: "Location")
    var location: String?

    static var parameterSummary: some ParameterSummary {
        Summary("Add \(\.$title) at \(\.$start)") { \.$minutes; \.$location }
    }

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let settings = SettingsStore.shared.settings
        let coordinator = BedtimeCoordinator.shared
        try await coordinator.calendar.ensureAccess()
        let event = NewWakeUpEvent(title: title, day: start, start: start, lengthMinutes: minutes, location: location ?? "")
        _ = try coordinator.calendar.addWakeUpEvent(event, mapItem: nil, settings: settings)
        let plan = try? await coordinator.buildPlan(settings: settings)
        let wake = plan?.firstAlarm.map { " The plan's first alarm would be \(WakePlanner.format($0)); open the app to set it." } ?? ""
        return .result(dialog: "Added \(title).\(wake)")
    }
}

/// RUN_MORNING_UPDATE (v0.4.3 item 14): Home Assistant sends it hourly on a leave-by morning and
/// when you leave home; this refreshes the morning Live Activity, or ends it.
struct MorningUpdateIntent: AppIntent {
    static var title: LocalizedStringResource = "Morning Update"
    static var description = IntentDescription("Refreshes the morning Live Activity (drive, weather, next backstop), or ends it once you've left home.")

    @MainActor
    func perform() async throws -> some IntentResult {
        await BedtimeCoordinator.shared.updateMorningActivity(settings: SettingsStore.shared.settings)
        return .result()
    }
}
