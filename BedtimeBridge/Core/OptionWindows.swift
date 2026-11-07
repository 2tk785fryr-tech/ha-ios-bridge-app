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

    /// v0.4.11 item 32: bedtime ran tonight and set no alarms (a day off), until the morning's
    /// Good morning from time. No alarm stopped since bedtime (that's a morning, not a night off),
    /// and not napping.
    static func inBedNoAlarms(bedtimeRanAt: Date?, lastStop: Date?, alarmsSet: Bool, napping: Bool,
                              goodMorningFrom: String, now: Date = .now, calendar: Calendar = .current) -> Bool {
        guard let ran = bedtimeRanAt, !alarmsSet, !napping, now >= ran else { return false }
        if let lastStop, lastStop >= ran { return false }
        return now < min(morning(after: ran, goodMorningFrom: goodMorningFrom, calendar: calendar), ran.addingTimeInterval(16 * 3600))
    }

    /// The first Good morning from time after `ran`: the morning a night's bedtime is for (a
    /// bedtime at 1 AM is for that same morning).
    static func morning(after ran: Date, goodMorningFrom: String, calendar: Calendar = .current) -> Date {
        let parts = goodMorningFrom.split(separator: ":").compactMap { Int($0) }
        guard var end = calendar.date(bySettingHour: parts.first ?? 8, minute: parts.count > 1 ? parts[1] : 0, second: 0, of: ran) else { return ran }
        if end <= ran { end = calendar.date(byAdding: .day, value: 1, to: end) ?? end }
        return end
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
