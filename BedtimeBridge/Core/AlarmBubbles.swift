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

    /// "✓ 3 alarms set" (no times; they're in the bubbles), counting the alarms that were set
    /// this morning, so it stays through the morning.
    static func header(_ bubbles: [AlarmBubble], shortfall: (set: Int, planned: Int)?) -> AlarmStatus {
        if let shortfall, shortfall.set < shortfall.planned {
            return AlarmStatus(kind: .error, text: "Couldn't set \(shortfall.planned - shortfall.set) of \(shortfall.planned) alarms")
        }
        let set = bubbles.filter { $0.ring != .notSet && $0.ring != .none }.count
        guard set > 0 else { return AlarmStatus(kind: .notSet, text: "Preview · not set") }
        return AlarmStatus(kind: .set, text: set == 1 ? "1 alarm set" : "\(set) alarms set")
    }
}
