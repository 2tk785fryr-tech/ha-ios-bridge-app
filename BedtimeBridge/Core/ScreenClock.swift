import Foundation

/// When Tonight redraws by itself (v0.4.6 item 3). Every time the screen depends on (5:00 PM,
/// 4:00 AM, wind-down, go to bed, the morning windows, alarms, Undo) falls on a whole minute, so
/// it checks at each minute while it's open instead of waiting for a tap.
enum ScreenClock {
    /// 5:00 PM until 4:00 AM: the evening bar.
    static func isEvening(_ now: Date, calendar: Calendar = .current) -> Bool {
        let hour = calendar.component(.hour, from: now)
        return hour >= 17 || hour < 4
    }

    /// Seconds from `now` to the next whole minute (never zero, so it doesn't spin).
    static func secondsToNextMinute(_ now: Date, calendar: Calendar = .current) -> TimeInterval {
        let next = calendar.nextDate(after: now, matching: DateComponents(second: 0), matchingPolicy: .nextTime) ?? now.addingTimeInterval(60)
        return max(next.timeIntervalSince(now), 0.5)
    }

    /// The moments Tonight's bar changes at that only Home Assistant's reply would otherwise
    /// bring: an alarm's time, Start wind-down now appearing, wind-down and go to bed.
    static func moments(alarms: [Date], windDown: WindDownState?, startWindDownHours: Int) -> [Date] {
        var times = alarms
        if let w = windDown {
            times += [w.windDown, w.goToBed, w.goToBed?.addingTimeInterval(-Double(startWindDownHours) * 3600)].compactMap { $0 }
        }
        return times
    }

    /// One of `moments` fell after `from` and by `to` (the last tick and this one).
    static func passed(_ moments: [Date], from: Date, to: Date) -> Bool {
        moments.contains { $0 > from && $0 <= to }
    }

    /// What the screen shows from the phone's own state; when one of these changes at a tick,
    /// the screen refreshes fully (and asks Home Assistant again).
    struct Windows: Equatable {
        var napAlarms: [UUID] = []
        var alarmsSet: [Date] = []
        var upEarly = false
        var backToBed = false
        var notReadyForBed = false
        var sleepLater = false
        var undo = false
        var evening = false
    }
}
