import Foundation

/// An extra wake-up that sits beside the regular alarms without replacing them: up early to
/// take the trash out or make a call, then back to bed. Stopping it leaves Awake For Day,
/// Sleep In and the rest of the series alone.
struct TemporaryAlarm: Codable, Equatable, Identifiable {
    let id: UUID
    let time: Date
    /// Disarm the house alarm when you stop it (and re-arm once you're back in bed), or
    /// leave it armed (a phone call you take in bed).
    let disarmHouse: Bool

    /// Sent to Home Assistant as `house_alarm`.
    var houseAlarm: String { disarmHouse ? "disarm" : "keep_armed" }
}

/// What to do instead when you skip the morning's planned wake-up.
enum SkipChoice: Equatable {
    case sleepIn
    /// Your own time, as the first or last alarm of the usual series.
    case wakeAt(Date, WakeTimeAlarm)
}

/// "Set alarms for a different time" in place of a skipped morning's alarms, so later plans
/// (the bedtime shortcut, a re-plan) keep it instead of clearing it.
struct SkipReplacement: Codable, Equatable {
    var wake: Date
    var wakeIs: WakeTimeAlarm
}
