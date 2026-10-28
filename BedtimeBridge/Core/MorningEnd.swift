import Foundation

/// Item 8: whether Tonight offers to end this morning's alarms, and what it says is left.
struct MorningEnd: Equatable {
    /// No alarm of the series has rung yet: "I'm up early".
    var early: Bool
    var title: String
    var detail: String

    /// - Parameters:
    ///   - series: every alarm of this wake-up as it was set.
    ///   - remaining: the series alarms still set (a snoozing one keeps its original time).
    ///   - snoozedUntil: when the running snooze rings again, if one is.
    ///   - windowHours: how long before the first alarm the early end shows.
    static func make(now: Date, series: [Date], remaining: [Date], snoozedUntil: Date?, windowHours: Int) -> MorningEnd? {
        guard !remaining.isEmpty, let first = (series.isEmpty ? remaining : series).min() else { return nil }
        guard now >= first.addingTimeInterval(-Double(windowHours) * 3600) else { return nil }
        let snoozing = remaining.filter { $0 <= now }.sorted()
        let toRing = remaining.filter { $0 > now }.sorted()
        let early = now < first
        var parts: [String] = []
        if !snoozing.isEmpty {
            let until = snoozedUntil.map { " until \(WakePlanner.format($0))" } ?? ""
            parts.append(snoozing.count == 1 ? "\(WakePlanner.format(snoozing[0])) snoozing\(until)" : "\(snoozing.count) snoozing\(until)")
        }
        if !toRing.isEmpty {
            parts.append(toRing.map(WakePlanner.format).joined(separator: ", ") + " still to ring")
        }
        return MorningEnd(
            early: early,
            title: early ? "Up before the alarms?" : "Up already?",
            detail: parts.joined(separator: " · ")
        )
    }
}
