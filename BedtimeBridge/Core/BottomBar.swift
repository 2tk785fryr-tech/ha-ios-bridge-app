import Foundation

/// Everything the bottom bar, the ⋯ list and the protected slider can do (v0.4.2 item 6).
enum BarAction: String, CaseIterable, Identifiable {
    case setAlarms, replan, previewPlan, nap, notReadyForBed, sleepLater, editAlarms
    case upEarly, endAlarms, wakeLater, backToBed, endNap, changeNap
    case changeMorning, skip, notGoingToSleep, addTemporary, settings
    /// v0.4.3 items 2 and 3.
    case undo, noAlarmsTomorrow

    var id: String { rawValue }

    /// Protected actions are amber and need the slide-and-hold.
    var isProtected: Bool {
        switch self {
        case .notReadyForBed, .notGoingToSleep, .upEarly, .endAlarms, .sleepLater, .endNap, .changeNap,
             .wakeLater, .changeMorning, .backToBed, .skip, .undo, .noAlarmsTomorrow:
            true
        default:
            false
        }
    }

    /// Opens a screen whose commit step has the slider, instead of the bar's own slider.
    var opensScreen: Bool { [.sleepLater, .changeNap, .editAlarms, .noAlarmsTomorrow].contains(self) }

    enum Knob { case stop, moon, clock }

    /// Red stop (ending), amber moon (back to sleep, up early), purple clock (changing times).
    var knob: Knob {
        switch self {
        case .endAlarms, .endNap, .noAlarmsTomorrow: .stop
        case .notReadyForBed, .notGoingToSleep, .upEarly, .backToBed: .moon
        default: .clock
        }
    }

    func title(day: String) -> String {
        switch self {
        case .setAlarms: "Set alarms"
        case .replan: "Re-plan"
        case .previewPlan: "Preview plan"
        case .nap: "Nap"
        case .notReadyForBed: "Not ready for bed"
        case .sleepLater: "Sleep later…"
        case .editAlarms: "Edit alarms"
        case .upEarly: "I'm up early"
        case .endAlarms: "End alarms"
        case .wakeLater: "Wake later…"
        case .backToBed: "Back to bed"
        case .endNap: "End nap"
        case .changeNap: "Change nap"
        case .changeMorning: "Change this morning"
        case .skip: "Skip \(day)'s wake-up"
        case .notGoingToSleep: "Not going to sleep yet"
        case .addTemporary: "Add a temporary alarm"
        case .settings: "Settings"
        case .undo: "Undo"
        case .noAlarmsTomorrow: "No alarms tomorrow"
        }
    }

    /// What the slider will do, on the caption line above it.
    func caption(day: String) -> String {
        switch self {
        case .notReadyForBed, .notGoingToSleep: "Turn tonight's alarms off and undo bedtime"
        case .upEarly: "End this morning's alarms before they ring"
        case .endAlarms: "End the rest of this morning's alarms"
        case .endNap: "End your nap and turn its alarms off"
        case .wakeLater: "Wake later: change this morning's alarms"
        case .changeMorning: "Change this morning's alarms"
        case .backToBed: "Back to bed: move this morning's alarms or turn them off"
        case .skip: "Skip \(day)'s wake-up and sleep in"
        case .undo: "Undo: put back the alarms from before"
        case .noAlarmsTomorrow: "Turn tomorrow's alarms off"
        default: title(day: day)
        }
    }
}

/// The bottom bar for this moment: a top row (status, or the one main action) and two buttons
/// plus ⋯. It never grows.
struct BottomBar: Equatable {
    enum Tone: Equatable { case good, muted, snoozing, accent }

    enum Top: Equatable {
        case status(String, Tone)
        case main(BarAction, String)
        /// "3 alarms set · Undo": the status, and Undo is a tap away (v0.4.3 item 2).
        case undo(String)
    }

    var top: Top
    var buttons: [BarAction]

    struct Inputs {
        var now = Date.now
        var napUpAt: Date?
        var snoozingUntil: Date?
        var snoozing = false
        /// "Calendar changed · re-plan" when the set alarms no longer match.
        var plansChanged: String?
        /// Alarms of tonight's / this morning's series still set.
        var alarmsSet = 0
        var firstAlarm: Date?
        var nextAlarm: Date?
        var upEarlyWindow = false
        var notReadyWindow = false
        var backToBedWindow = false
        var sleepLaterWindow = false
        var leaveBy: Date?
        /// A plan on screen whose alarms aren't set: (count, up at).
        var planReady: (count: Int, up: Date?)?
        var tomorrow: Date?
        var napEnabled = false
        var evening = false
        /// "3 alarms set · Undo" while Undo applies (v0.4.3 items 2 and 3).
        var undo: String?
        /// Tomorrow has a wake-up that No alarms tomorrow could clear.
        var tomorrowHasAlarm = false
    }

