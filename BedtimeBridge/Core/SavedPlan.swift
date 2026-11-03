import Foundation

/// v0.4.11 items 3 and 4: the plan the alarms were set from, or the last preview, kept with when
/// it was worked out, so Your morning shows in full after the app was closed without asking for
/// drive times, weather or the calendar again.
struct SavedPlan: Codable, Equatable {
    var plan: WakePlan
    var asOf: Date

    /// When its event starts: the shift's or the appointment's.
    var eventStart: Date? {
        switch plan.source {
        case .shift: plan.shift?.start
        case .appointment: plan.appointment?.start
        case .manual, .none: nil
        }
    }

    /// Shown until the event starts or the morning is over (the late backstop + 60 min, or the
    /// last alarm + 60 min), whichever is later.
    func showsUntil(lateBackstop: Date?) -> Date? {
        let over = AlarmBubble.morningOver(lateBackstop: lateBackstop, lastAlarm: plan.alarmTimes.max() ?? plan.wakeTime)
        return [eventStart, over].compactMap { $0 }.max()
    }

    func shows(lateBackstop: Date?, now: Date = .now) -> Bool {
        showsUntil(lateBackstop: lateBackstop).map { now < $0 } ?? false
    }

    /// Kept on the phone this long after its morning, then forgotten (the screen stops showing
    /// it well before, at `showsUntil`).
    static let keep: TimeInterval = 12 * 3600

    func expired(now: Date = .now) -> Bool {
        showsUntil(lateBackstop: nil).map { now > $0.addingTimeInterval(Self.keep) } ?? (now > asOf.addingTimeInterval(36 * 3600))
    }

    static func load(_ key: String, defaults: UserDefaults = .standard, now: Date = .now) -> SavedPlan? {
        guard let data = defaults.data(forKey: key), let saved = try? JSONDecoder().decode(SavedPlan.self, from: data),
              !saved.expired(now: now) else { return nil }
        return saved
    }

    static func save(_ saved: SavedPlan?, key: String, defaults: UserDefaults = .standard) {
        defaults.set(saved.flatMap { try? JSONEncoder().encode($0) }, forKey: key)
    }
}
