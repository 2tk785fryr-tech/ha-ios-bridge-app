import Foundation

/// What the Lock Screen widget shows. The app writes it to the shared App Group whenever
/// alarms change (plan, snooze, stop, cancel); the widget only reads it.
struct NextAlarmSnapshot: Codable, Equatable {
    /// "group.<app ID>", from Info.plist (BedtimeBridgeAppGroup = group.$(APP_BUNDLE_ID)), so the
    /// app and widget always agree with the entitlements without a hard-coded ID.
    static let appGroup = Bundle.main.object(forInfoDictionaryKey: "BedtimeBridgeAppGroup") as? String
        ?? "group.io.github.2tk785fryr-tech.bedtimebridge"
    private static let key = "nextAlarmSnapshot.v1"

    var alarmTimes: [Date] = []
    /// "Days", "Swings", "calendar", "automade" or "noalarm".
    var cause: String = "noalarm"
    /// Short label for the widget: "Days shift", "Dentist", "Day off".
    var label: String = ""
    /// Appointment mornings only.
    var leaveBy: Date?
    /// Set while a snooze countdown is running.
    var snoozedUntil: Date?
    /// "app" or "clock"
    var alarmStyle: String = "app"
    /// Temporary wake-ups beside the series. Optional so snapshots saved before they
    /// existed still load.
    var temporaryAlarms: [Date]? = nil
    /// When you need to be up, and why ("Days shift at 6:00 AM"), for Tonight to show what
    /// the bedtime shortcut set. Optional for the same reason.
    var wakeTime: Date? = nil
    var reason: String? = nil

    /// "3 alarms set", counting the series still to ring.
    func setSummary(after date: Date) -> String? {
        let count = setCount(after: date)
        guard count > 0 else { return nil }
        return count == 1 ? "1 alarm set" : "\(count) alarms set"
    }

    /// How many of the series' alarms are still to ring at `date`.
    func setCount(after date: Date) -> Int {
        alarmTimes.filter { $0 > date }.count
    }

    /// The next alarm at `date`: a running snooze first, then the series or a temporary one.
    func nextAlarm(after date: Date) -> Date? {
        if let snoozedUntil, snoozedUntil > date { return snoozedUntil }
        return (alarmTimes + (temporaryAlarms ?? [])).sorted().first { $0 > date }
    }

    /// "Temporary wake-up" when the next alarm is one, otherwise the plan's label.
    func label(after date: Date) -> String {
        guard let next = nextAlarm(after: date), next != snoozedUntil, (temporaryAlarms ?? []).contains(next) else { return label }
        return "Temporary wake-up"
    }

    /// Times at which the widget's text changes (each alarm passing), for its timeline.
    func changeDates(after date: Date) -> [Date] {
        ([snoozedUntil].compactMap { $0 } + alarmTimes + (temporaryAlarms ?? [])).filter { $0 > date }.sorted()
    }

    static func load() -> NextAlarmSnapshot {
        guard let data = UserDefaults(suiteName: appGroup)?.data(forKey: key),
              let snapshot = try? JSONDecoder().decode(NextAlarmSnapshot.self, from: data) else { return NextAlarmSnapshot() }
        return snapshot
    }

    func save() {
        guard let data = try? JSONEncoder().encode(self) else { return }
        UserDefaults(suiteName: Self.appGroup)?.set(data, forKey: Self.key)
    }
}
