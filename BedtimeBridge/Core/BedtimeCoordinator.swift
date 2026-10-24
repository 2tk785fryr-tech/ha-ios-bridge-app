import EventKit
import Foundation
import MapKit

/// Glues calendar, drive time and alarms together. Used by both the app UI and the
/// Shortcuts actions, so the bedtime shortcut and the "Preview" button behave the same.
@MainActor
final class BedtimeCoordinator {
    static let shared = BedtimeCoordinator()

    let calendar = CalendarService()
    let travel = TravelTimeService()
    let alarms = AlarmScheduler()

    /// Works out tonight's wake-up without touching any alarms.
    func buildPlan(settings: BridgeSettings, now: Date = .now) async throws -> WakePlan {
        try await calendar.ensureAccess()
        let end = now.addingTimeInterval(Double(settings.lookAheadHours) * 3600)

        let shift = calendar.events(from: now, to: end, calendarIDs: settings.shiftCalendarIDs)
            .lazy
            .compactMap { event -> ShiftCandidate? in
                guard let rule = WakePlanner.matchingRule(forTitle: event.title ?? "", rules: settings.shiftRules) else { return nil }
                return ShiftCandidate(
                    title: event.title ?? rule.keyword,
                    start: event.startDate,
                    wakeMinutesBefore: rule.wakeMinutesBefore,
                    cause: rule.keyword.trimmingCharacters(in: .whitespaces)
                )
            }
            .first

        let appointmentEvents = calendar.events(from: now, to: end, calendarIDs: settings.appointmentCalendarIDs)
            .filter { event in
                WakePlanner.notesRequestWakeUp(event.notes, keyword: settings.appointmentKeyword)
                    && !(event.location ?? "").trimmingCharacters(in: .whitespaces).isEmpty
            }

        var appointments: [AppointmentCandidate] = []
        if !appointmentEvents.isEmpty {
            // A missing origin or API key becomes the fallback reason on each appointment.
            let route: Result<(MKMapItem, DriveTimeProvider), Error>
            do {
                route = .success((try await travel.origin(homeAddress: settings.homeAddress), try travel.provider(for: settings)))
            } catch {
                route = .failure(error)
            }
            for event in appointmentEvents {
                appointments.append(await appointmentCandidate(for: event, route: route, settings: settings))
            }
        }

        return WakePlanner.plan(shift: shift, appointments: appointments, settings: settings, now: now)
    }

    func planAndSchedule(settings: BridgeSettings) async throws -> WakePlan {
        let plan = try await buildPlan(settings: settings)
        if plan.hasAlarm {
            try await alarms.replaceAlarms(with: plan.alarmTimes, title: alarmTitle(for: plan))
        } else {
            // Don't leave last night's alarms ringing on a day off.
            try alarms.cancelAll()
        }
        return plan
    }

    /// For the day-off path: you pick the time, the app sets the usual alarm series.
    func scheduleManual(firstAlarm: Date, settings: BridgeSettings) async throws -> WakePlan {
        let first = Self.nextOccurrence(ofTimeIn: firstAlarm)
        let times = WakePlanner.alarmTimes(first: first, count: settings.alarmCount, spacingMinutes: settings.alarmSpacingMinutes)
        try await alarms.replaceAlarms(with: times, title: "Wake up")
        return WakePlan(source: .manual, alarmTimes: times, reason: "Day off alarm")
    }

    func drivingMinutes(to destination: String, arrivingAt arrival: Date, settings: BridgeSettings) async throws -> Int {
        let origin = try await travel.origin(homeAddress: settings.homeAddress)
        let target = try await travel.destination(locationText: destination, coordinates: nil)
        let seconds = try await travel.provider(for: settings).drivingTime(from: origin, to: target, arrivingBy: arrival)
        return Int((seconds / 60).rounded())
    }

    private func appointmentCandidate(
        for event: EKEvent,
        route: Result<(MKMapItem, DriveTimeProvider), Error>,
        settings: BridgeSettings
    ) async -> AppointmentCandidate {
        var candidate = AppointmentCandidate(
            title: event.title ?? "Appointment",
            start: event.startDate,
            location: event.location ?? "",
            travelSeconds: Double(settings.fallbackTravelMinutes) * 60
        )
        do {
            let (origin, provider) = try route.get()
            let destination = try await travel.destination(locationText: candidate.location, coordinates: event.structuredLocation?.geoLocation)
            candidate.travelSeconds = try await provider.drivingTime(
                from: origin,
                to: destination,
                arrivingBy: candidate.arriveBy(bufferMinutes: settings.arrivalBufferMinutes)
            )
        } catch {
            candidate.fallbackReason = error.localizedDescription
        }
        return candidate
    }

    private func alarmTitle(for plan: WakePlan) -> String {
        switch plan.source {
        case .shift: "Wake up for \(plan.shift?.title ?? "work")"
        case .appointment: "Wake up for \(plan.appointment?.title ?? "your appointment")"
        case .manual, .none: "Wake up"
        }
    }

    /// Shortcuts' "Ask for Input" with a time often returns today's date; a time that has
    /// already passed today means tomorrow morning.
    nonisolated static func nextOccurrence(ofTimeIn date: Date, now: Date = .now, calendar: Calendar = .current) -> Date {
        guard date <= now else { return date }
        let parts = calendar.dateComponents([.hour, .minute], from: date)
        return calendar.nextDate(after: now, matching: parts, matchingPolicy: .nextTime) ?? date
    }
}
