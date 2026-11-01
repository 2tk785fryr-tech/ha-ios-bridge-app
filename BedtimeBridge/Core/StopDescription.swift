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

    var title: String
    var detail: String
    var kind: Kind = .series
    /// Later alarms in this wake-up that the slide-and-hold would end too (item 2).
    var canEndAll = false

    /// - Parameters:
    ///   - alarmTime: when the alarm being stopped was set to ring (its first ring, not the snooze).
    ///   - series: every alarm of this wake-up as it was set, including ones already stopped.
    ///   - remaining: the series alarms still set after this one.
    static func make(kind: Kind, alarmTime: Date?, series: [Date], remaining: [Date]) -> StopDescription {
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
            return StopDescription(
                title: [time, position].compactMap { $0 }.joined(separator: " · "),
                detail: next.map { "Next: \(WakePlanner.format($0))" } ?? "Last alarm",
                canEndAll: next != nil
            )
        }
    }
}
