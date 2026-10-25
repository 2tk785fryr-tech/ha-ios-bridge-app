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

    /// The next alarm at `date`: a running snooze first, then the series.
    func nextAlarm(after date: Date) -> Date? {
        if let snoozedUntil, snoozedUntil > date { return snoozedUntil }
        return alarmTimes.sorted().first { $0 > date }
    }

    /// Times at which the widget's text changes (each alarm passing), for its timeline.
    func changeDates(after date: Date) -> [Date] {
        ([snoozedUntil].compactMap { $0 } + alarmTimes).filter { $0 > date }.sorted()
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
