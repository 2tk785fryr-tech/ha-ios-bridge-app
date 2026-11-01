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
    }

    var title: String
}
