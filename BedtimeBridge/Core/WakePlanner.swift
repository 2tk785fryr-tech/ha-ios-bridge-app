import Foundation

/// The next shift found on the calendar, with the rule that matched it.
struct ShiftCandidate: Equatable {
    var title: String
    var start: Date
    var wakeMinutesBefore: Int

    var wakeTime: Date { start.addingTimeInterval(-Double(wakeMinutesBefore) * 60) }
}

/// An appointment whose notes asked for a wake-up, with its drive time already resolved.
struct AppointmentCandidate: Equatable {
    var title: String
    var start: Date
    var location: String
    var travelSeconds: TimeInterval
    /// True when the drive time could not be calculated and the fallback was used.
    var usedFallbackTravel: Bool

    func wakeTime(getReadyMinutes: Int) -> Date {
        start.addingTimeInterval(-travelSeconds - Double(getReadyMinutes) * 60)
    }
}

enum WakeSource: String, Codable {
    case shift
    case appointment
    case manual
    case none
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
            .map { ($0, $0.wakeTime(getReadyMinutes: settings.getReadyMinutes)) }
            .filter { $0.1 > now }
            .min { $0.1 < $1.1 }

        for appointment in appointments where appointment.wakeTime(getReadyMinutes: settings.getReadyMinutes) <= now {
            warnings.append("\(appointment.title) needs you up before now; skipped.")
        }
        for appointment in appointments where appointment.usedFallbackTravel {
            warnings.append("Couldn't get a drive time to \(appointment.title); used \(settings.fallbackTravelMinutes) min.")
        }

        let makeTimes = { (first: Date) in
            alarmTimes(first: first, count: settings.alarmCount, spacingMinutes: settings.alarmSpacingMinutes)
        }

        if let best = earliestAppointment, shiftWake.map({ best.1 < $0 }) ?? true {
            let (appointment, wake) = best
            let minutes = Int((appointment.travelSeconds / 60).rounded())
            return WakePlan(
                source: .appointment,
                alarmTimes: makeTimes(wake),
                reason: "\(appointment.title) at \(format(appointment.start)), \(minutes) min drive",
                shift: shift,
                appointment: appointment,
                warnings: warnings
            )
        }

        if let shift, let shiftWake {
            return WakePlan(
                source: .shift,
                alarmTimes: makeTimes(shiftWake),
                reason: "\(shift.title) shift at \(format(shift.start))",
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
