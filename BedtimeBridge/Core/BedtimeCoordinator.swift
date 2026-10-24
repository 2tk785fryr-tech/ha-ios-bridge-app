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
                return ShiftCandidate(title: event.title ?? rule.keyword, start: event.startDate, wakeMinutesBefore: rule.wakeMinutesBefore)
            }
            .first

        let appointmentEvents = calendar.events(from: now, to: end, calendarIDs: settings.appointmentCalendarIDs)
            .filter { event in
                WakePlanner.notesRequestWakeUp(event.notes, keyword: settings.appointmentKeyword)
                    && !(event.location ?? "").trimmingCharacters(in: .whitespaces).isEmpty
            }

        var appointments: [AppointmentCandidate] = []
        if !appointmentEvents.isEmpty {
            let origin = try? await travel.origin(homeAddress: settings.homeAddress)
            for event in appointmentEvents {
                appointments.append(await appointmentCandidate(for: event, origin: origin, settings: settings))
            }
        }

        return WakePlanner.plan(shift: shift, appointments: appointments, settings: settings, now: now)
    }

    func planAndSchedule(settings: BridgeSettings) async throws -> WakePlan {
        let plan = try await buildPlan(settings: settings)
        if plan.hasAlarm {
            try await alarms.replaceAlarms(with: plan.alarmTimes, title: alarmTitle(for: plan))
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
        let seconds = try await travel.drivingTime(from: origin, to: target, arrivingAt: arrival)
        return Int((seconds / 60).rounded())
    }

    private func appointmentCandidate(for event: EKEvent, origin: MKMapItem?, settings: BridgeSettings) async -> AppointmentCandidate {
        let title = event.title ?? "Appointment"
        let location = event.location ?? ""
        var seconds = Double(settings.fallbackTravelMinutes) * 60
        var usedFallback = true
        if let origin,
           let destination = try? await travel.destination(locationText: location, coordinates: event.structuredLocation?.geoLocation),
           let travelTime = try? await travel.drivingTime(from: origin, to: destination, arrivingAt: event.startDate) {
            seconds = travelTime
            usedFallback = false
        }
        return AppointmentCandidate(title: title, start: event.startDate, location: location, travelSeconds: seconds, usedFallbackTravel: usedFallback)
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
