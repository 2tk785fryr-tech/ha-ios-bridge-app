import Foundation

/// Tonight's wind-down and go to bed times from tomorrow's first alarm (v0.4.3 item 5). Home
/// Assistant runs the evening with the same rule; the app shows it.
enum WindDownTimes {
    /// Go to bed = first alarm − sleep goal; wind-down = go to bed − length. Home late: wind-down
    /// waits for home + free time and lasts at least `minimum`, so bedtime moves later.
    static func compute(firstAlarm: Date, sleepGoal: Int, length: Int, free: Int, minimum: Int,
                        homeAt: Date? = nil) -> (windDown: Date, goToBed: Date) {
        var bed = firstAlarm.addingTimeInterval(-Double(sleepGoal) * 60)
        var wind = bed.addingTimeInterval(-Double(length) * 60)
        if let homeAt { wind = max(wind, homeAt.addingTimeInterval(Double(free) * 60)) }
        bed = max(bed, wind.addingTimeInterval(Double(minimum) * 60))
        return (wind, bed)
    }

    static func compute(firstAlarm: Date, settings: BridgeSettings) -> (windDown: Date, goToBed: Date) {
        compute(firstAlarm: firstAlarm, sleepGoal: settings.sleepGoalMinutes, length: settings.windDownMinutes,
                free: settings.freeAfterHomeMinutes, minimum: settings.minimumWindDownMinutes)
    }
}

/// What Home Assistant says about tonight's wind-down, from its last reply.
struct WindDownState: Codable, Equatable {
    enum Status: String, Codable { case scheduled, windingDown = "winding_down", bedtime, cancelled, off }

    var status: Status = .off
    var windDown: Date?
    var goToBed: Date?
    var firstAlarm: Date?
    var appointmentsChecked = true
    var remindersStopped = false
    var inBed = false
    /// The bedtime shortcut ran tonight (into bed).
    var bedtimeRan = false

    init(status: Status = .off, windDown: Date? = nil, goToBed: Date? = nil, firstAlarm: Date? = nil,
         remindersStopped: Bool = false, inBed: Bool = false) {
        self.status = status
        self.windDown = windDown
        self.goToBed = goToBed
        self.firstAlarm = firstAlarm
        self.remindersStopped = remindersStopped
        self.inBed = inBed
    }

    init(_ reply: [String: Any]) {
        func date(_ key: String) -> Date? {
            guard let text = reply[key] as? String else { return nil }
            let formatter = ISO8601DateFormatter()
            if let date = formatter.date(from: text) { return date }
            formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            return formatter.date(from: text)
        }
        status = Status(rawValue: reply["status"] as? String ?? "off") ?? .off
        windDown = date("wind_down")
        goToBed = date("go_to_bed")
        firstAlarm = date("first_alarm")
        appointmentsChecked = reply["appointments_checked"] as? Bool ?? true
        remindersStopped = reply["reminders_stopped"] as? Bool ?? false
        inBed = reply["in_bed"] as? Bool ?? false
        bedtimeRan = reply["bedtime_ran"] as? Bool ?? false
    }

    private static let key = "windDownState.v1"

    static var cached: WindDownState {
        get { UserDefaults.standard.data(forKey: key).flatMap { try? JSONDecoder().decode(WindDownState.self, from: $0) } ?? WindDownState() }
        set {
            UserDefaults.standard.set(try? JSONEncoder().encode(newValue), forKey: key)
            // The widget shows "Bed in 42 min" during wind-down.
            var snapshot = NextAlarmSnapshot.load()
            let active = [.scheduled, .windingDown, .bedtime].contains(newValue.status)
            snapshot.windDownAt = active ? newValue.windDown : nil
            snapshot.goToBedAt = active ? newValue.goToBed : nil
            snapshot.windDownStatus = newValue.status.rawValue
            snapshot.windDownCanStart = newValue.canStartNow(hours: SettingsStore.sharedHoursToStartWindDown)
            snapshot.save()
            ControlRefresh.reload()
        }
    }

    /// "Start wind-down now" shows from `hours` before go to bed, until wind-down starts.
    func canStartNow(hours: Int, now: Date = .now) -> Bool {
        guard status == .scheduled, let goToBed, let windDown, now < windDown else { return false }
        return now >= goToBed.addingTimeInterval(-Double(hours) * 3600)
    }
}
