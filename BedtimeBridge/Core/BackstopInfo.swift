import Foundation

/// The backstops for "Your morning" on Tonight (v0.4.1 item 8): their times and a status line.
struct BackstopInfo: Equatable {
    struct Rung: Equatable {
        var name: String
        var time: Date
    }

    var rungs: [Rung]
    /// "Backstops armed", the idle reason, or "Backstop fault: …".
    var status: String
    var isFault = false
    /// Worked out on the phone because Home Assistant couldn't be reached.
    var estimate = false
    /// The times shown are the old template's, which the house backstop fires on until the cutover.
    var houseOldTimes = false
    var firstDayBackMinutes: Int?
    /// Until the cutover: a marked appointment replaced this shift, but the house backstop still
    /// uses the shift's times (v0.4.1 item 11).
    var houseUsesShift: String?

    /// - Parameters:
    ///   - context: from Home Assistant, or nil when it couldn't be reached.
    ///   - leaveBy: this morning's leave-by, for an estimate without Home Assistant.
    ///   - offsets: minutes before leave-by (early, deadline, late) and the first-day-back extra.
    static func make(context: MorningContext?, leaveBy: Date?, offsets: (early: Int, deadline: Int, late: Int, firstDayBack: Int),
                     firstDayBack: Bool, replacedShift: String? = nil) -> BackstopInfo? {
        guard let context else {
            guard let leaveBy else { return nil }
            let extra = firstDayBack ? offsets.firstDayBack : 0
            let rungs = [("Early backstop", offsets.early), ("Deadline backstop", offsets.deadline), ("Late backstop", offsets.late)]
                .map { Rung(name: $0.0, time: leaveBy.addingTimeInterval(-Double($0.1 + extra) * 60)) }
            return BackstopInfo(rungs: rungs, status: "Estimate: Home Assistant couldn't be reached", estimate: true,
                                firstDayBackMinutes: firstDayBack && extra > 0 ? extra : nil)
        }
        let useHouse = context.houseUsesOldTimes && !context.houseTimes.isEmpty
        let times = useHouse ? context.houseTimes : (context.ladderArmed ? context.backstops : [:])
        let rungs = [("early", "Early backstop"), ("deadline", "Deadline backstop"), ("late", "Late backstop")]
            .compactMap { key, name in times[key].map { Rung(name: name, time: $0) } }
        let status: String
        var fault = false
        switch context.ladderStatus {
        case "armed": status = "Backstops armed"
        case "fault":
            status = "Backstop fault: \(context.ladderReason ?? "unknown")"
            fault = true
        case nil: status = "Backstops: no status from Home Assistant"
        default: status = context.ladderReason.map { "Backstops off: \($0)" } ?? "Backstops off"
        }
        if rungs.isEmpty, context.ladderStatus != "armed", context.ladderStatus != "fault" {
            return BackstopInfo(rungs: [], status: status)
        }
        return BackstopInfo(rungs: rungs, status: status, isFault: fault, houseOldTimes: useHouse,
                            firstDayBackMinutes: context.firstDayBack ? offsets.firstDayBack : nil,
                            houseUsesShift: useHouse ? replacedShift : nil)
    }
}
