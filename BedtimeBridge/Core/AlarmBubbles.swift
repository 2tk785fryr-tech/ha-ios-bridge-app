import Foundation

/// The alarm bubbles on the main screen's card, each with its real state from AlarmKit
/// (v0.4.2 item 5).
struct AlarmBubble: Equatable, Identifiable {
    enum Ring: Equatable {
        /// Preview: nothing set, no outline.
        case none
        /// Set, still to ring: solid green.
        case set
        /// Rang and snoozing: yellow, pulsing; rings again then.
        case snoozing(until: Date?)
        /// Turned off: red, time crossed out.
        case off
        /// Should be set but isn't: red dashed.
        case notSet
    }

    var time: Date
    var ring: Ring
    var isWake: Bool
    var id: Date { time }

    var label: String? {
        switch ring {
        case .none, .set: nil
        case .snoozing(let until): "snoozing" + (until.map { " · rings \(WakePlanner.format($0))" } ?? "")
        case .off: "off"
        case .notSet: "not set"
        }
    }

    /// - Parameters:
    ///   - morning: every alarm this morning should have (planned, plus what was set).
    ///   - held: what AlarmKit holds now (a snoozing alarm keeps its original time).
    ///   - stopped: an alarm of this wake-up was stopped or the morning ended: anything no
    ///     longer held is off rather than missing.
    static func make(morning: [Date], held: [Date], wake: Date?, snoozedUntil: Date?, stopped: Bool, now: Date = .now) -> [AlarmBubble] {
        let times = Array(Set(morning + held)).sorted()
        return times.map { time in
            let isHeld = held.contains { abs($0.timeIntervalSince(time)) < 1 }
            let ring: Ring
            if isHeld {
                ring = time <= now ? .snoozing(until: snoozedUntil) : .set
            } else if stopped || time <= now {
                ring = .off
            } else {
                ring = .notSet
            }
            return AlarmBubble(time: time, ring: ring, isWake: wake.map { abs($0.timeIntervalSince(time)) < 60 } ?? false)
        }
    }

    /// A plan not set yet: plain bubbles.
    static func preview(_ times: [Date], wake: Date?) -> [AlarmBubble] {
        times.map { time in AlarmBubble(time: time, ring: .none, isWake: wake.map { abs($0.timeIntervalSince(time)) < 60 } ?? false) }
    }

    /// The rings stay until the morning is over: the late backstop + 60 min, or the last alarm
    /// + 60 min without backstops.
    static func morningOver(lateBackstop: Date?, lastAlarm: Date?) -> Date? {
        (lateBackstop ?? lastAlarm).map { $0.addingTimeInterval(3600) }
    }

    /// "✓ 3 alarms set" (no times; they're in the bubbles), counting the alarms still set plus
    /// the ones that really rang, so it stays through the morning. Alarms cancelled before their
    /// time don't count (v0.4.9 item 5): "1 of 3 alarms left", "Ended early" or "Alarms off".
    /// - Parameter stoppedAt: when an alarm of this wake-up was stopped or the morning ended, if
    ///   it was; an alarm off after that time was cancelled, not rung.
    static func header(_ bubbles: [AlarmBubble], shortfall: (set: Int, planned: Int)?, stoppedAt: Date? = nil, now: Date = .now) -> AlarmStatus {
        if let shortfall, shortfall.set < shortfall.planned {
            return AlarmStatus(kind: .error, text: "Couldn't set \(shortfall.planned - shortfall.set) of \(shortfall.planned) alarms")
        }
        let counted = bubbles.filter { $0.ring != .notSet && $0.ring != .none }
        guard !counted.isEmpty else { return AlarmStatus(kind: .notSet, text: "Preview · not set") }
        let rangBy = stoppedAt ?? now
        let active = counted.filter { $0.ring != .off }.count
        let rang = counted.filter { $0.ring == .off && $0.time <= rangBy }.count
        let cancelled = counted.count - active - rang
        if cancelled == 0 {
            return AlarmStatus(kind: .set, text: counted.count == 1 ? "1 alarm set" : "\(counted.count) alarms set")
        }
        if active > 0 {
            return AlarmStatus(kind: .set, text: "\(active) of \(counted.count) alarms left")
        }
        // Ended within this wake-up (a stop with the rest cancelled, or I'm up early) rather than
        // turned off some other time.
        let first = counted.map(\.time).min() ?? now
        let endedThisWakeUp = stoppedAt.map { $0 >= first.addingTimeInterval(-StopDescription.wakeUpSpan) } ?? false
        if rang > 0 || endedThisWakeUp {
            return AlarmStatus(kind: rang > 0 ? .set : .notSet, text: "Ended early")
        }
        return AlarmStatus(kind: .notSet, text: "Alarms off")
    }
}
