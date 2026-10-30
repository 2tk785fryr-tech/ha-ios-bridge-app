import EventKit
import Foundation
import UserNotifications

/// Vacations (v0.4.7 item 6; "leave" before): all-day events whose title is one of Settings →
/// Vacations → Vacation titles.
struct Vacation: Identifiable, Equatable {
    var id: String
    var title: String
    var first: Date
    var last: Date
    /// "I'm travelling": drives and the weather from where you are.
    var travelling: Bool

    /// "Nov 3 – Nov 7" or "Nov 3".
    var rangeText: String {
        let format = Date.FormatStyle().month(.abbreviated).day()
        return Calendar.current.isDate(first, inSameDayAs: last) ? first.formatted(format) : "\(first.formatted(format)) – \(last.formatted(format))"
    }

    func covers(_ day: Date, calendar: Calendar = .current) -> Bool {
        let day = calendar.startOfDay(for: day)
        return day >= calendar.startOfDay(for: first) && day <= calendar.startOfDay(for: last)
    }
}

/// First and last day of a vacation, for Home Assistant's weekly summary (item 6f).
struct DayRange: Equatable {
    var first: Date
    var last: Date
}

enum Vacations {
    /// Written into a travelling vacation's notes, and how it's recognised.
    static let travellingNote = "Travelling (Bedtime Bridge)"

    static func isTravelling(notes: String?) -> Bool {
        let notes = (notes ?? "").lowercased()
        return notes.contains("travelling") || notes.contains("traveling")
    }

    /// The last day of an all-day event (its end is the end of that day, or the next midnight).
    static func lastDay(start: Date, end: Date, calendar: Calendar = .current) -> Date {
        let last = calendar.startOfDay(for: end.addingTimeInterval(-1))
        return max(last, calendar.startOfDay(for: start))
    }

    // MARK: Back to work (item 6a)

    struct BackToWork: Equatable {
        var vacation: Vacation
        var shift: ShiftCandidate
        var firstAlarm: Date
        /// The evening before the shift, at 6 PM.
        var remindAt: Date
    }

    /// For each vacation, the first shift after it (within a week), with its first alarm and
    /// when to remind (6 PM the evening before). Only reminders still ahead of `now`.
    static func backToWork(vacations: [Vacation], shifts: [ShiftCandidate], settings: BridgeSettings, now: Date,
                           calendar: Calendar = .current) -> [BackToWork] {
        vacations.compactMap { vacation in
            let afterLast = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: vacation.last))!
            guard let shift = shifts.filter({ $0.start >= afterLast && $0.start < afterLast.addingTimeInterval(7 * 86400) })
                .min(by: { $0.start < $1.start }) else { return nil }
            let times = WakePlanner.alarmTimes(wakeTime: shift.wakeTime, count: shift.alarmCount ?? settings.alarmCount,
                                               spacingMinutes: shift.alarmSpacingMinutes ?? settings.alarmSpacingMinutes,
                                               wakeIs: shift.wakeIs ?? settings.wakeTimeIs)
            guard let first = times.min() else { return nil }
            let dayBefore = calendar.date(byAdding: .day, value: -1, to: calendar.startOfDay(for: first))!
            guard let remindAt = calendar.date(bySettingHour: 18, minute: 0, second: 0, of: dayBefore), remindAt > now else { return nil }
            return BackToWork(vacation: vacation, shift: shift, firstAlarm: first, remindAt: remindAt)
        }
    }

    /// "Back to work tomorrow: Days at 6:30 AM, first alarm 4:20 AM (first day back: the backstops
    /// come 15 min earlier)."
    static func reminderText(_ back: BackToWork) -> String {
        "Back to work tomorrow: \(back.shift.cause) at \(WakePlanner.format(back.shift.start)), first alarm \(WakePlanner.format(back.firstAlarm)) "
            + "(first day back: the backstops come 15 min earlier)."
    }

    static let reminderPrefix = "backToWork."

    /// Replaces the back-to-work notifications with these.
    static func schedule(_ reminders: [BackToWork], center: UNUserNotificationCenter = .current()) async {
        let pending = await center.pendingNotificationRequests().map(\.identifier).filter { $0.hasPrefix(reminderPrefix) }
        center.removePendingNotificationRequests(withIdentifiers: pending)
        for back in reminders {
            let content = UNMutableNotificationContent()
            content.title = "Back to work tomorrow"
            content.body = reminderText(back)
            content.sound = .default
            let parts = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: back.remindAt)
            let request = UNNotificationRequest(identifier: reminderPrefix + back.vacation.id,
                                                content: content, trigger: UNCalendarNotificationTrigger(dateMatching: parts, repeats: false))
            try? await center.add(request)
        }
    }
}

