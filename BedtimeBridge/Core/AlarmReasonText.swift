import Foundation

/// "Reason for alarm: Days shift" at the bottom of Tonight (v0.4.1 item 9), in place of the raw
/// alarm_cause. Display only: what's sent to Home Assistant doesn't change.
enum AlarmReasonText {
    /// - Parameters:
    ///   - cause: the plan's alarm_cause ("Days", "calendar", "automade", "noalarm").
    ///   - label: the plan's label (the appointment's title for "calendar").
    ///   - insteadOfShift: the shift a marked appointment replaced (item 11), if any.
    ///   - changeReason: why this morning was changed, if it was.
    static func make(cause: String, label: String?, insteadOfShift: String? = nil, changeReason: String? = nil) -> String {
        let what: String
        switch cause {
        case AlarmCause.calendar:
            let title = label.flatMap { $0.isEmpty ? nil : $0 } ?? "appointment"
            what = "Appointment: \(title)" + (insteadOfShift.map { " (instead of \($0))" } ?? "")
        case AlarmCause.manual: what = "Your own time"
        case AlarmCause.none, "": what = "No alarm"
        default: what = "\(cause) shift"
        }
        return "Reason for alarm: \(what)" + (changeReason.map { " (morning changed: \($0))" } ?? "")
    }
}

extension AlarmReasonText {
    /// "Nothing on Sunday": a preview that found nothing for the next morning (v0.4.9 item 9).
    /// Before 4 AM the next morning is today's.
    static func nothingOn(now: Date, calendar: Calendar = .current) -> String {
        let morning = calendar.component(.hour, from: now) < 4 ? now : calendar.nextDay(after: now)
        let day = DateFormatter()
        day.calendar = calendar
        day.timeZone = calendar.timeZone
        day.locale = ClockStyle.locale
        day.setLocalizedDateFormatFromTemplate("EEEE")
        return "Nothing on \(day.string(from: morning))"
    }

    /// v0.4.10 item 7: under a preview that found nothing, the alarms you already set, as
    /// ("You already have alarms set at ", "8:00, 8:10, 8:20", ". You can still change or cancel
    /// them."), so the times can be bold. nil with none set.
    /// v0.4.10 item 16: what tomorrow has, for "Days shift 6:30 · no alarms set": the shift's
    /// keyword or the appointment's title, and its start. nil with neither.
    static func tomorrowLabel(_ plan: WakePlan?) -> String? {
        guard let plan else { return nil }
        if plan.source == .shift, let shift = plan.shift { return "\(shift.cause) shift \(WakePlanner.format(shift.start))" }
        if plan.source == .appointment, let appointment = plan.appointment { return "\(appointment.title) \(WakePlanner.format(appointment.start))" }
        return nil
    }

    /// v0.4.10 item 12: the pill's forecast, only when it's for these alarms' first one.
    static func wakeWeather(_ forecast: MorningForecast?, firstAlarm: Date?) -> MorningForecast? {
        guard let forecast, let firstAlarm, abs(forecast.at.timeIntervalSince(firstAlarm)) < 60 else { return nil }
        return forecast
    }

    static func alreadySet(_ times: [Date]) -> (lead: String, times: String, tail: String)? {
        guard !times.isEmpty else { return nil }
        let one = times.count == 1
        return ("You already have \(one ? "an alarm" : "alarms") set at ",
                times.sorted().map(WakePlanner.format).joined(separator: ", "),
                ". You can still change or cancel \(one ? "it" : "them").")
    }
}
