import Foundation

/// Everything the bottom bar, the ⋯ list and the protected slider can do (v0.4.2 item 6).
enum BarAction: String, CaseIterable, Identifiable {
    case setAlarms, replan, previewPlan, nap, notReadyForBed, sleepLater, editAlarms
    case upEarly, endAlarms, wakeLater, backToBed, endNap, changeNap
    case changeMorning, skip, notGoingToSleep, addTemporary, settings
    /// v0.4.3 items 2 and 3.
    case undo, noAlarmsTomorrow
    /// v0.4.3 item 5.
    case startWindDown, cancelWindDown, stopReminders
    /// v0.4.3 items 12 and 13.
    case addLeave, addWakeUpEvent
    /// v0.4.6 item 2: good morning on a morning with no alarms.
    case imAwake
    /// v0.4.7 item 8: your own alarms when nothing is set.
    case setAlarmsForTime
    /// v0.4.8 item 5: start bedtime, and every way to change tonight's alarms.
    case goodNight, changePlan
    /// v0.4.8 item 9: a testing report.
    case report

    var id: String { rawValue }

    /// Protected actions are amber and need the slide-and-hold.
    var isProtected: Bool {
        switch self {
        case .notReadyForBed, .notGoingToSleep, .upEarly, .endAlarms, .sleepLater, .endNap, .changeNap,
             .wakeLater, .changeMorning, .backToBed, .skip, .undo, .noAlarmsTomorrow, .imAwake, .goodNight:
            true
        default:
            false
        }
    }

    /// Opens a screen whose commit step has the slider, instead of the bar's own slider.
    var opensScreen: Bool { [.sleepLater, .changeNap, .editAlarms, .noAlarmsTomorrow, .changePlan].contains(self) }

    enum Knob { case stop, moon, clock }

    /// Red stop (ending), amber moon (back to sleep, up early), purple clock (changing times).
    var knob: Knob {
        switch self {
        case .endAlarms, .endNap, .noAlarmsTomorrow: .stop
        case .notReadyForBed, .notGoingToSleep, .upEarly, .backToBed, .imAwake, .goodNight: .moon
        default: .clock
        }
    }

    /// The bar's day is today's: after midnight, "No alarms this morning" (v0.4.8 item 7).
    static func isToday(_ day: String, now: Date = .now) -> Bool {
        day == now.formatted(.dateTime.weekday(.wide))
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
        case .noAlarmsTomorrow: Self.isToday(day) ? "No alarms this morning" : "No alarms tomorrow"
        case .startWindDown: "Start wind-down now"
        case .cancelWindDown: "Cancel wind-down"
        case .stopReminders: "Stop bedtime reminders"
        case .addLeave: "Add vacation"
        case .addWakeUpEvent: "Add a wake-up event"
        case .imAwake: "I'm awake"
        case .setAlarmsForTime: "Set alarms for a time"
        case .goodNight: "Good night"
        case .changePlan: "Change plan"
        case .report: "Report something"
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
        case .noAlarmsTomorrow: Self.isToday(day) ? "Turn this morning's alarms off" : "Turn tomorrow's alarms off"
        case .imAwake: "Good morning: Sleep In off, wake the house"
        case .goodNight: "Good night: start bedtime now; the lights go off"
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
    /// A row of filled buttons between the top and the buttons (v0.4.7 item 8: nothing set).
    var actionRow: [BarAction] = []
    /// A slide-and-hold filling the middle row (v0.4.8 item 5: Good night), with Undo on the
    /// status line while it applies.
    var hold: BarAction? = nil
    var undoOffered = false

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
        /// Tonight's wind-down from Home Assistant (v0.4.3 item 5).
        var windDown: WindDownState?
        var startWindDownHours = 2
        /// A morning with no alarms, from Home Assistant (v0.4.6 item 2).
        var awakeOffered = false
        /// A preview found no shift or event (v0.4.7 item 8).
        var nothingFound = false
        var alarmStyleApp = true
        /// Alarms set and bedtime not run since (v0.4.8 item 5).
        var goodNight = false
        /// Testing reports are on (v0.4.8 item 9): Report something heads ⋯.
        var reporting = false
        /// The bedtime check found something (v0.4.8 item 14).
        var healthIssue: String?
    }

