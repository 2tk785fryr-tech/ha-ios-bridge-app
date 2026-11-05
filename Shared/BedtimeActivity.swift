import ActivityKit
import Foundation

/// The app's own Live Activities: wind-down ("Bed in 42 min · first alarm 4:20", v0.4.3 item
/// 5), the morning's leave-by countdown (item 14) and a nap (v0.4.9 item 3). Separate from
/// AlarmKit's snooze one.
struct BedtimeActivityAttributes: ActivityAttributes {
    enum Kind: String, Codable, Hashable { case windDown, morning, nap }

    struct ContentState: Codable, Hashable {
        var kind: Kind
        var goToBed: Date?
        var firstAlarm: Date?
        // Morning (item 14)
        var leaveBy: Date?
        var driveMinutes: Int?
        var worstCaseMinutes: Int?
        /// "Rain · 58°" at leave time.
        var driveWeather: String?
        /// "Cloudy · 71°/55° · rain after 3 PM"
        var dayWeather: String?
        var nextBackstopName: String?
        var nextBackstop: Date?
        // Nap (v0.4.9 item 3): `firstAlarm` is when it's up.
        var snoozedUntil: Date?
        // v0.4.11 item 20: left home ("On your way"), and when the event starts.
        var departed: Date?
        var eventStart: Date?
    }

    var title: String
}

/// v0.4.11 item 17: the Dynamic Island's compact countdown, minutes and seconds even over an
/// hour (65:00), so it never needs the width of 1:05:00.
enum CompactCountdown {
    static func label(_ seconds: TimeInterval) -> String {
        let total = max(0, Int(seconds.rounded(.up)))
        return "\(total / 60):" + String(format: "%02d", total % 60)
    }
}

/// v0.4.11 item 20: what the morning activity's headline says.
enum MorningHeadline: Equatable {
    case leaveIn(Date)
    case pastLeaveTime(Date)
    case onYourWay(start: Date?)

    static func of(_ state: BedtimeActivityAttributes.ContentState, stale: Bool, now: Date = .now) -> MorningHeadline? {
        if state.departed != nil { return .onYourWay(start: state.eventStart) }
        guard let leave = state.leaveBy else { return nil }
        return stale || leave <= now ? .pastLeaveTime(leave) : .leaveIn(leave)
    }
}