extension CalendarService {
    /// Vacations overlapping `start`…`end`, earliest first.
    func vacations(from start: Date, to end: Date, settings: BridgeSettings) -> [Vacation] {
        guard EKEventStore.authorizationStatus(for: .event) == .fullAccess else { return [] }
        return allDayEvents(from: start, to: end, calendarIDs: settings.shiftCalendarIDs.union(settings.appointmentCalendarIDs))
            .filter { LeaveDays.isLeave(title: $0.title, titles: settings.leaveTitles) }
            .map { Vacation(id: $0.eventIdentifier ?? UUID().uuidString, title: $0.title ?? "Leave", first: Calendar.current.startOfDay(for: $0.startDate),
                            last: Vacations.lastDay(start: $0.startDate, end: $0.endDate), travelling: Vacations.isTravelling(notes: $0.notes)) }
            .sorted { $0.first < $1.first }
    }

    /// A travelling vacation covers `day`.
    func isTravelling(on day: Date, settings: BridgeSettings) -> Bool {
        vacations(from: Calendar.current.startOfDay(for: day), to: Calendar.current.startOfDay(for: day).addingTimeInterval(86400), settings: settings)
            .contains { $0.travelling && $0.covers(day) }
    }

    func addVacation(title: String, first: Date, last: Date, travelling: Bool, settings: BridgeSettings) throws -> EKEvent {
        guard let calendar = newEventsCalendar(settings: settings) else { throw BridgeError.eventNotFound }
        let event = EKEvent(eventStore: store)
        let dates = LeaveDays.eventDates(first: first, last: last)
        event.title = title
        event.isAllDay = true
        event.startDate = dates.start
        event.endDate = dates.end
        event.notes = travelling ? Vacations.travellingNote : nil
        event.calendar = calendar
        try store.save(event, span: .thisEvent)
        return event
    }

    /// Moves or shortens a vacation ("back early"), or changes whether you're travelling.
    func updateVacation(id: String, first: Date, last: Date, travelling: Bool) throws {
        guard let event = store.event(withIdentifier: id) else { throw BridgeError.eventNotFound }
        let dates = LeaveDays.eventDates(first: first, last: last)
        event.startDate = dates.start
        event.endDate = dates.end
        let others = (event.notes ?? "").components(separatedBy: "\n").filter { !Vacations.isTravelling(notes: $0) }
        event.notes = (others + (travelling ? [Vacations.travellingNote] : [])).filter { !$0.isEmpty }.joined(separator: "\n")
        try store.save(event, span: .thisEvent)
    }

    func deleteVacation(id: String) throws {
        guard let event = store.event(withIdentifier: id) else { throw BridgeError.eventNotFound }
        try store.remove(event, span: .thisEvent)
    }
}

extension BedtimeCoordinator {
    /// The back-to-work reminders for the vacations in the next 30 days (v0.4.7 item 6a), from
    /// the first shift after each (shift calendars, the shift rules).
    func scheduleBackToWork(settings phoneSettings: BridgeSettings, now: Date = .now) async {
        let settings = phoneSettings.applying(HomeAssistantLinks.cachedSettings)
        guard EKEventStore.authorizationStatus(for: .event) == .fullAccess else { return }
        let vacations = calendar.vacations(from: Calendar.current.startOfDay(for: now), to: now.addingTimeInterval(30 * 86400), settings: settings)
        let shifts = calendar.events(from: now, to: now.addingTimeInterval(40 * 86400), calendarIDs: settings.shiftCalendarIDs)
            .compactMap { event -> ShiftCandidate? in
                guard let rule = WakePlanner.matchingRule(forTitle: event.title ?? "", rules: settings.shiftRules) else { return nil }
                return ShiftCandidate.make(title: event.title ?? rule.keyword, start: event.startDate, rule: rule).0
            }
        await Vacations.schedule(Vacations.backToWork(vacations: vacations, shifts: shifts, settings: settings, now: now))
    }
}
