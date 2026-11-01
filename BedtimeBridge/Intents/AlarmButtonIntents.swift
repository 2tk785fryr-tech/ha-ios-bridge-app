import AlarmKit
import AppIntents
import Foundation

/// Runs when you tap Stop on a Bedtime Bridge alarm's banner or Lock Screen. It never ends the
/// alarm (v0.4.10 item 3): it snoozes, onto the next alarm if that rings first, and opens the
/// app's Stop screen, where the slide ends this alarm and the hold ends them all.
struct StopWakeAlarmIntent: LiveActivityIntent {
    static var title: LocalizedStringResource = "Stop Wake-Up Alarm"
    static var isDiscoverable = false
    /// Comes to the front for the Stop screen when it can.
    static var supportedModes: IntentModes = [.background, .foreground(.dynamic)]

    @Parameter(title: "Alarm ID")
    var alarmID: String

    /// What the alarm was set for (`nap`, `temporary`, `test`, or the plan's cause), so the app
    /// knows even when AlarmKit has already removed it (v0.4.9 item 4).
    @Parameter(title: "Cause")
    var cause: String?

    init() {}

    init(alarmID: UUID, cause: String? = nil) {
        self.alarmID = alarmID.uuidString
        self.cause = cause
    }

    @MainActor
    func perform() async throws -> some IntentResult {
        guard let id = UUID(uuidString: alarmID),
              let snoozed = await BedtimeCoordinator.shared.bannerStopped(id: id, cause: cause, settings: SettingsStore.shared.settings) else {
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

    /// What the alarm was set for (`nap`, `temporary`, `test`, or the plan's cause), so the app
    /// knows even when AlarmKit has already removed it (v0.4.9 item 4).
    @Parameter(title: "Cause")
    var cause: String?

    init() {}

    init(alarmID: UUID, cause: String? = nil) {
        self.alarmID = alarmID.uuidString
        self.cause = cause
    }

    @MainActor
    func perform() async throws -> some IntentResult {
        if let id = UUID(uuidString: alarmID) {
            await BedtimeCoordinator.shared.alarmSnoozed(id: id, cause: cause, settings: SettingsStore.shared.settings)
        }
        return .result()
    }
}
