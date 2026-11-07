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
    /// v0.4.10 item 9: the snoozing bar's plain slide, which ends only the snoozing alarm (the
    /// hold is End alarms).
    case endThisAlarm
    /// v0.4.11 item 41: tonight's bedtime later (the alarms don't move).
    case goToBedLater

    var id: String { rawValue }

    /// Protected actions are amber and need the slide-and-hold.
    var isProtected: Bool {
        switch self {
        case .notReadyForBed, .notGoingToSleep, .upEarly, .endAlarms, .endThisAlarm, .sleepLater, .endNap, .changeNap,
             .wakeLater, .changeMorning, .backToBed, .skip, .undo, .noAlarmsTomorrow, .imAwake, .goodNight:
            true
        default:
            false
        }
    }

    /// v0.4.10 item 15: drawn in nap orange wherever it shows (the bar, ⋯).
    var napStyled: Bool { [.nap, .endNap, .changeNap].contains(self) }

    /// Opens a screen whose commit step has the slider, instead of the bar's own slider.
    var opensScreen: Bool { [.sleepLater, .changeNap, .editAlarms, .noAlarmsTomorrow, .changePlan].contains(self) }

    enum Knob { case stop, moon, clock }

    /// Red stop (ending), amber moon (back to sleep, up early), purple clock (changing times).
    var knob: Knob {
        switch self {
        case .endAlarms, .endThisAlarm, .endNap, .noAlarmsTomorrow: .stop
        case .notReadyForBed, .notGoingToSleep, .upEarly, .backToBed, .imAwake, .goodNight: .moon
        default: .clock
        }
    }

    /// v0.4.11 item 28: the day the bar's buttons name. The set or planned morning, else
    /// tomorrow, the same morning `noAlarmsMorning` turns off.
    static func dayName(morning: Date?, now: Date = .now) -> String {
        let calendar = Calendar.current
        let day = morning ?? calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: now))!
        return day.formatted(.dateTime.weekday(.wide))
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
        case .sleepLater: "Wake up later…"
        case .editAlarms: "Edit alarms"
        // v0.4.11 item 46: one name to end the morning's alarms, before or after the first.
        case .upEarly: "End this morning's alarms"
        case .endAlarms: "End this morning's alarms"
        // v0.4.11 item 47: one action to move the morning's alarms; Back to bed once you're up.
        case .wakeLater: "Wake up later…"
        case .backToBed: "Back to bed"
        case .endNap: "End nap"
        case .changeNap: "Change nap"
        case .changeMorning: "Change this morning"
        case .skip: "Skip \(day)'s wake-up"
        case .notGoingToSleep: "Not going to sleep yet"
        case .addTemporary: "Add a temporary alarm"
        case .settings: "Settings"
        case .undo: "Undo"
        // v0.4.10 item 10: one "No alarms Sunday" (Skip merged into it).
        case .noAlarmsTomorrow: "No alarms \(day)"
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
        case .endThisAlarm: "End this alarm"
        case .goToBedLater: "Go to bed later…"
        }
    }

    /// What the slider will do, on the caption line above it.
    func caption(day: String) -> String {
        switch self {
        case .notReadyForBed, .notGoingToSleep: "Turn tonight's alarms off and undo bedtime"
        case .upEarly: "End this morning's alarms before they ring"
        case .endAlarms: "End the rest of this morning's alarms"
        case .endNap: "End your nap and turn its alarms off"
        case .wakeLater: "Wake up later: change this morning's alarms"
        case .changeMorning: "Change this morning's alarms"
        case .backToBed: "Back to bed: move this morning's alarms or turn them off"
        case .skip: "Skip \(day)'s wake-up and sleep in"
        case .undo: "Undo: put back the alarms from before"
        case .noAlarmsTomorrow: "Turn \(day)'s alarms off until you undo it"
        case .endThisAlarm: "End this alarm; hold to end all of this morning's alarms"
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

        var isMain: Bool { if case .main = self { true } else { false } }
    }

    var top: Top
    var buttons: [BarAction]
    /// A row of filled buttons between the top and the buttons (v0.4.7 item 8: nothing set).
    var actionRow: [BarAction] = []
    /// A slide-and-hold filling the middle row (v0.4.8 item 5: Good night), with Undo on the
    /// status line while it applies.
    var hold: BarAction? = nil
    var undoOffered = false
    /// v0.4.10 item 9: what a plain slide does when the hold is something more (snoozing: the
    /// slide ends this alarm, the hold ends them all).
    var slide: BarAction? = nil
    /// v0.4.10 item 16: Set alarms' own wording in the action row ("Set 3 alarms · up 4:30").
    var setTitle: String? = nil

    /// v0.4.11 item 7: the hold layout's status line ("Alarms off · leave by 5:43") is centred
    /// like the buttons below it; with Undo beside it, it stays on the left.
    var statusCentered: Bool { !undoOffered }

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
        /// The plan on screen is a preview that found nothing for tomorrow (v0.4.9 item 9).
        var previewedNothing = false
        var alarmStyleApp = true
        /// Alarms set and bedtime not run since (v0.4.8 item 5).
        var goodNight = false
        /// Testing reports are on (v0.4.8 item 9): Report something heads ⋯.
        var reporting = false
        /// The bedtime check found something (v0.4.8 item 14).
        var healthIssue: String?
        /// Tomorrow's shift or appointment, "Days shift 6:30" (v0.4.10 item 16).
        var tomorrowLabel: String?
        /// Past the evening plan check (v0.4.10 item 18): No alarms takes Nap's place.
        var eveningCheckPassed = false
        /// v0.4.11 item 32: bedtime ran tonight with no alarms, until the morning; the morning's day.
        var inBedNoAlarms = false
        var inBedDay = ""
        /// v0.4.11 item 35: the sleeping-in morning after a no-alarm bedtime; its day.
        var sleepingIn = false
        var sleepingInDay = ""
        /// v0.4.11 item 43: the morning the bar names ("Nothing set for Saturday").
        var day = ""
        /// v0.4.11 item 44: a vacation covers tomorrow (the day you're back); Home Assistant says
        /// you're away; calendar access is off.
        var vacationBack: String?
        var away = false
        var calendarOff = false
    }

    /// v0.4.10 item 18: when the evening starts for the bar, the wind-down settings' evening plan
    /// check: `beforeMinutes` before tonight's wind-down, or without one, `fallback` ("18:00").
    static func eveningCheck(windDown: Date?, beforeMinutes: Int, fallback: String, now: Date, calendar: Calendar = .current) -> Date {
        if let windDown { return windDown.addingTimeInterval(-Double(beforeMinutes) * 60) }
        let parts = fallback.split(separator: ":").compactMap { Int($0) }
        return calendar.date(bySettingHour: parts.first ?? 18, minute: parts.count > 1 ? parts[1] : 0, second: 0, of: now) ?? now
    }

    /// Wind-down's states (9 before, 10 during, 11 after go to bed and not in bed).
    private static func windDownBar(_ i: Inputs) -> BottomBar? {
        guard let w = i.windDown else { return nil }
        let format = WakePlanner.format
        let first = w.firstAlarm.map { " · first alarm \(format($0))" } ?? ""
        // v0.4.11 item 42: Go to bed later (bedtime later); with no alarms set, Set alarms beside it.
        let noAlarms: [BarAction] = [.goToBedLater, .setAlarms]
        if w.status == .bedtime, !w.bedtimeRan, !w.inBed, !w.remindersStopped, let bed = w.goToBed, i.now >= bed {
            return BottomBar(top: .status("Time for bed" + first, .accent), buttons: i.alarmsSet > 0 ? [.stopReminders, .goToBedLater] : noAlarms)
        }
        if w.status == .windingDown, let bed = w.goToBed {
            return BottomBar(top: .status("Winding down · bed \(format(bed))", .accent), buttons: i.alarmsSet > 0 ? [.cancelWindDown, .goToBedLater] : noAlarms)
        }
        // v0.4.11 item 21: with no alarms set the evening bar wins (Set alarms / Pick a time);
        // Start and Cancel wind-down are in ⋯.
        guard i.alarmsSet > 0 else { return nil }
        if w.status == .cancelled, w.canStartNow(hours: i.startWindDownHours, now: i.now), let bed = w.goToBed {
            // v0.4.11 item 13: cancelled, it can start again until go to bed.
            return BottomBar(top: .status("Wind-down off tonight · bed \(format(bed))", .muted), buttons: [.startWindDown, .goToBedLater])
        }
        if w.canStartNow(hours: i.startWindDownHours, now: i.now), let wind = w.windDown, let bed = w.goToBed {
            return BottomBar(top: .status("Wind-down \(format(wind)) · bed \(format(bed))", .accent), buttons: [.startWindDown, .goToBedLater])
        }
        return nil
    }

    static func make(_ i: Inputs) -> BottomBar {
        var bar = state(i)
        // v0.4.11 item 44: states the bar didn't have, on the status line of the state underneath
        // (only with nothing set: alarms, a nap and snoozing keep their own line).
        guard i.alarmsSet == 0, i.napUpAt == nil, !i.snoozing, case .status(_, let tone) = bar.top else { return bar }
        if i.calendarOff {
            bar.top = .status("⚠ Calendar access off · Settings → Calendars", .snoozing)
        } else if let issue = i.healthIssue, i.inBedNoAlarms || i.sleepingIn {
            bar.top = .status("⚠ " + issue, .snoozing)
        } else if tone == .muted, let back = i.vacationBack {
            bar.top = .status("On vacation · back \(back)", .accent)
        } else if tone == .muted, i.away {
            bar.top = .status("Away from home", .muted)
        }
        return bar
    }

    private static func state(_ i: Inputs) -> BottomBar {
        let format = WakePlanner.format
        if let up = i.napUpAt {
            return BottomBar(top: .status("Napping · up at \(format(up))", .accent), buttons: [.endNap, .changeNap])
        }
        // v0.4.10 item 9: in the morning's windows, the status on top, that window's slider the
        // whole width, then the buttons.
        let temporary: [BarAction] = i.alarmStyleApp ? [.addTemporary] : []
        if i.snoozing {
            let rings = i.snoozingUntil.map { " · rings \(format($0))" } ?? ""
            return BottomBar(top: .status("Snoozing" + rings, .snoozing), buttons: [.wakeLater] + temporary,
                             hold: .endAlarms, slide: .endThisAlarm)
        }
        // v0.4.8 item 3: in the up-early window that window's bar wins over a re-plan prompt.
        if let changed = i.plansChanged, !i.upEarlyWindow {
            // v0.4.11 item 22: after bedtime, what you need in bed: Not going to sleep yet's
            // slide-and-hold, Change this morning and Temporary (Preview stays in ⋯; Edit is
            // inside Change this morning).
            if i.alarmsSet > 0, !i.goodNight, !i.backToBedWindow {
                return BottomBar(top: .main(.replan, changed), buttons: [.changeMorning] + temporary,
                                 hold: i.notReadyWindow ? .notReadyForBed : nil)
            }
            // v0.4.11 item 43: with no alarms, your own time instead of Edit alarms.
            return BottomBar(top: .main(.replan, changed), buttons: [.previewPlan, i.alarmsSet > 0 ? .editAlarms : .setAlarmsForTime])
        }
        // v0.4.8 item 5: alarms set, bedtime still to come: Good night, Change plan, Temporary
        // (wind-down's actions stay in ⋯).
        if i.goodNight, i.alarmsSet > 0, !i.upEarlyWindow, !i.backToBedWindow, !i.notReadyWindow {
            // v0.4.11 item 43: one pattern, "✓ 3 alarms · first 4:38".
            let count = i.alarmsSet == 1 ? "1 alarm" : "\(i.alarmsSet) alarms"
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
            return BottomBar(top: .status("Alarms off" + leave, .muted), buttons: [.previewPlan] + temporary, hold: .backToBed)
        }
        if i.alarmsSet > 0 {
            // v0.4.11 item 43: "✓ 3 alarms · first 4:38", "✓ 3 alarms · next 4:53".
            var count = "✓ " + (i.alarmsSet == 1 ? "1 alarm" : "\(i.alarmsSet) alarms")
            if i.upEarlyWindow, let first = i.firstAlarm {
                if first > i.now {
                    return BottomBar(top: .status("\(count) · first \(format(first))", .good),
                                     buttons: [.sleepLater] + temporary, hold: .upEarly)
                }
                let next = i.nextAlarm.map { " · next \(format($0))" } ?? ""
                return BottomBar(top: .status(count + next, .good), buttons: [.wakeLater] + temporary, hold: .endAlarms)
            }
            if let first = i.firstAlarm, first > i.now { count += " · first \(format(first))" }
            if i.notReadyWindow {
                // v0.4.8 item 14: after bedtime, what the check found, in one line.
                let top: Top = i.healthIssue.map { .status("⚠ " + $0, .snoozing) } ?? .status(count, .good)
                return BottomBar(top: top, buttons: [.sleepLater] + temporary, hold: .notReadyForBed)
            }
            // v0.4.11 item 38: the middle of the night: Wake up later and Temporary; No alarms is in
            // ⋯, so turning the night's alarms off isn't one half-asleep tap.
            let night: [BarAction] = temporary.isEmpty ? [.noAlarmsTomorrow] : temporary
            return BottomBar(top: .status(count, .good), buttons: i.sleepLaterWindow ? [.sleepLater] + night : [.editAlarms] + night)
        }
        // v0.4.11 items 35 and 36: a no-alarm morning (from bedtime + sleep goal − 1 h, or Home
        // Assistant's offer from 4:00): I'm awake as the purple slide-and-hold, your own time,
        // Temporary and Preview; Nap is in ⋯.
        if i.sleepingIn || NoAlarmMorning.barOffers(offered: i.awakeOffered, alarmsSet: i.alarmsSet, napping: false, evening: i.evening) {
            return BottomBar(top: .status("Sleeping in · no alarms \(i.sleepingInDay)", .accent), buttons: temporary + [.previewPlan],
                             actionRow: [.setAlarmsForTime], hold: .imAwake)
        }
        // v0.4.11 item 32: in bed with no alarms: Not ready for bed to undo it, your own time,
        // Temporary and Preview; Nap is in ⋯.
        if i.inBedNoAlarms {
            if i.notReadyWindow {
                return BottomBar(top: .status("In bed · no alarms \(i.inBedDay)", .accent), buttons: temporary + [.previewPlan],
                                 actionRow: [.setAlarmsForTime], hold: .notReadyForBed)
            }
            return BottomBar(top: .status("In bed · no alarms \(i.inBedDay)", .muted), buttons: temporary + [.previewPlan], actionRow: [.setAlarmsForTime])
        }
        let nap: [BarAction] = i.napEnabled ? [.nap] : []
        // v0.4.7 item 8: nothing set and nothing coming (on opening, or a preview found nothing):
        // the two ways to set something yourself, in the bar.
        if i.nothingFound || (!i.evening && i.tomorrow == nil) {
            // v0.4.9 item 9: after a preview that found nothing, No alarms tomorrow beside it
            // (Temporary alarm stays in ⋯).
            let buttons: [BarAction] = i.previewedNothing ? [.noAlarmsTomorrow, .previewPlan]
                : (i.alarmStyleApp ? [.addTemporary] : []) + [.previewPlan]
            return BottomBar(top: .status(nothingSet(i), .muted), buttons: buttons, actionRow: [.setAlarmsForTime] + nap)
        }
        if i.evening {
            // v0.4.10 items 16 and 17: the status on top, both ways to set alarms in the first row,
            // short enough to share it.
            var title = "Set alarms"
            if let plan = i.planReady, plan.count > 0 {
                title = "Set \(plan.count)" + (plan.up.map { " · up \(format($0))" } ?? "")
            }
            let status = i.tomorrowLabel.map { "\($0) · no alarms set" } ?? (i.day.isEmpty ? "No alarms set" : "No alarms · \(i.day)")
            // v0.4.10 item 18: from the evening plan check, No alarms instead of Nap (Nap in ⋯).
            let somethingTomorrow = i.tomorrowLabel != nil || i.planReady != nil
            let second: [BarAction] = i.eveningCheckPassed && somethingTomorrow ? [.noAlarmsTomorrow] : nap
            return BottomBar(top: .status(status, .muted), buttons: [.previewPlan] + second,
                             actionRow: [.setAlarms, .setAlarmsForTime], setTitle: title)
        }
        let status = i.tomorrow.map { "Tomorrow \(format($0)) · not set yet" } ?? nothingSet(i)
        return BottomBar(top: .status(status, .muted), buttons: nap + [.previewPlan])
    }

    /// v0.4.11 item 43: "Nothing set for Saturday" (the day's name, not "tonight").
    private static func nothingSet(_ i: Inputs) -> String {
        i.day.isEmpty ? "Nothing set for tonight" : "Nothing set for \(i.day)"
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
        // v0.4.10 item 10: from bedtime to the end of the morning, only Change this morning's
        // alarms (Edit single alarms is inside it); before bedtime, Edit alarms.
        let afterBedtime = (i.alarmsSet > 0 && !i.goodNight) || i.snoozing || i.upEarlyWindow || i.backToBedWindow
        if i.alarmsSet > 0 && !afterBedtime { items.append(.editAlarms) }
        if i.sleepLaterWindow { items.append(.sleepLater) }
        // v0.4.11 item 40: no Nap from bedtime until the morning's alarms end.
        let alarmsAhead = (i.alarmsSet > 0 && !i.goodNight) || i.snoozing || i.upEarlyWindow
        if i.napEnabled && i.napUpAt == nil && !alarmsAhead { items.append(.nap) }
        if afterBedtime && (i.snoozing || i.alarmsSet > 0 || i.backToBedWindow) { items.append(.changeMorning) }
        // v0.4.8 item 7: up to the first alarm, the 2-hour window included.
        let beforeFirst = i.upEarlyWindow && (i.firstAlarm ?? i.now) > i.now
        let morning = i.snoozing || (i.upEarlyWindow && !beforeFirst) || i.backToBedWindow
        if !morning && (i.alarmsSet > 0 || i.tomorrowHasAlarm) { items.append(.noAlarmsTomorrow) }
        // v0.4.11 item 21: with no card, Pick a time is in ⋯ whenever nothing is set.
        if i.alarmsSet == 0 && !morning && i.napUpAt == nil { items.append(.setAlarmsForTime) }
        // v0.4.10 item 10: Skip is merged into No alarms.
        // v0.4.11 item 37: one name for undoing bedtime.
        if i.notReadyWindow { items.append(.notReadyForBed) }
        if let w = i.windDown {
            if w.canStartNow(hours: i.startWindDownHours, now: i.now) { items.append(.startWindDown) }
            if w.status == .scheduled || w.status == .windingDown { items.append(.cancelWindDown) }
            if (w.status == .bedtime || w.status == .windingDown) && !w.bedtimeRan && !w.remindersStopped { items.append(.stopReminders) }
        }
        if i.awakeOffered && i.alarmsSet == 0 && i.napUpAt == nil { items.append(.imAwake) }
        if alarmStyleApp { items.append(.addTemporary) }
        items += [.addWakeUpEvent, .addLeave]
        items.append(.settings)
        // v0.4.11 item 45: ⋯ doesn't repeat what the bar shows now (Preview plan and Settings stay).
        let bar = make(i)
        var shown = Set(bar.buttons + bar.actionRow + [bar.hold, bar.slide].compactMap { $0 })
        if case .main(let action, _) = bar.top { shown.insert(action) }
        return items.filter { !shown.contains($0) || $0 == .previewPlan || $0 == .settings }
    }
}
