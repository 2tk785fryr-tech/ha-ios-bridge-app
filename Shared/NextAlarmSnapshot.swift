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
    /// After the last alarm, leave-by stays on the widget until this many minutes past it.
    var leaveByShownMinutes: Int? = nil
    /// Tonight's wind-down (v0.4.3 item 5): from wind-down until go to bed the widget shows
    /// "Bed in 42 min · first alarm 4:20".
    var windDownAt: Date? = nil
    var goToBedAt: Date? = nil
    /// For the Wind-down control (v0.4.3 item 16): Home Assistant's status.
    var windDownStatus: String? = nil
    /// Settings → Shortcuts & controls, read by the controls and the widget's tap.
    var windDownControlOpensApp: Bool? = nil
    var napControlNapsNow: Bool? = nil
    var widgetTapAlwaysTonight: Bool? = nil
    var startWindDownHours: Int? = nil

    /// Start wind-down now is open at `date`: scheduled, within the window before go to bed, and
    /// before wind-down time (worked out when asked, so the control never goes stale).
    func canStartWindDown(at date: Date) -> Bool {
        guard windDownStatus == "scheduled", let windDownAt, let goToBedAt, date < windDownAt else { return false }
        return date >= goToBedAt.addingTimeInterval(-Double(startWindDownHours ?? 2) * 3600)
    }

    /// Winding down at `date`: go to bed still ahead.
    func bedCountdown(at date: Date) -> Date? {
        guard let windDownAt, let goToBedAt, windDownAt <= date, date < goToBedAt else { return nil }
        return goToBedAt
    }

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

    /// Leave-by to show once no alarm is left: shift and appointment mornings, until
    /// `leaveByShownMinutes` (30) past it.
    func leaveByAfterAlarms(at date: Date) -> Date? {
        guard nextAlarm(after: date) == nil, let leaveBy, date < leaveByHiddenAt(leaveBy) else { return nil }
        return leaveBy
    }

    private func leaveByHiddenAt(_ leaveBy: Date) -> Date {
        leaveBy.addingTimeInterval(TimeInterval((leaveByShownMinutes ?? 30) * 60))
    }

    /// Times at which the widget's text changes (each alarm passing, leave-by going away),
    /// for its timeline.
    func changeDates(after date: Date) -> [Date] {
        ([snoozedUntil, leaveBy.map(leaveByHiddenAt), windDownAt, goToBedAt].compactMap { $0 } + alarmTimes + (temporaryAlarms ?? [])).filter { $0 > date }.sorted()
    }

    /// The label chip at `date`: "Bed in" during wind-down, the alarm's label while an alarm or
    /// leave-by is still ahead, and nothing otherwise (the label of alarms that have passed or were
    /// turned off isn't tomorrow's).
    func chipLabel(at date: Date) -> String? {
        if bedCountdown(at: date) != nil { return "Bed in" }
        guard nextAlarm(after: date) != nil || leaveByAfterAlarms(at: date) != nil else { return nil }
        let text = label(after: date)
        return text.isEmpty ? nil : text
    }

    /// One line of the bigger widgets' timeline: wind-down, go to bed, each alarm, leave-by.
    struct Step: Equatable {
        enum Kind: Equatable { case windDown, goToBed, alarm, wakeUp, temporary, snooze, leaveBy }
        var kind: Kind
        var time: Date
        var title: String
    }

    /// What's still ahead at `date`, in time order: the medium widget shows the first four, the
    /// large one up to eight.
    func steps(after date: Date) -> [Step] {
        var steps: [Step] = []
        if let windDownAt, let goToBedAt, goToBedAt > date {
            if windDownAt > date { steps.append(Step(kind: .windDown, time: windDownAt, title: "Wind-down")) }
            steps.append(Step(kind: .goToBed, time: goToBedAt, title: "Go to bed"))
        }
        if let snoozedUntil, snoozedUntil > date { steps.append(Step(kind: .snooze, time: snoozedUntil, title: "Snooze ends")) }
        let series = alarmTimes.filter { $0 > date }.sorted()
        for (index, time) in series.enumerated() {
            let isWake = wakeTime.map { abs($0.timeIntervalSince(time)) < 60 } ?? (index == series.count - 1)
            steps.append(Step(kind: isWake ? .wakeUp : .alarm, time: time, title: isWake ? "Wake up" : "Alarm"))
        }
        for time in (temporaryAlarms ?? []) where time > date {
            steps.append(Step(kind: .temporary, time: time, title: "Temporary wake-up"))
        }
        if let leaveBy, date < leaveByHiddenAt(leaveBy) {
            steps.append(Step(kind: .leaveBy, time: leaveBy, title: leaveBy > date ? "Leave by" : "Time to go"))
        }
        return steps.sorted { $0.time < $1.time }
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
