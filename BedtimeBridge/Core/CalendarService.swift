import EventKit

enum BridgeError: LocalizedError {
    case calendarAccessDenied
    case alarmAccessDenied
    case locationNotFound(String)
    case homeAddressRequired
    case apiKeyMissing(String)
    case driveTimeService(String, Int, String)
    case homeAssistant(Int, String)

    var errorDescription: String? {
        switch self {
        case .calendarAccessDenied:
            "Calendar access is off. Allow full calendar access for Bedtime Bridge in Settings."
        case .alarmAccessDenied:
            "Alarm access is off. Allow alarms for Bedtime Bridge in Settings."
        case .locationNotFound(let query):
            "Couldn't find a location for \"\(query)\"."
        case .homeAddressRequired:
            "Set your home address in Settings to use TomTom or Google drive times."
        case .apiKeyMissing(let service):
            "Add your \(service) API key in Settings."
        case .driveTimeService(let service, let status, let body):
            "\(service) returned an error (\(status)): \(body)"
        case .homeAssistant(let status, let body):
            "Home Assistant returned an error (\(status)): \(body)"
        }
    }
}

final class CalendarService {
    let store = EKEventStore()

    func ensureAccess() async throws {
        switch EKEventStore.authorizationStatus(for: .event) {
        case .fullAccess:
            return
        case .notDetermined:
            guard try await store.requestFullAccessToEvents() else { throw BridgeError.calendarAccessDenied }
        default:
            throw BridgeError.calendarAccessDenied
        }
    }

    func eventCalendars() -> [EKCalendar] {
        store.calendars(for: .event).sorted { $0.title < $1.title }
    }

    func events(from start: Date, to end: Date, calendarIDs: Set<String>) -> [EKEvent] {
        let calendars = calendarIDs.isEmpty ? nil : eventCalendars().filter { calendarIDs.contains($0.calendarIdentifier) }
        let predicate = store.predicateForEvents(withStart: start, end: end, calendars: calendars)
        return store.events(matching: predicate)
            .filter { !$0.isAllDay && $0.startDate >= start }
            .sorted { $0.startDate < $1.startDate }
    }
}
