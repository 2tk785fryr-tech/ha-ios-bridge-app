import Foundation

/// Wake at a different time (v0.4.1 item 18): the alarms and backstops shown in the preview,
/// before they're set.
struct OwnAlarmDraft: Hashable {
    var times: [Date]
    var wakeIs: WakeTimeAlarm
    var backstopsOn: Bool
    /// early / deadline / late; a removed one is absent.
    var backstops: [String: Date]
    /// The backstops were changed by hand (cleared when the alarms change).
    var backstopsEdited = false

    /// 6 hours from now, rounded UP to the interval (15: 6:54 → 7:00, 7:02 → 7:15; 0: exact).
    static func defaultTime(now: Date = .now, roundingMinutes: Int, calendar: Calendar = .current) -> Date {
        let later = now.addingTimeInterval(6 * 3600)
        guard roundingMinutes > 0 else { return later }
        let parts = calendar.dateComponents([.minute, .second, .nanosecond], from: later)
        let intoHour = Double((parts.minute ?? 0) * 60 + (parts.second ?? 0)) + Double(parts.nanosecond ?? 0) / 1e9
        let interval = Double(roundingMinutes * 60)
        let remainder = intoHour.truncatingRemainder(dividingBy: interval)
        return remainder == 0 ? later : later.addingTimeInterval(interval - remainder)
    }

    /// The backstops after the last alarm, from the settings' offsets.
    static func backstops(after last: Date?, settings: BridgeSettings) -> [String: Date] {
        guard let last else { return [:] }
        let (early, deadline, late) = settings.ownOffsetsValid
            ? (settings.ownEarlyMinutes, settings.ownDeadlineMinutes, settings.ownLateMinutes) : (15, 30, 45)
        return ["early": last.addingTimeInterval(Double(early) * 60),
                "deadline": last.addingTimeInterval(Double(deadline) * 60),
                "late": last.addingTimeInterval(Double(late) * 60)]
    }

    static func make(wake: Date, count: Int, spacingMinutes: Int, wakeIs: WakeTimeAlarm, backstopsOn: Bool, settings: BridgeSettings) -> OwnAlarmDraft {
        let times = WakePlanner.alarmTimes(wakeTime: wake, count: count, spacingMinutes: spacingMinutes, wakeIs: wakeIs)
        return OwnAlarmDraft(times: times, wakeIs: wakeIs, backstopsOn: backstopsOn, backstops: backstops(after: times.max(), settings: settings))
    }

    /// New alarms: the backstops are worked out again from the new last alarm, and any edits to
    /// them are undone. Returns true when edits were undone (so the preview can say so).
    @discardableResult
    mutating func setAlarms(_ new: [Date], settings: BridgeSettings) -> Bool {
        times = new.sorted()
        let undone = backstopsEdited
        backstops = Self.backstops(after: times.max(), settings: settings)
        backstopsEdited = false
        return undone
    }

    /// Where a new alarm goes: before the first, after the last, or midway after alarm `index`.
    enum Insert {
        case before
        case after
        case between(Int)
    }

    func adding(_ insert: Insert, spacingMinutes: Int) -> [Date] {
        let sorted = times.sorted()
        guard let first = sorted.first, let last = sorted.last else { return times }
        let spacing = Double(max(spacingMinutes, 1)) * 60
        switch insert {
        case .before: return [first.addingTimeInterval(-spacing)] + sorted
        case .after: return sorted + [last.addingTimeInterval(spacing)]
        case .between(let index):
            guard index + 1 < sorted.count else { return sorted + [last.addingTimeInterval(spacing)] }
            let mid = sorted[index].addingTimeInterval(sorted[index + 1].timeIntervalSince(sorted[index]) / 2)
            return (sorted + [mid]).sorted()
        }
    }

    /// The wake-up these alarms are built around (first or last, as chosen).
    var wake: Date? { wakeIs == .last ? times.max() : times.min() }

    var replacement: SkipReplacement? {
        guard let wake else { return nil }
        return SkipReplacement(wake: wake, wakeIs: wakeIs, times: times, backstops: backstopsOn,
                               customBackstops: backstopsOn && backstopsEdited ? backstops : nil)
    }
}
