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
    /// Where the appointment is, kept so the leave-by reminder can recheck traffic.
    var latitude: Double? = nil
    var longitude: Double? = nil

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
    /// When you need to be up: the last or first alarm, per Settings.
    var wakeTime: Date? = nil
    var alarmTimes: [Date]
    var reason: String
    var shift: ShiftCandidate?
    var appointment: AppointmentCandidate?
    var weather: WeatherAdjustment? = nil
    /// From Home Assistant; nil when it couldn't tell.
    var atHome: Bool? = nil
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

    /// The alarm series around a wake-up time. With `.last` the wake-up time is the final
    /// alarm and the others count back from it; with `.first` they follow it.
    static func alarmTimes(wakeTime: Date, count: Int, spacingMinutes: Int, wakeIs: WakeTimeAlarm) -> [Date] {
        let count = max(count, 1)
        let first = wakeIs == .last
            ? wakeTime.addingTimeInterval(-Double((count - 1) * spacingMinutes) * 60)
            : wakeTime
        return (0..<count).map { first.addingTimeInterval(Double($0 * spacingMinutes) * 60) }
    }

    /// Picks the wake time: the shift's wake time, unless an appointment needs you up earlier.
    /// Bad weather moves a shift alarm earlier and adds to appointment drive times.
    static func plan(
        shift: ShiftCandidate?,
        appointments: [AppointmentCandidate],
        settings: BridgeSettings,
        now: Date,
        weather: WeatherAdjustment? = nil
    ) -> WakePlan {
        var warnings: [String] = []
        let extra = Double(weather?.minutes ?? 0) * 60
        let shift = shift.map { shift -> ShiftCandidate in
            var shift = shift
            shift.wakeMinutesBefore += weather?.minutes ?? 0
            return shift
        }
        let appointments = appointments.map { appointment -> AppointmentCandidate in
            var appointment = appointment
            appointment.travelSeconds += extra
            return appointment
        }

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

        let makeTimes = { (wake: Date) in
            alarmTimes(wakeTime: wake, count: settings.alarmCount, spacingMinutes: settings.alarmSpacingMinutes, wakeIs: settings.wakeTimeIs)
        }

        let weatherNote = weather.map { " +\($0.minutes) min for \($0.reason)" } ?? ""

        if let best = earliestAppointment, shiftWake.map({ best.1 < $0 }) ?? true {
            let (appointment, wake) = best
            let minutes = Int((appointment.travelSeconds / 60).rounded())
            let leaveBy = appointment.leaveBy(bufferMinutes: settings.arrivalBufferMinutes)
            return WakePlan(
                source: .appointment,
                wakeTime: wake,
                alarmTimes: makeTimes(wake),
                reason: "\(appointment.title) at \(format(appointment.start)). Leave by \(format(leaveBy)) (\(minutes) min drive, \(settings.arrivalBufferMinutes) min early)\(weatherNote)",
                shift: shift,
                appointment: appointment,
                weather: weather,
                warnings: warnings
            )
        }

        if let shift, let shiftWake {
            return WakePlan(
                source: .shift,
                wakeTime: shiftWake,
                alarmTimes: makeTimes(shiftWake),
                reason: "\(shift.cause) shift at \(format(shift.start))\(weatherNote)",
                shift: shift,
                appointment: earliestAppointment?.0,
                weather: weather,
                warnings: warnings
            )
        }

        return WakePlan(source: .none, alarmTimes: [], reason: "No shift or wake-up appointment found", warnings: warnings)
    }

    static func format(_ date: Date) -> String {
        date.formatted(date: .omitted, time: .shortened)
    }
}
