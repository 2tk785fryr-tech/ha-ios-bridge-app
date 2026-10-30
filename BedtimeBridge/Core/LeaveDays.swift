import MapKit
import EventKit
import Foundation

/// Leave days (v0.4.3 item 12): an all-day event whose title is one of the leave titles
/// (trimmed, any case). Other events during leave work as usual.
enum LeaveDays {
    static func isLeave(title: String?, titles: [String]) -> Bool {
        let title = (title ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return titles.contains { $0.trimmingCharacters(in: .whitespacesAndNewlines).caseInsensitiveCompare(title) == .orderedSame && !title.isEmpty }
    }

    /// ONE all-day event from the start of the first day to the end of the last (the day after
    /// the last is where it stops: EventKit's end date is exclusive of that day).
    static func eventDates(first: Date, last: Date, calendar: Calendar = .current) -> (start: Date, end: Date) {
        let start = calendar.startOfDay(for: min(first, last))
        let lastDay = calendar.startOfDay(for: max(first, last))
        let end = calendar.date(byAdding: .day, value: 1, to: lastDay)!.addingTimeInterval(-1)
        return (start, end)
    }

    /// "Leave · Mon, Nov 3 – Fri, Nov 7 (5 days), all day, in Work"
    static func describe(title: String, first: Date, last: Date, calendarName: String, calendar: Calendar = .current) -> String {
        let dates = eventDates(first: first, last: last, calendar: calendar)
        let days = (calendar.dateComponents([.day], from: dates.start, to: dates.end).day ?? 0) + 1
        let format = Date.FormatStyle().weekday(.abbreviated).month(.abbreviated).day()
        let span = days == 1 ? dates.start.formatted(format) : "\(dates.start.formatted(format)) – \(dates.end.formatted(format)) (\(days) days)"
        return "\(title) · \(span), all day, in \(calendarName)"
    }
}

/// A wake-up event added from the app (v0.4.3 item 13): always marked with the keyword.
struct NewWakeUpEvent: Equatable {
    var title = ""
    var day: Date
    var start: Date
    var lengthMinutes = 60
    var location = ""

    /// The start: `start`'s time on `day`.
    func startDate(calendar: Calendar = .current) -> Date {
        let time = calendar.dateComponents([.hour, .minute], from: start)
        return calendar.date(bySettingHour: time.hour ?? 9, minute: time.minute ?? 0, second: 0, of: day) ?? day
    }

    func notes(keyword: String) -> String? { WakePlanner.notes(nil, settingWakeUp: true, keyword: keyword) }
}

extension CalendarService {
    /// All-day events (leave), which `events(from:to:)` leaves out.
    func allDayEvents(from start: Date, to end: Date, calendarIDs: Set<String>) -> [EKEvent] {
        let calendars = calendarIDs.isEmpty ? nil : eventCalendars().filter { calendarIDs.contains($0.calendarIdentifier) }
        return store.events(matching: store.predicateForEvents(withStart: start, end: end, calendars: calendars)).filter(\.isAllDay)
    }

    /// Is `day` a leave day?
    func isLeave(on day: Date, settings: BridgeSettings) -> Bool {
        guard EKEventStore.authorizationStatus(for: .event) == .fullAccess else { return false }
        let start = Calendar.current.startOfDay(for: day)
        let end = Calendar.current.date(byAdding: .day, value: 1, to: start)!
        return allDayEvents(from: start, to: end, calendarIDs: settings.shiftCalendarIDs.union(settings.appointmentCalendarIDs))
            .contains { LeaveDays.isLeave(title: $0.title, titles: settings.leaveTitles) }
    }

    /// "Calendar for new events": the chosen one, else the calendar holding the shifts.
    func newEventsCalendar(settings: BridgeSettings) -> EKCalendar? {
        let writable = eventCalendars().filter(\.allowsContentModifications)
        if let chosen = writable.first(where: { $0.calendarIdentifier == settings.newEventsCalendarID }) { return chosen }
        if let shifts = writable.first(where: { settings.shiftCalendarIDs.contains($0.calendarIdentifier) }) { return shifts }
        let now = Date.now
        let recentShift = events(from: now.addingTimeInterval(-30 * 86400), to: now.addingTimeInterval(30 * 86400), calendarIDs: [])
            .first { WakePlanner.matchingRule(forTitle: $0.title ?? "", rules: settings.shiftRules) != nil }
        if let calendar = recentShift?.calendar, calendar.allowsContentModifications { return calendar }
        return store.defaultCalendarForNewEvents
    }

    func addLeave(first: Date, last: Date, settings: BridgeSettings) throws -> EKEvent {
        guard let calendar = newEventsCalendar(settings: settings) else { throw BridgeError.eventNotFound }
        let event = EKEvent(eventStore: store)
        let dates = LeaveDays.eventDates(first: first, last: last)
        event.title = settings.leaveTitles.first ?? "Leave"
        event.isAllDay = true
        event.startDate = dates.start
        event.endDate = dates.end
        event.calendar = calendar
        try store.save(event, span: .thisEvent)
        return event
    }

    func addWakeUpEvent(_ new: NewWakeUpEvent, mapItem: MKMapItem?, settings: BridgeSettings) throws -> EKEvent {
        guard let calendar = newEventsCalendar(settings: settings) else { throw BridgeError.eventNotFound }
        let event = EKEvent(eventStore: store)
        event.title = new.title.trimmingCharacters(in: .whitespaces).isEmpty ? "Appointment" : new.title
        event.startDate = new.startDate()
        event.endDate = event.startDate.addingTimeInterval(Double(new.lengthMinutes) * 60)
        event.notes = new.notes(keyword: settings.appointmentKeyword)
        let place = new.location.trimmingCharacters(in: .whitespacesAndNewlines)
        if !place.isEmpty {
            event.location = place
            if let mapItem {
                let structured = EKStructuredLocation(mapItem: mapItem)
                structured.title = place
                event.structuredLocation = structured
            }
        }
        event.calendar = calendar
        try store.save(event, span: .thisEvent)
        return event
    }
}
