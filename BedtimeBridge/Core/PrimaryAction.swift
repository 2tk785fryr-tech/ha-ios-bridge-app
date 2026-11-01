import Foundation

/// Tonight's big button (v0.4.1 item 10): gone once the alarms are set, back (reworded) only when
/// something changed, and never one that would undo a change made this morning.
struct PrimaryAction: Equatable {
    /// nil: no button, show the alarm status instead.
    var buttonTitle: String?
    /// "Changed this morning: Tired"
    var note: String?

    /// `ownAlarms`: your own alarms are set; the calendar and the plan can't put them out of
    /// date (v0.4.8 item 3). `thisMorning`: from the up-early window to the end of the morning,
    /// no re-plan prompt; Change plan in ⋯ still re-plans (v0.4.10 item 4).
    static func make(alarmsSet: Bool, defaultTitle: String, changedThisMorning: String?, missingAlarms: Bool,
                     calendarChanged: Bool, planChanged: Bool, ownAlarms: Bool = false, thisMorning: Bool = false) -> PrimaryAction {
        guard alarmsSet || missingAlarms else { return PrimaryAction(buttonTitle: defaultTitle) }
        if let changedThisMorning {
            return PrimaryAction(note: "Changed this morning: \(changedThisMorning)")
        }
        if missingAlarms { return PrimaryAction(buttonTitle: "Set the missing alarms") }
        if ownAlarms || thisMorning { return PrimaryAction() }
        if calendarChanged { return PrimaryAction(buttonTitle: "Calendar changed: re-plan alarms") }
        if planChanged { return PrimaryAction(buttonTitle: "Plan changed: update alarms") }
        return PrimaryAction()
    }
}
