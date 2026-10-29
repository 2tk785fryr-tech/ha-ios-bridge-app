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

/// The shape of a morning's alarm series: how many, how far apart, and whether the wake-up is
/// the first or last of them. Kept from the rule that built it (a shift's own pattern), so a
/// change makes the same shape (v0.4.1 item 3).
struct SeriesPattern: Codable, Equatable {
    var count: Int
    var spacingMinutes: Int
    var wakeIs: WakeTimeAlarm

    /// Read from a series as it was set: its count and spacing, and which end is the wake-up.
    static func from(series: [Date], wake: Date?, fallback: BridgeSettings) -> SeriesPattern {
        let sorted = series.sorted()
        guard let first = sorted.first, let last = sorted.last else {
            return SeriesPattern(count: fallback.alarmCount, spacingMinutes: fallback.alarmSpacingMinutes, wakeIs: fallback.wakeTimeIs)
        }
        let spacing = sorted.count > 1 ? Int((sorted[1].timeIntervalSince(first) / 60).rounded()) : fallback.alarmSpacingMinutes
        let wakeIs: WakeTimeAlarm
        if let wake, abs(wake.timeIntervalSince(first)) < 60, sorted.count > 1 {
            wakeIs = .first
        } else if let wake, abs(wake.timeIntervalSince(last)) < 60 {
            wakeIs = .last
        } else {
            wakeIs = fallback.wakeTimeIs
        }
        return SeriesPattern(count: sorted.count, spacingMinutes: max(spacing, 1), wakeIs: wakeIs)
    }

    static func general(_ settings: BridgeSettings) -> SeriesPattern {
        SeriesPattern(count: settings.alarmCount, spacingMinutes: settings.alarmSpacingMinutes, wakeIs: settings.wakeTimeIs)
    }
}

struct MorningChange: Equatable {
    var choice: MorningChangeChoice
    /// Shift alarms only, or the entire wake-up (v0.4.1 item 7).
    var scope: MorningChangeScope = .wakeUp
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
        make(choice, currentWake: currentWake, pattern: .general(settings))
    }

    /// The new series in this morning's own pattern.
    static func make(_ choice: MorningChangeChoice, currentWake: Date, pattern: SeriesPattern) -> MorningChange {
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
            wakeTime: wake, count: pattern.count, spacingMinutes: pattern.spacingMinutes, wakeIs: pattern.wakeIs
        )
        return MorningChange(choice: choice, alarmTimes: times, newWake: wake,
                             delayMinutes: Int((wake.timeIntervalSince(currentWake) / 60).rounded()))
    }

    /// A change only makes sense if its first new alarm is still ahead.
    func isPossible(now: Date) -> Bool {
        alarmTimes.isEmpty || (alarmTimes.min() ?? now) > now.addingTimeInterval(60)
    }

    /// The backstop times after this change. Entire wake-up: all three move by the delay.
    /// Alarms only: deadline and late stay, and early moves to `earlyGap` minutes after the new
    /// last alarm if it would otherwise come before it. No alarms: unchanged.
    func backstops(_ current: [String: Date], earlyGap: Int = 5) -> [String: Date] {
        guard !alarmTimes.isEmpty else { return current }
        if scope == .alarms {
            var moved = current
            if let early = current["early"], let last = alarmTimes.max() {
                moved["early"] = max(early, last.addingTimeInterval(Double(earlyGap) * 60))
            }
            return moved
        }
        return current.mapValues { $0.addingTimeInterval(Double(delayMinutes) * 60) }
    }

    enum Limit: Equatable {
        case ok
        /// The last alarm is after the deadline backstop (allowed, with a warning).
        case afterDeadline(Date)
        /// The last alarm would be after the late backstop: not allowed for alarms only.
        case afterLate(Date)
    }

    /// Shift alarms only may never put the last alarm after the late backstop.
    func limit(backstops current: [String: Date]) -> Limit {
        guard scope == .alarms, let last = alarmTimes.max() else { return .ok }
        if let late = current["late"], last > late { return .afterLate(late) }
        if let deadline = current["deadline"], last > deadline { return .afterDeadline(deadline) }
        return .ok
    }

    /// The latest wake-up whose last alarm still isn't after `late`, in this pattern.
    static func latestWake(notAfter late: Date, pattern: SeriesPattern) -> Date {
        let span = Double((pattern.count - 1) * pattern.spacingMinutes) * 60
        return pattern.wakeIs == .last ? late : late.addingTimeInterval(-span)
    }

    /// Sleep In after this change, by Home Assistant's rule: on when the first alarm is after the
    /// curtains open. nil when unknown (no alarms, where you choose, or no curtain time).
    func sleepIn(curtainsOpenAt: Date?) -> Bool? {
        guard let first = alarmTimes.min(), let curtainsOpenAt else { return nil }
        return first > curtainsOpenAt
    }
}
