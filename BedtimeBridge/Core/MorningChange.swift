import Foundation

/// Item 3: moving this morning's alarms later (or earlier), or cancelling them.
enum MorningChangeChoice: Equatable, Hashable {
    case later(minutes: Int)
    case at(Date)
    case noAlarms
}

/// While snoozing (nothing in the house has changed yet) or after you're up (Wake Mike and Good
/// Morning ran, or the alarms were ended early): Home Assistant undoes different things.
enum MorningChangePhase: String {
    case snoozing
    case up
}

struct MorningChange: Equatable {
    var choice: MorningChangeChoice
    /// The new series: the usual count, spacing and "wake time is the first/last alarm".
    var alarmTimes: [Date]
    var newWake: Date?
    /// New wake-up minus the current one; the backstops move by the same amount.
    var delayMinutes: Int

    /// The wake-up the current series is built around: its last alarm, or its first.
    static func currentWake(series: [Date], wakeIs: WakeTimeAlarm) -> Date? {
        wakeIs == .last ? series.max() : series.min()
    }

    static func make(_ choice: MorningChangeChoice, currentWake: Date, settings: BridgeSettings) -> MorningChange {
        let wake: Date
        switch choice {
        case .noAlarms:
            return MorningChange(choice: choice, alarmTimes: [], newWake: nil, delayMinutes: 0)
        case .later(let minutes):
            wake = currentWake.addingTimeInterval(Double(minutes) * 60)
        case .at(let time):
            wake = time
        }
        let times = WakePlanner.alarmTimes(
            wakeTime: wake, count: settings.alarmCount, spacingMinutes: settings.alarmSpacingMinutes, wakeIs: settings.wakeTimeIs
        )
        return MorningChange(choice: choice, alarmTimes: times, newWake: wake,
                             delayMinutes: Int((wake.timeIntervalSince(currentWake) / 60).rounded()))
    }

    /// A change only makes sense if its first new alarm is still ahead.
    func isPossible(now: Date) -> Bool {
        alarmTimes.isEmpty || (alarmTimes.min() ?? now) > now.addingTimeInterval(60)
    }

    /// The backstop times after this change: moved by the delay, or unchanged with no alarms.
    func backstops(_ current: [String: Date]) -> [String: Date] {
        guard !alarmTimes.isEmpty else { return current }
        return current.mapValues { $0.addingTimeInterval(Double(delayMinutes) * 60) }
    }

    /// Sleep In after this change, by Home Assistant's rule: on when the first alarm is after the
    /// curtains open. nil when unknown (no alarms, where you choose, or no curtain time).
    func sleepIn(curtainsOpenAt: Date?) -> Bool? {
        guard let first = alarmTimes.min(), let curtainsOpenAt else { return nil }
        return first > curtainsOpenAt
    }
}
