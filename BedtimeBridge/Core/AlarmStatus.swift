import Foundation

/// What Tonight says about the alarms, from what AlarmKit actually holds (v0.4.1 items 1 and 4).
struct AlarmStatus: Equatable {
    enum Kind: Equatable {
        case set
        case error
        case notSet
    }

    var kind: Kind
    var text: String

    /// - Parameters:
    ///   - setTimes: the series alarms AlarmKit holds (snoozing ones included).
    ///   - shortfall: the last setting took fewer than asked: (set, asked).
    static func make(setTimes: [Date], shortfall: (set: Int, planned: Int)?, now: Date = .now) -> AlarmStatus {
        let times = setTimes.sorted().map(WakePlanner.format).joined(separator: " ")
        if let shortfall, shortfall.set < shortfall.planned {
            let missing = shortfall.planned - shortfall.set
            return AlarmStatus(kind: .error, text: "Couldn't set \(missing) of \(shortfall.planned) alarms" + (times.isEmpty ? "" : " · set: \(times)"))
        }
        guard !setTimes.isEmpty else { return AlarmStatus(kind: .notSet, text: "Preview, not set yet") }
        return AlarmStatus(kind: .set, text: (setTimes.count == 1 ? "1 alarm set" : "\(setTimes.count) alarms set") + " · " + times)
    }
}