    static func make(_ i: Inputs) -> BottomBar {
        let format = WakePlanner.format
        if let up = i.napUpAt {
            return BottomBar(top: .status("Napping · up at \(format(up))", .accent), buttons: [.endNap, .changeNap])
        }
        if i.snoozing {
            let rings = i.snoozingUntil.map { " · rings \(format($0))" } ?? ""
            return BottomBar(top: .status("Snoozing" + rings, .snoozing), buttons: [.endAlarms, .wakeLater])
        }
        if let changed = i.plansChanged {
            return BottomBar(top: .main(.replan, changed), buttons: [.previewPlan, .editAlarms])
        }
        if let undo = i.undo, !i.upEarlyWindow, !i.backToBedWindow {
            let buttons: [BarAction] = i.alarmsSet > 0
                ? (i.sleepLaterWindow ? [.sleepLater, .noAlarmsTomorrow] : [.noAlarmsTomorrow, .editAlarms])
                : [.previewPlan] + (i.napEnabled ? [.nap] : [])
            return BottomBar(top: .undo(undo), buttons: buttons)
        }
        if i.alarmsSet == 0, i.backToBedWindow {
            let leave = i.leaveBy.flatMap { $0 > i.now ? " · leave by \(format($0))" : nil } ?? ""
            return BottomBar(top: .status("Alarms off" + leave, .muted), buttons: [.backToBed, .previewPlan])
        }
        if i.alarmsSet > 0 {
            let count = i.alarmsSet == 1 ? "1 alarm set" : "\(i.alarmsSet) alarms set"
            if i.upEarlyWindow, let first = i.firstAlarm {
                if first > i.now {
                    return BottomBar(top: .status("\(count) · first at \(format(first))", .good), buttons: [.upEarly, .sleepLater])
                }
                let next = i.nextAlarm.map { " · next at \(format($0))" } ?? ""
                return BottomBar(top: .status(count + next, .good), buttons: [.endAlarms, .wakeLater])
            }
            if i.notReadyWindow {
                return BottomBar(top: .status("✓ " + count, .good), buttons: [.notReadyForBed, .sleepLater])
            }
            // v0.4.3 item 3: No alarms tomorrow takes Edit alarms' place (Edit stays in ⋯).
            return BottomBar(top: .status("✓ " + count, .good), buttons: i.sleepLaterWindow ? [.sleepLater, .noAlarmsTomorrow] : [.noAlarmsTomorrow, .editAlarms])
        }
        let nap: [BarAction] = i.napEnabled ? [.nap] : []
        if i.evening {
            if let plan = i.planReady, plan.count > 0 {
                let up = plan.up.map { " · up \(format($0))" } ?? ""
                return BottomBar(top: .main(.setAlarms, "Set \(plan.count) alarm\(plan.count == 1 ? "" : "s")" + up), buttons: [.previewPlan] + nap)
            }
            return BottomBar(top: .main(.setAlarms, "Plan and set alarms"), buttons: [.previewPlan] + nap)
        }
        let status = i.tomorrow.map { "Tomorrow \(format($0)) · not set yet" } ?? "Nothing set for tonight"
        return BottomBar(top: .status(status, .muted), buttons: nap + [.previewPlan])
    }

    /// The ⋯ list: the same list in every state, hiding what doesn't apply.
    static func menu(_ i: Inputs, alarmStyleApp: Bool, morningKnown: Bool) -> [BarAction] {
        var items: [BarAction] = [.previewPlan]
        if i.alarmsSet > 0 { items.append(.editAlarms) }
        if i.sleepLaterWindow { items.append(.sleepLater) }
        if i.napEnabled && i.napUpAt == nil { items.append(.nap) }
        if i.snoozing || (i.alarmsSet > 0 && i.upEarlyWindow) || i.backToBedWindow { items.append(.changeMorning) }
        let morning = i.snoozing || i.upEarlyWindow || i.backToBedWindow
        if !morning && (i.alarmsSet > 0 || i.tomorrowHasAlarm) { items.append(.noAlarmsTomorrow) }
        if morningKnown { items.append(.skip) }
        if i.notReadyWindow { items.append(.notGoingToSleep) }
        if alarmStyleApp { items.append(.addTemporary) }
        items.append(.settings)
        return items
    }
}
