import EventKit
import MapKit

enum BridgeError: LocalizedError {
    case calendarAccessDenied
    case alarmAccessDenied
    case locationNotFound(String)
    case locationAccessDenied
    case homeAddressRequired
    case apiKeyMissing(String)
    case driveTimeService(String, Int, String)
    case homeAssistant(Int, String)
    case homeAssistantNotSetUp
    case eventNotFound

    var errorDescription: String? {
        switch self {
        case .calendarAccessDenied:
            "Calendar access is off. Allow full calendar access for Bedtime Bridge in Settings."
        case .alarmAccessDenied:
            "Alarm access is off. Allow alarms for Bedtime Bridge in Settings."
        case .locationNotFound(let query):
            "Couldn't find a location for \"\(query)\"."
        case .locationAccessDenied:
            "Location access is off. Allow location for Bedtime Bridge in Settings, or type your address."
        case .homeAddressRequired:
            "Set your home address in Settings to use TomTom or Google drive times."
        case .apiKeyMissing(let service):
            "Add your \(service) API key in Settings."
        case .driveTimeService(let service, let status, let body):
            "\(service) returned an error (\(status)): \(body)"
        case .homeAssistant(let status, let body):
            "Home Assistant returned an error (\(status)): \(body)"
        case .homeAssistantNotSetUp:
            "Connect Home Assistant in Bedtime Bridge's settings first."
        case .eventNotFound:
            "That calendar event couldn't be found. It may have been moved or deleted."
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

    /// Fills in a location the event was saved without (you confirmed it should have one).
    func setLocation(_ location: String, eventID: String) throws {
        guard let event = store.event(withIdentifier: eventID) else { throw BridgeError.eventNotFound }
        event.location = location
        try store.save(event, span: .thisEvent)
    }

    /// Saves the location on this occurrence only. A place picked from Maps also stores its
    /// coordinates, which drive times use instead of searching the text.
    func setLocation(_ location: String, mapItem: MKMapItem?, on event: EKEvent) throws {
        event.location = location
        if let mapItem {
            let structured = EKStructuredLocation(mapItem: mapItem)
            structured.title = location
            event.structuredLocation = structured
        }
        try store.save(event, span: .thisEvent)
    }

    /// Adds or removes the wake-up keyword in this occurrence's notes.
    func setWakeUp(_ wakeUp: Bool, keyword: String, on event: EKEvent) throws {
        event.notes = WakePlanner.notes(event.notes, settingWakeUp: wakeUp, keyword: keyword)
        try store.save(event, span: .thisEvent)
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
