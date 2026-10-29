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
