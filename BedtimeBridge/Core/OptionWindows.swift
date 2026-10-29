import Foundation

/// When each situational option shows (v0.4.2 item 7), for the bottom bar, the ⋯ menu and the
/// cards alike. Once a window closes the option disappears; nothing else changes.
enum OptionWindows {
    /// I'm up early / End this morning's alarms: from this long before the first alarm, while
    /// any alarm of the series is left.
    static func upEarly(firstAlarm: Date?, anyLeft: Bool, hours: Int, now: Date = .now) -> Bool {
        guard anyLeft, let firstAlarm else { return false }
        return now >= firstAlarm.addingTimeInterval(-Double(hours) * 3600)
    }

    /// Not ready for bed: for this long after bedtime ran, while the alarms are set.
    static func notReadyForBed(bedtimeRanAt: Date?, alarmsSet: Bool, hours: Int, now: Date = .now) -> Bool {
        guard alarmsSet, let bedtimeRanAt, now >= bedtimeRanAt else { return false }
        return now <= bedtimeRanAt.addingTimeInterval(Double(hours) * 3600)
    }

    /// Back to bed: once the series is over, until this long after the wake-up (the series'
    /// last alarm) or after the last stop, whichever is later.
    static func backToBed(series: [Date], lastStop: Date?, anyLeft: Bool, upEarlyHours: Int, hours: Int, now: Date = .now) -> Bool {
        guard !anyLeft, let first = series.min(), let last = series.max() else { return false }
        let from = first.addingTimeInterval(-Double(upEarlyHours) * 3600)
        let until = max(last, lastStop ?? last).addingTimeInterval(Double(hours) * 3600)
        return now >= from && now <= until
    }

    /// Sleep later: until the first alarm (no setting).
    static func sleepLater(firstAlarm: Date?, stopped: Bool, now: Date = .now) -> Bool {
        guard let firstAlarm else { return false }
        return firstAlarm > now && !stopped
    }
}
