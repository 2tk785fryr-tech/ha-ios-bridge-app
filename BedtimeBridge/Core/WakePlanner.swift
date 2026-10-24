import Foundation

/// The next shift found on the calendar, with the rule that matched it.
struct ShiftCandidate: Equatable {
    var title: String
    var start: Date
    var wakeMinutesBefore: Int
    /// The matching rule's keyword ("Days", "Swings"), sent to Home Assistant as the cause.
    var cause: String

    var wakeTime: Date { start.addingTimeInterval(-Double(wakeMinutesBefore) * 60) }
}

/// An appointment whose notes asked for a wake-up, with its drive time already resolved.
struct AppointmentCandidate: Equatable {
    var title: String
    var start: Date
    var location: String
    /// Drive time for arriving `arrivalBufferMinutes` before the start.
    var travelSeconds: TimeInterval
    /// Set when the drive time could not be calculated and the fallback was used.
    var fallbackReason: String? = nil

    var usedFallbackTravel: Bool { fallbackReason != nil }

    /// When you have to be there: the start time minus the buffer.
    func arriveBy(bufferMinutes: Int) -> Date {
        start.addingTimeInterval(-Double(bufferMinutes) * 60)
    }

    func leaveBy(bufferMinutes: Int) -> Date {
        arriveBy(bufferMinutes: bufferMinutes).addingTimeInterval(-travelSeconds)
    }

    func wakeTime(settings: BridgeSettings) -> Date {
        leaveBy(bufferMinutes: settings.arrivalBufferMinutes).addingTimeInterval(-Double(settings.getReadyMinutes) * 60)
    }
}

enum WakeSource: String, Codable {
    case shift
    case appointment
    case manual
    case none
}

/// Values sent to Home Assistant as `alarm_cause`. Shifts send their rule keyword instead.
enum AlarmCause {
    static let calendar = "calendar"
    static let manual = "automade"
    static let none = "noalarm"
}

struct WakePlan: Equatable {
    var source: WakeSource
    var alarmTimes: [Date]
    var reason: String
    var shift: ShiftCandidate?
    var appointment: AppointmentCandidate?
    var warnings: [String] = []

    var firstAlarm: Date? { alarmTimes.first }
    var hasAlarm: Bool { !alarmTimes.isEmpty }

    /// What caused the alarm: "Days" / "Swings" (or another shift keyword), "calendar",
    /// "automade" (time picked by you) or "noalarm".
    var cause: String {
        switch source {
        case .shift: shift?.cause ?? AlarmCause.none
        case .appointment: AlarmCause.calendar
        case .manual: AlarmCause.manual
        case .none: AlarmCause.none
        }
    }
}

/// Pure decision logic: no EventKit, MapKit or AlarmKit, so it can be unit tested.
enum WakePlanner {
    static func matchingRule(forTitle title: String, rules: [ShiftRule]) -> ShiftRule? {
        rules.first { rule in
            let keyword = rule.keyword.trimmingCharacters(in: .whitespaces)
            return !keyword.isEmpty && title.range(of: keyword, options: [.caseInsensitive, .diacriticInsensitive]) != nil
        }
    }

    static func notesRequestWakeUp(_ notes: String?, keyword: String) -> Bool {
        guard let notes, !keyword.isEmpty else { return false }
        return notes.range(of: keyword, options: [.caseInsensitive, .diacriticInsensitive]) != nil
    }

    static func alarmTimes(first: Date, count: Int, spacingMinutes: Int) -> [Date] {
        (0..<max(count, 1)).map { first.addingTimeInterval(Double($0 * spacingMinutes) * 60) }
    }

    /// Picks the wake time: the shift's wake time, unless an appointment needs you up earlier.
    static func plan(
        shift: ShiftCandidate?,
        appointments: [AppointmentCandidate],
        settings: BridgeSettings,
        now: Date
    ) -> WakePlan {
        var warnings: [String] = []

        var shiftWake: Date?
        if let shift {
            if shift.wakeTime > now {
                shiftWake = shift.wakeTime
            } else {
                warnings.append("Wake time for \(shift.title) has already passed.")
            }
        }

        let earliestAppointment = appointments
            .map { ($0, $0.wakeTime(settings: settings)) }
            .filter { $0.1 > now }
            .min { $0.1 < $1.1 }

        for appointment in appointments where appointment.wakeTime(settings: settings) <= now {
            warnings.append("\(appointment.title) needs you up before now; skipped.")
        }
        for appointment in appointments {
            if let reason = appointment.fallbackReason {
                warnings.append("No drive time to \(appointment.title) (\(reason)); used \(settings.fallbackTravelMinutes) min.")
            }
        }

        let makeTimes = { (first: Date) in
            alarmTimes(first: first, count: settings.alarmCount, spacingMinutes: settings.alarmSpacingMinutes)
        }

        if let best = earliestAppointment, shiftWake.map({ best.1 < $0 }) ?? true {
            let (appointment, wake) = best
            let minutes = Int((appointment.travelSeconds / 60).rounded())
            let leaveBy = appointment.leaveBy(bufferMinutes: settings.arrivalBufferMinutes)
            return WakePlan(
                source: .appointment,
                alarmTimes: makeTimes(wake),
                reason: "\(appointment.title) at \(format(appointment.start)). Leave by \(format(leaveBy)) (\(minutes) min drive, \(settings.arrivalBufferMinutes) min early)",
                shift: shift,
                appointment: appointment,
                warnings: warnings
            )
        }

        if let shift, let shiftWake {
            return WakePlan(
                source: .shift,
                alarmTimes: makeTimes(shiftWake),
                reason: "\(shift.cause) shift at \(format(shift.start))",
                shift: shift,
                appointment: earliestAppointment?.0,
                warnings: warnings
            )
        }

        return WakePlan(source: .none, alarmTimes: [], reason: "No shift or wake-up appointment found", warnings: warnings)
    }

    static func format(_ date: Date) -> String {
        date.formatted(date: .omitted, time: .shortened)
    }
}
