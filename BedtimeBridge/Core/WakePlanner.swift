import Foundation

/// The next shift found on the calendar, with the rule that matched it.
struct ShiftCandidate: Equatable {
    var title: String
    var start: Date
    var wakeMinutesBefore: Int
    /// The matching rule's keyword ("Days", "Swings"), sent to Home Assistant as the cause.
    var cause: String
    /// Set for fixed-time rules (e.g. Swings at 8:00 AM on the shift's day).
    var fixedWake: Date? = nil
    /// This shift's alarm series; nil parts use the general settings.
    var wakeIs: WakeTimeAlarm? = nil
    var alarmCount: Int? = nil
    var alarmSpacingMinutes: Int? = nil

    var wakeTime: Date { fixedWake ?? start.addingTimeInterval(-Double(wakeMinutesBefore) * 60) }

    /// Builds the candidate from its rule. A fixed time that would land at or after the shift
    /// start (a misconfigured rule) falls back to minutes-before, with a warning.
    static func make(title: String, start: Date, rule: ShiftRule, calendar: Calendar = .current) -> (ShiftCandidate, String?) {
        var candidate = ShiftCandidate(
            title: title,
            start: start,
            wakeMinutesBefore: rule.wakeMinutesBefore,
            cause: rule.keyword.trimmingCharacters(in: .whitespaces),
            wakeIs: rule.wakeIs,
            alarmCount: rule.alarmCount,
            alarmSpacingMinutes: rule.alarmSpacingMinutes
        )
        guard rule.timing == .fixedTime else { return (candidate, nil) }
        let fixed = calendar.date(bySettingHour: rule.fixedHour, minute: rule.fixedMinute, second: 0, of: start)
        guard let fixed, fixed < start else {
            return (candidate, "\(rule.keyword)'s fixed alarm time is after the shift starts; used \(rule.wakeMinutesBefore) min before instead.")
        }
        candidate.fixedWake = fixed
        return (candidate, nil)
    }
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
    /// The calendar event, so a missing location can be filled in.
    var eventID: String? = nil
    /// False for a "wake up" appointment with no location (a call, or one saved without
    /// its place).
    var hasLocation = true
    /// No location and you haven't said "no location needed" yet. Until you answer it's
    /// planned with the fallback drive time, so an unanswered question errs toward waking
    /// early; once you confirm, it has no drive.
    var askAboutLocation = false

    /// Planned as a trip somewhere (a real location, or one we're not sure about yet).
    var plannedWithDrive: Bool { hasLocation || askAboutLocation }

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
    /// "Wake up" appointments without a location that might have been saved without one.
    var missingLocations: [AppointmentCandidate] = []

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

    /// Notes with the keyword added on its own line, or every mention of it taken out.
    /// A line left empty by the removal goes too; the rest of the notes are kept as written.
    static func notes(_ notes: String?, settingWakeUp wakeUp: Bool, keyword: String) -> String? {
        let keyword = keyword.trimmingCharacters(in: .whitespaces)
        guard !keyword.isEmpty, notesRequestWakeUp(notes, keyword: keyword) != wakeUp else { return notes }
        let notes = notes ?? ""
        if wakeUp {
            return notes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? keyword : notes + "\n" + keyword
        }
        let lines = notes.components(separatedBy: .newlines).compactMap { line -> String? in
            let removed = line.replacingOccurrences(of: keyword, with: "", options: [.caseInsensitive, .diacriticInsensitive])
            guard removed != line else { return line }
            let trimmed = removed.trimmingCharacters(in: .whitespaces)
            return trimmed.isEmpty ? nil : trimmed
        }
        let result = lines.joined(separator: "\n")
        return result.isEmpty ? nil : result
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
        // Bad weather moves a commute-based alarm earlier; a fixed-time alarm (Swings at
        // 8:00 AM, hours before the drive) stays put.
        let shift = shift.map { shift -> ShiftCandidate in
            var shift = shift
            if shift.fixedWake == nil { shift.wakeMinutesBefore += weather?.minutes ?? 0 }
            return shift
        }
        let appointments = appointments.map { appointment -> AppointmentCandidate in
            var appointment = appointment
            // Bad weather slows the drive; it doesn't matter for a call from home.
            if appointment.plannedWithDrive { appointment.travelSeconds += extra }
            return appointment
        }
        let missing = appointments.filter(\.askAboutLocation)

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
            let reason: String
            if appointment.hasLocation {
                reason = "\(appointment.title) at \(format(appointment.start)). Leave by \(format(leaveBy)) (\(minutes) min drive, \(settings.arrivalBufferMinutes) min early)\(weatherNote)"
            } else if appointment.askAboutLocation {
                reason = "\(appointment.title) at \(format(appointment.start)) has no location; planned with a \(minutes) min drive to be safe\(weatherNote)"
            } else {
                reason = "\(appointment.title) at \(format(appointment.start)). Ready by \(format(leaveBy)) (no location needed)"
            }
            return WakePlan(
                source: .appointment,
                wakeTime: wake,
                alarmTimes: makeTimes(wake),
                reason: reason,
                shift: shift,
                appointment: appointment,
                weather: appointment.plannedWithDrive ? weather : nil,
                warnings: warnings,
                missingLocations: missing
            )
        }

        if let shift, let shiftWake {
            let shiftWeather = shift.fixedWake == nil ? weather : nil
            let times = alarmTimes(
                wakeTime: shiftWake,
                count: shift.alarmCount ?? settings.alarmCount,
                spacingMinutes: shift.alarmSpacingMinutes ?? settings.alarmSpacingMinutes,
                wakeIs: shift.wakeIs ?? settings.wakeTimeIs
            )
            return WakePlan(
                source: .shift,
                wakeTime: shiftWake,
                alarmTimes: times,
                reason: "\(shift.cause) shift at \(format(shift.start))\(shiftWeather == nil ? "" : weatherNote)",
                shift: shift,
                appointment: earliestAppointment?.0,
                weather: shiftWeather,
                warnings: warnings,
                missingLocations: missing
            )
        }

        return WakePlan(source: .none, alarmTimes: [], reason: "No shift or wake-up appointment found", warnings: warnings, missingLocations: missing)
    }

    static func format(_ date: Date) -> String {
        date.formatted(date: .omitted, time: .shortened)
    }
}
