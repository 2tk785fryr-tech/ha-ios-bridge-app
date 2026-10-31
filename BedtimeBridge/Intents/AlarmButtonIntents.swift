import AlarmKit
import AppIntents
import Foundation

/// Runs when you tap Stop on a Bedtime Bridge alarm's banner or Lock Screen. From v0.4.8
/// item 4 it snoozes instead and opens the app's Stop screen, where the slide-and-hold ends the
/// alarms (and Home Assistant gets the stop, Good Morning and the leave-by re-check).
struct StopWakeAlarmIntent: LiveActivityIntent {
    static var title: LocalizedStringResource = "Stop Wake-Up Alarm"
    static var isDiscoverable = false
    /// Comes to the front for the Stop screen when it can.
    static var supportedModes: IntentModes = [.background, .foreground(.dynamic)]

    @Parameter(title: "Alarm ID")
    var alarmID: String

    init() {}

    init(alarmID: UUID) {
        self.alarmID = alarmID.uuidString
    }

    @MainActor
    func perform() async throws -> some IntentResult {
        guard let id = UUID(uuidString: alarmID),
              let snoozed = await BedtimeCoordinator.shared.bannerStopped(id: id, settings: SettingsStore.shared.settings) else {
            return .result()
        }
        do {
            try await continueInForeground(nil, alwaysConfirm: false)
        } catch {
            await BannerStop.notify(id: snoozed.id, ringsAgain: snoozed.ringsAgain)
        }
        return .result()
    }
}

/// Runs when you tap Snooze: tells Home Assistant (Wake Snooze Fade). The system handles
/// the countdown and rings again after the snooze length from Settings.
struct SnoozeWakeAlarmIntent: LiveActivityIntent {
    static var title: LocalizedStringResource = "Snooze Wake-Up Alarm"
    static var isDiscoverable = false

    @Parameter(title: "Alarm ID")
    var alarmID: String

    init() {}

    init(alarmID: UUID) {
        self.alarmID = alarmID.uuidString
    }

    @MainActor
    func perform() async throws -> some IntentResult {
        if let id = UUID(uuidString: alarmID) {
            await BedtimeCoordinator.shared.alarmSnoozed(id: id, settings: SettingsStore.shared.settings)
        }
        return .result()
    }
}
