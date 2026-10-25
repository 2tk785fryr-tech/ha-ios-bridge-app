import AlarmKit
import AppIntents
import Foundation

/// Runs when you tap Stop on a Bedtime Bridge alarm: tells Home Assistant (Wake Sequence),
/// cancels the rest of the series and rechecks traffic for a leave-by reminder.
struct StopWakeAlarmIntent: LiveActivityIntent {
    static var title: LocalizedStringResource = "Stop Wake-Up Alarm"
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
            await BedtimeCoordinator.shared.alarmStopped(id: id, settings: SettingsStore.shared.settings)
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
