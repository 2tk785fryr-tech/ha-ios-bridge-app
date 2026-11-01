import Foundation

/// What the Stop screen says about the alarm you're ending: "4:25 AM · alarm 2 of 3" and
/// "Next: 4:30 AM" (or "Last alarm").
struct StopDescription: Equatable {
    enum Kind: Equatable {
        case series
        case temporary
        case nap
        case test

        /// v0.4.9 item 4: what kind of alarm this is, from the alarms as they were set (not only
        /// the ones AlarmKit still has: Stop on the banner removes the alarm before the app hears
        /// of it) and, as a second check, the cause the alarm was set with.
        static func of(_ id: UUID, cause: String?, test: UUID?, temporary: Set<UUID>, nap: Set<UUID>) -> Kind {
            if id == test || cause == "test" { return .test }
            if temporary.contains(id) || cause == AlarmCause.temporary { return .temporary }
            if nap.contains(id) || cause == AlarmCause.nap { return .nap }
            return .series
        }
    }

    /// v0.4.9 item 4: alarms this long after the one ringing belong to a later wake-up (another
    /// day, or a nap's evening), which stopping this one never ends.
    static let wakeUpSpan: TimeInterval = 4 * 3600

    static func laterWakeUp(_ alarm: Date, ringing: Date) -> Bool {
        alarm > ringing.addingTimeInterval(wakeUpSpan)
    }

    /// v0.4.10 item 1: a banner Stop folds into the next alarm of this wake-up when it rings
    /// before the snooze would, instead of setting another alarm next to it.
    struct Upcoming: Equatable {
        var id: UUID
        /// The time it was set for.
        var set: Date
        /// When it rings next: the set time, or the end of its snooze.
        var rings: Date
    }

    static func foldsInto(snoozeAt: Date, upcoming: [Upcoming]) -> Upcoming? {
        upcoming.filter { $0.rings <= snoozeAt }.min { $0.rings < $1.rings }
    }

    /// "1st", "2nd", "3rd", "4th".
    static func ordinal(_ n: Int) -> String {
        let suffix = (11...13).contains(n % 100) ? "th" : [1: "st", 2: "nd", 3: "rd"][n % 10] ?? "th"
        return "\(n)\(suffix)"
    }

    var title: String
    var detail: String
    var kind: Kind = .series
    /// Later alarms in this wake-up that the slide-and-hold would end too (item 2).
    var canEndAll = false
    /// v0.4.10 item 1: what's left in this wake-up, as each rings: "8:20", or "8:10 → rings 8:19"
    /// while snoozing.
    var left: [String] = []

    /// - Parameters:
    ///   - alarmTime: when the alarm being stopped was set to ring (its first ring, not the snooze).
    ///   - series: every alarm of this wake-up as it was set, including ones already stopped.
    ///   - remaining: the series alarms still set after this one.
    ///   - snoozes: how many times this alarm has been snoozed (v0.4.10 item 1).
    ///   - left: the rest of this wake-up as it rings, for the list on the Stop screen.
    ///   - foldedInto: the alarm a banner Stop snoozed onto, for "Next: the 8:10 alarm, in 1 min".
    static func make(kind: Kind, alarmTime: Date?, series: [Date], remaining: [Date], snoozes: Int = 0,
                     left: [Upcoming] = [], foldedInto: Upcoming? = nil, now: Date = .now) -> StopDescription {
        let time = alarmTime.map(WakePlanner.format)
        switch kind {
        case .test:
            return StopDescription(title: [time, "Test alarm"].compactMap { $0 }.joined(separator: " · "), detail: "Your real alarms aren't affected.", kind: .test)
        case .temporary:
            return StopDescription(title: [time, "Temporary alarm"].compactMap { $0 }.joined(separator: " · "), detail: "Your regular alarms are unchanged.", kind: .temporary)
        case .nap:
            let next = remaining.filter { alarm in alarmTime.map { alarm > $0.addingTimeInterval(30) } ?? true }.min()
            return StopDescription(title: [time, "Nap"].compactMap { $0 }.joined(separator: " · "),
                                   detail: next.map { "Next: \(WakePlanner.format($0)) (backup)" } ?? "Last nap alarm", kind: .nap)
        case .series:
            let sorted = series.sorted()
            let place = alarmTime.flatMap { time in sorted.firstIndex { abs($0.timeIntervalSince(time)) < 60 } }
            let position = place.map { "alarm \($0 + 1) of \(sorted.count)" }
            let next = remaining.filter { alarm in alarmTime.map { alarm > $0.addingTimeInterval(30) } ?? true }.min()
            // v0.4.10 item 1: named by the time it was set for, so a snooze isn't another alarm.
            let name = time.map { snoozes > 0 || foldedInto != nil ? "The \($0) alarm" : $0 }
            let snoozed = snoozes > 0 ? "\(ordinal(snoozes)) snooze" : nil
            var detail = next.map { "Next: \(WakePlanner.format($0))" } ?? "Last alarm"
            if let foldedInto {
                let minutes = max(0, Int((foldedInto.rings.timeIntervalSince(now) / 60).rounded(.up)))
                detail = "Next: the \(WakePlanner.format(foldedInto.set)) alarm, in \(minutes) min"
            }
            return StopDescription(
                title: [name, position, snoozed].compactMap { $0 }.joined(separator: " · "),
                detail: detail,
                canEndAll: next != nil || !left.isEmpty,
                left: left.sorted { $0.rings < $1.rings }.map { alarm in
                    abs(alarm.rings.timeIntervalSince(alarm.set)) < 30
                        ? WakePlanner.format(alarm.set)
                        : "\(WakePlanner.format(alarm.set)) → rings \(WakePlanner.format(alarm.rings))"
                }
            )
        }
    }
}
