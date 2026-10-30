import Foundation

/// How Settings → Alarms describes the two alarm series (v0.4.7 item 7).
enum AlarmSeriesText {
    /// "3 alarms, 10 min apart"
    static func summary(count: Int, spacing: Int) -> String {
        count == 1 ? "1 alarm" : "\(count) alarms, \(spacing) min apart"
    }

    /// "Up at 5:30 → alarms 5:10, 5:20, 5:30"
    static func example(count: Int, spacing: Int, wakeIs: WakeTimeAlarm, calendar: Calendar = .current) -> String {
        let wake = calendar.date(bySettingHour: 5, minute: 30, second: 0, of: .now) ?? .now
        let times = WakePlanner.alarmTimes(wakeTime: wake, count: count, spacingMinutes: spacing, wakeIs: wakeIs)
        return "Up at \(WakePlanner.format(wake)) → alarms " + times.map(WakePlanner.format).joined(separator: ", ")
    }

    /// The Alarms row on the main Settings page: "Snooze 9 min" (the app's alarms), or the Clock
    /// app's name. Short, so it fits beside the title.
    static func alarmsRow(style: AlarmStyle, snooze: Int) -> String {
        style == .app ? "Snooze \(snooze) min" : style.displayName
    }
}

/// Your own alarms' series (Settings → Alarms → Your own alarms), for a time you pick: Wake at a
/// different time and, from v0.4.7 item 7, the Set Wake-Up Alarms action.
enum OwnAlarmSeries {
    static func replacement(wake: Date, wakeIs: WakeTimeAlarm?, settings: BridgeSettings) -> SkipReplacement {
        let wakeIs = wakeIs ?? settings.ownAlarmWakeIs
        let times = WakePlanner.alarmTimes(wakeTime: wake, count: settings.ownAlarmCount, spacingMinutes: settings.ownAlarmSpacingMinutes, wakeIs: wakeIs)
        return SkipReplacement(wake: wake, wakeIs: wakeIs, times: times)
    }
}
