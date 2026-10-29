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
    /// Exactly the alarms (and backstops) set in Wake at a different time (v0.4.1 item 18).
    case exactly(SkipReplacement)
}

/// "Set alarms for a different time" in place of a skipped morning's alarms, so later plans
/// (the bedtime shortcut, a re-plan) keep it instead of clearing it.
struct SkipReplacement: Codable, Equatable {
    var wake: Date
    var wakeIs: WakeTimeAlarm
    /// Exactly these alarms, as set in Wake at a different time's preview (v0.4.1 item 18).
    var times: [Date]? = nil
    /// Backstops for your own alarm (item 14), and any times edited in the preview.
    var backstops: Bool? = nil
    var customBackstops: [String: Date]? = nil
}
