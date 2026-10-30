import AppIntents

/// v0.4.6 item 2: I'm awake by Siri, on a morning with no alarms.
struct ImAwakeIntent: AppIntent {
    static var title: LocalizedStringResource = "I'm Awake"
    static var description = IntentDescription("On a morning with no alarms: Sleep In off, Awake For Day on, the house disarmed and Good Morning run in Home Assistant.")

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let outcome = await BedtimeCoordinator.shared.imAwake(settings: SettingsStore.shared.settings)
        return .result(dialog: "\(NoAlarmMorning.dialog(outcome))")
    }
}