    /// Wind-down's states (9 before, 10 during, 11 after go to bed and not in bed).
    private static func windDownBar(_ i: Inputs) -> BottomBar? {
        guard let w = i.windDown else { return nil }
        let format = WakePlanner.format
        let first = w.firstAlarm.map { " · first alarm \(format($0))" } ?? ""
        if w.status == .bedtime, !w.bedtimeRan, !w.inBed, !w.remindersStopped, let bed = w.goToBed, i.now >= bed {
            return BottomBar(top: .status("Time for bed" + first, .accent), buttons: [.stopReminders, .notReadyForBed])
        }
        if w.status == .windingDown, let bed = w.goToBed {
            return BottomBar(top: .status("Winding down · bed \(format(bed))", .accent), buttons: [.cancelWindDown, .sleepLater])
        }
        if w.canStartNow(hours: i.startWindDownHours, now: i.now), let wind = w.windDown, let bed = w.goToBed {
            return BottomBar(top: .status("Wind-down \(format(wind)) · bed \(format(bed))", .accent), buttons: [.startWindDown, .sleepLater])
        }
        return nil
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
        // v0.4.8 item 3: in the up-early window that window's bar wins over a re-plan prompt.
        if let changed = i.plansChanged, !i.upEarlyWindow {
            return BottomBar(top: .main(.replan, changed), buttons: [.previewPlan, .editAlarms])
        }
        // v0.4.8 item 5: alarms set, bedtime still to come: Good night, Change plan, Temporary
        // (wind-down's actions stay in ⋯).
        if i.goodNight, i.alarmsSet > 0, !i.upEarlyWindow, !i.backToBedWindow, !i.notReadyWindow {
            let count = i.alarmsSet == 1 ? "1 alarm set" : "\(i.alarmsSet) alarms set"
            let first = i.firstAlarm.flatMap { $0 > i.now ? " · first \(format($0))" : nil } ?? ""
            return BottomBar(top: .status("✓ " + count + first, .good),
                             buttons: [.changePlan] + (i.alarmStyleApp ? [.addTemporary] : []),
                             hold: .goodNight, undoOffered: i.undo != nil)
        }
        if !i.upEarlyWindow, !i.backToBedWindow, let wind = windDownBar(i) { return wind }
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
                // v0.4.8 item 14: after bedtime, what the check found, in one line.
                let top: Top = i.healthIssue.map { .status("⚠ " + $0, .snoozing) } ?? .status("✓ " + count, .good)
                return BottomBar(top: top, buttons: [.notReadyForBed, .sleepLater])
            }
            // v0.4.3 item 3: No alarms tomorrow takes Edit alarms' place (Edit stays in ⋯).
            return BottomBar(top: .status("✓ " + count, .good), buttons: i.sleepLaterWindow ? [.sleepLater, .noAlarmsTomorrow] : [.noAlarmsTomorrow, .editAlarms])
        }
        let nap: [BarAction] = i.napEnabled ? [.nap] : []
        if NoAlarmMorning.barOffers(offered: i.awakeOffered, alarmsSet: i.alarmsSet, napping: false, evening: i.evening) {
            return BottomBar(top: .main(.imAwake, "I'm awake · good morning"), buttons: nap + [.previewPlan])
        }
        // v0.4.7 item 8: nothing set and nothing coming (on opening, or a preview found nothing):
        // the two ways to set something yourself, in the bar.
        if i.nothingFound || (!i.evening && i.tomorrow == nil) {
            return BottomBar(top: .status("Nothing set for tonight", .muted),
                             buttons: (i.alarmStyleApp ? [.addTemporary] : []) + [.previewPlan],
                             actionRow: [.setAlarmsForTime] + nap)
        }
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

    /// Change plan's list (v0.4.8 item 5), in order, hiding what doesn't apply.
    static func changePlanItems(_ i: Inputs) -> [BarAction] {
        var items: [BarAction] = []
        if i.undo != nil { items.append(.undo) }
        if i.alarmsSet > 0 && i.alarmStyleApp { items.append(.editAlarms) }
        items += [.setAlarmsForTime, .replan]
        if i.sleepLaterWindow { items.append(.sleepLater) }
        if i.alarmsSet > 0 || i.tomorrowHasAlarm { items.append(.noAlarmsTomorrow) }
        return items
    }

    /// The ⋯ list: the same list in every state, hiding what doesn't apply.
    static func menu(_ i: Inputs, alarmStyleApp: Bool, morningKnown: Bool) -> [BarAction] {
        var items: [BarAction] = (i.reporting ? [.report] : []) + [.previewPlan]
        if i.alarmsSet > 0 { items.append(.editAlarms) }
        if i.sleepLaterWindow { items.append(.sleepLater) }
        if i.napEnabled && i.napUpAt == nil { items.append(.nap) }
        if i.snoozing || (i.alarmsSet > 0 && i.upEarlyWindow) || i.backToBedWindow { items.append(.changeMorning) }
        // v0.4.8 item 7: up to the first alarm, the 2-hour window included.
        let beforeFirst = i.upEarlyWindow && (i.firstAlarm ?? i.now) > i.now
        let morning = i.snoozing || (i.upEarlyWindow && !beforeFirst) || i.backToBedWindow
        if !morning && (i.alarmsSet > 0 || i.tomorrowHasAlarm) { items.append(.noAlarmsTomorrow) }
        if morningKnown { items.append(.skip) }
        if i.notReadyWindow { items.append(.notGoingToSleep) }
        if let w = i.windDown {
            if w.canStartNow(hours: i.startWindDownHours, now: i.now) { items.append(.startWindDown) }
            if w.status == .scheduled || w.status == .windingDown { items.append(.cancelWindDown) }
            if (w.status == .bedtime || w.status == .windingDown) && !w.bedtimeRan && !w.remindersStopped { items.append(.stopReminders) }
        }
        if i.awakeOffered && i.alarmsSet == 0 && i.napUpAt == nil { items.append(.imAwake) }
        if alarmStyleApp { items.append(.addTemporary) }
        items += [.addWakeUpEvent, .addLeave]
        items.append(.settings)
        return items
    }
}
