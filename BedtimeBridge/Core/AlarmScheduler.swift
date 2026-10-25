import ActivityKit
import AlarmKit
import SwiftUI

/// Sets real system alarms through AlarmKit: they ring through Silent mode and Focus like
/// Clock alarms, but they belong to this app and don't appear in the Clock app (so the
/// Shortcuts "Alarm is snoozed/stopped" automations don't see them; the Snooze and Stop
/// buttons tell Home Assistant themselves instead).
final class AlarmScheduler {
    private let manager = AlarmManager.shared

    func ensureAccess() async throws {
        switch manager.authorizationState {
        case .authorized:
            return
        case .notDetermined:
            guard try await manager.requestAuthorization() == .authorized else { throw BridgeError.alarmAccessDenied }
        default:
            throw BridgeError.alarmAccessDenied
        }
    }

    /// Alarms this app currently has scheduled, earliest first.
    func scheduledAlarmTimes(excluding excluded: UUID? = nil) -> [Date] {
        scheduledAlarms().filter { $0.id != excluded }.map(\.date)
    }

    func scheduledAlarms() -> [(id: UUID, date: Date)] {
        let alarms = (try? manager.alarms) ?? []
        return alarms.compactMap { alarm -> (id: UUID, date: Date)? in
            if case .fixed(let date) = alarm.schedule { return (alarm.id, date) }
            return nil
        }
        .sorted { $0.date < $1.date }
    }

    /// Replaces every alarm this app owns with the given times, so re-running the
    /// bedtime routine never leaves stale alarms behind. Alarms in `keeping` (temporary
    /// wake-ups, the test alarm) are left alone.
    func replaceAlarms(with times: [Date], title: String, cause: String, snoozeMinutes: Int, sound: AlarmSound, keeping: Set<UUID> = []) async throws {
        try await ensureAccess()
        try cancelAll(keeping: keeping)

        let alert = AlarmPresentation.Alert(
            title: LocalizedStringResource(stringLiteral: title),
            secondaryButton: AlarmButton(text: "Snooze", textColor: .white, systemImageName: "zzz"),
            // Snooze starts a countdown of `postAlert` seconds, then the alarm rings again.
            secondaryButtonBehavior: .countdown
        )
        let presentation = AlarmPresentation(
            alert: alert,
            countdown: AlarmPresentation.Countdown(title: "Snoozing", pauseButton: nil),
            paused: nil
        )
        let attributes = AlarmAttributes<WakeAlarmMetadata>(
            presentation: presentation,
            metadata: WakeAlarmMetadata(cause: cause),
            tintColor: Theme.accent
        )

        for time in times where time > .now {
            let id = UUID()
            let configuration = AlarmManager.AlarmConfiguration<WakeAlarmMetadata>(
                countdownDuration: Alarm.CountdownDuration(preAlert: nil, postAlert: TimeInterval(max(snoozeMinutes, 1) * 60)),
                schedule: .fixed(time),
                attributes: attributes,
                stopIntent: StopWakeAlarmIntent(alarmID: id),
                secondaryIntent: SnoozeWakeAlarmIntent(alarmID: id),
                sound: alertSound(sound)
            )
            _ = try await manager.schedule(id: id, configuration: configuration)
        }
    }

    /// One alarm a couple of minutes out, alongside tonight's alarms (it doesn't replace them).
    func scheduleTest(at time: Date, snoozeMinutes: Int, sound: AlarmSound) async throws -> UUID {
        try await scheduleSingle(at: time, title: "Test alarm", cause: "test", snoozeMinutes: snoozeMinutes, sound: sound)
    }

    /// One alarm on its own, alongside the regular series, which it never replaces.
    func scheduleSingle(at time: Date, title: String, cause: String, snoozeMinutes: Int, sound: AlarmSound) async throws -> UUID {
        try await ensureAccess()
        let alert = AlarmPresentation.Alert(
            title: LocalizedStringResource(stringLiteral: title),
            secondaryButton: AlarmButton(text: "Snooze", textColor: .white, systemImageName: "zzz"),
            secondaryButtonBehavior: .countdown
        )
        let attributes = AlarmAttributes<WakeAlarmMetadata>(
            presentation: AlarmPresentation(alert: alert, countdown: AlarmPresentation.Countdown(title: "Snoozing", pauseButton: nil), paused: nil),
            metadata: WakeAlarmMetadata(cause: cause),
            tintColor: Theme.accent
        )
        let id = UUID()
        let configuration = AlarmManager.AlarmConfiguration<WakeAlarmMetadata>(
            countdownDuration: Alarm.CountdownDuration(preAlert: nil, postAlert: TimeInterval(max(snoozeMinutes, 1) * 60)),
            schedule: .fixed(time),
            attributes: attributes,
            stopIntent: StopWakeAlarmIntent(alarmID: id),
            secondaryIntent: SnoozeWakeAlarmIntent(alarmID: id),
            sound: alertSound(sound)
        )
        _ = try await manager.schedule(id: id, configuration: configuration)
        return id
    }

    private func alertSound(_ sound: AlarmSound) -> AlertConfiguration.AlertSound {
        sound.fileName.map { .named($0) } ?? .default
    }

    func cancel(_ id: UUID) { try? manager.cancel(id: id) }

    func cancelAll(keeping: Set<UUID> = []) throws {
        for alarm in try manager.alarms where !keeping.contains(alarm.id) {
            try manager.cancel(id: alarm.id)
        }
    }

    /// Cancels the rest of the series once you're up.
    func cancelAll(except keep: UUID, keeping: Set<UUID> = []) {
        for alarm in (try? manager.alarms) ?? [] where alarm.id != keep && !keeping.contains(alarm.id) {
            try? manager.cancel(id: alarm.id)
        }
    }

    // The system already does these when the alert buttons are tapped; calling them again
    // is harmless and covers the buttons on the Live Activity.
    func stop(_ id: UUID) { try? manager.stop(id: id) }
    func snooze(_ id: UUID) { try? manager.countdown(id: id) }
}
