import AlarmKit
import SwiftUI

struct WakeAlarmMetadata: AlarmMetadata {}

/// Sets real system alarms through AlarmKit: they ring through Silent mode and Focus like
/// Clock alarms, but they belong to this app and don't appear in the Clock app.
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
    func scheduledAlarmTimes() -> [Date] {
        let alarms = (try? manager.alarms) ?? []
        return alarms.compactMap { alarm -> Date? in
            if case .fixed(let date) = alarm.schedule { return date }
            return nil
        }
        .sorted()
    }

    /// Replaces every alarm this app owns with the given times, so re-running the
    /// bedtime routine never leaves stale alarms behind.
    func replaceAlarms(with times: [Date], title: String) async throws {
        try await ensureAccess()
        try cancelAll()

        let alert = AlarmPresentation.Alert(
            title: LocalizedStringResource(stringLiteral: title),
            stopButton: AlarmButton(text: "Stop", textColor: .white, systemImageName: "stop.circle")
        )
        let attributes = AlarmAttributes<WakeAlarmMetadata>(
            presentation: AlarmPresentation(alert: alert),
            metadata: WakeAlarmMetadata(),
            tintColor: .orange
        )

        for time in times where time > .now {
            let configuration = AlarmManager.AlarmConfiguration<WakeAlarmMetadata>.alarm(
                schedule: .fixed(time),
                attributes: attributes
            )
            _ = try await manager.schedule(id: UUID(), configuration: configuration)
        }
    }

    func cancelAll() throws {
        for alarm in try manager.alarms {
            try manager.cancel(id: alarm.id)
        }
    }
}
