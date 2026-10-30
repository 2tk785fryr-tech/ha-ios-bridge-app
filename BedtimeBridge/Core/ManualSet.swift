import Foundation

/// What a manual set or "No alarms tomorrow" replaced, so Undo can put it back (v0.4.3 items 2
/// and 3). Kept until bedtime runs or the alarms are changed another way.
struct UndoRecord: Codable, Equatable {
    enum Kind: String, Codable { case set, noAlarms }

    var kind: Kind
    /// The regular alarms before (empty: none were set).
    var previousTimes: [Date]
    var previousWake: Date?
    var previousSource: WakeSource
    var previousReason: String
    var previousCause: String
    /// "No alarms tomorrow" was in force before (its morning).
    var previousCleared: Date?
    /// The regular alarms this left set, to tell whether they've been changed since.
    var leftTimes: [Date]
    var savedAt: Date

    /// Undo still applies: the alarms are as this left them, bedtime hasn't run since, and
    /// there's something still to come to go back to (or nothing was set before).
    func available(currentTimes: [Date], bedtimeRanAt: Date?, now: Date = .now) -> Bool {
        if let ran = bedtimeRanAt, ran > savedAt { return false }
        guard Self.same(currentTimes.filter { $0 > now }, leftTimes.filter { $0 > now }) else { return false }
        // Before, alarms that have all rung since: nothing to put back.
        return previousTimes.isEmpty || previousTimes.contains { $0 > now }
    }

    /// The same alarms, to the minute.
    static func same(_ a: [Date], _ b: [Date]) -> Bool {
        let minutes = { (dates: [Date]) in dates.map { Int(($0.timeIntervalSinceReferenceDate / 60).rounded()) }.sorted() }
        return minutes(a) == minutes(b)
    }

    /// The previous plan, rebuilt to set its alarms again.
    var previousPlan: WakePlan? {
        guard !previousTimes.isEmpty else { return nil }
        var plan = WakePlan(source: previousSource, wakeTime: previousWake, alarmTimes: previousTimes.sorted(), reason: previousReason)
        if previousSource == .shift {
            plan.shift = ShiftCandidate(title: previousCause, start: previousWake ?? previousTimes.max()!, wakeMinutesBefore: 0, cause: previousCause)
        }
        return plan
    }

    /// The bottom bar's status for this: "3 alarms set · Undo" or "No alarms tomorrow · Undo".
    func status(alarmsSet: Int) -> String {
        switch kind {
        case .set: "\(alarmsSet == 1 ? "1 alarm" : "\(alarmsSet) alarms") set · Undo"
        case .noAlarms: "No alarms tomorrow · Undo"
        }
    }
}

/// What changed in tomorrow's plan since the alarms were set (v0.4.3 item 4), in a sentence:
/// "Tomorrow changed: Days shift deleted. Your 4:20 alarms are still set. Re-plan?"
enum PlanChange {
    /// nil when the new plan wakes you at the same times for the same reason.
    static func describe(set: [Date], setCause: String, setLabel: String?, new: WakePlan) -> String? {
        let upcoming = set.sorted()
        guard let first = upcoming.first else { return nil }
        if UndoRecord.same(upcoming, new.alarmTimes), setCause == new.cause { return nil }
        let what: String
        let wasShift = ![AlarmCause.calendar, AlarmCause.manual, AlarmCause.none, ""].contains(setCause)
        if !new.hasAlarm {
            what = wasShift ? "\(setCause) shift deleted" : "\(setLabel ?? "The wake-up event") is gone"
        } else if new.cause != setCause {
            switch new.source {
            case .appointment: what = "\(new.appointment?.title ?? "An event") now decides the wake-up"
            case .shift: what = wasShift ? "\(setCause) shift is now \(new.cause)" : "\(new.cause) shift added"
            default: what = "the wake-up changed"
            }
        } else if let newFirst = new.firstAlarm {
            what = "first alarm would be \(WakePlanner.format(newFirst))"
        } else {
            what = "the wake-up changed"
        }
        let sentence = what.prefix(1).uppercased() + what.dropFirst()
        return "Tomorrow changed: \(sentence). Your \(WakePlanner.format(first)) alarms are still set. Re-plan?"
    }
}
