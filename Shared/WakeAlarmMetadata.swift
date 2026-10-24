import AlarmKit

/// Shared by the app (which schedules alarms) and the widget extension (which draws the
/// snooze countdown on the Lock Screen and Dynamic Island).
struct WakeAlarmMetadata: AlarmMetadata {
    /// "Days", "Swings", "calendar", "automade"; shown under the countdown.
    var cause: String = ""
}
