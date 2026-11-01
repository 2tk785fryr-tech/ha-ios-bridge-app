import Foundation

/// v0.4.10 item 11: Your morning for alarms with no drive (your own, a day off): each alarm,
/// temporary alarms included, and that morning's backstops, in time order.
enum AlarmTimeline {
    struct Step: Equatable {
        enum Kind: Equatable { case alarm, wake, temporary, backstop }
        var kind: Kind
        var title: String
        var time: Date
        var detail: String?
    }

    /// Temporary alarms more than this far from the morning's alarms aren't that morning's.
    static let morningSpan: TimeInterval = 12 * 3600

    static func steps(alarms: [Date], wake: Date?, temporary: [TemporaryAlarm], rungs: [BackstopInfo.Rung]) -> [Step] {
        let sorted = alarms.sorted()
        var steps = sorted.enumerated().map { index, time in
            let isWake = wake.map { abs($0.timeIntervalSince(time)) < 30 } ?? false
            return Step(kind: isWake ? .wake : .alarm, title: isWake ? "Wake up" : "Alarm \(index + 1) of \(sorted.count)", time: time)
        }
        let first = sorted.first
        steps += temporary.filter { alarm in first.map { abs(alarm.time.timeIntervalSince($0)) < morningSpan } ?? true }.map {
            Step(kind: .temporary, title: "Temporary alarm", time: $0.time,
                 detail: $0.disarmHouse ? "Disarms the house" : "House stays armed")
        }
        steps += rungs.map { Step(kind: .backstop, title: $0.name, time: $0.time) }
        return steps.sorted { $0.time < $1.time }
    }
}
