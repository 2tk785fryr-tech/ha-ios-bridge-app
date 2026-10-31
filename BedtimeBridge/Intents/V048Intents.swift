import AppIntents

/// Good night (v0.4.8 item 5): Home Assistant sends RUN_BEDTIME, so the bedtime shortcut runs.
/// Siri can't slide and hold, so it asks first.
struct GoodNightIntent: AppIntent {
    static var title: LocalizedStringResource = "Good Night"
    static var description = IntentDescription("Starts bedtime now: Home Assistant sends the bedtime push, so I'm Ready For Bed - App runs and the house goes to bedtime. Asks first.")

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        try await requestConfirmation(dialog: "Start bedtime now? The lights will go off.")
        let outcome = await BedtimeCoordinator.shared.goodNight(settings: SettingsStore.shared.settings)
        return .result(dialog: "\(GoodNight.dialog(outcome))")
    }
}

enum WindDownChoice: String, AppEnum {
    case start
    case cancel

    static var typeDisplayRepresentation: TypeDisplayRepresentation = "Wind-Down"
    static var caseDisplayRepresentations: [WindDownChoice: DisplayRepresentation] = [
        .start: "Start",
        .cancel: "Cancel",
    ]
}

/// v0.4.8 item 13: Start and Cancel wind-down as one Siri shortcut, so Good night has a slot
/// (Apple allows 10). The two separate actions stay in the Shortcuts app.
struct WindDownIntent: AppIntent {
    static var title: LocalizedStringResource = "Start or Cancel Wind-Down"
    static var description = IntentDescription("Starts tonight's wind-down now, or cancels it.")

    @Parameter(title: "Wind-Down")
    var choice: WindDownChoice

    static var parameterSummary: some ParameterSummary {
        Summary("\(\.$choice) wind-down")
    }

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let settings = SettingsStore.shared.settings
        switch choice {
        case .start:
            let state = try await BedtimeCoordinator.shared.windDownAction("start", settings: settings)
            guard state.status == .windingDown else { return .result(dialog: "There's no wind-down to start tonight.") }
            return .result(dialog: "Winding down. Bed at \(state.goToBed.map(WakePlanner.format) ?? "the usual time").")
        case .cancel:
            try await requestConfirmation(dialog: "Cancel tonight's wind-down?")
            try await BedtimeCoordinator.shared.windDownAction("cancel", settings: settings)
            return .result(dialog: "Tonight's wind-down is cancelled.")
        }
    }
}
