import XCTest
@testable import BedtimeBridge

/// v0.4.3 items 1–4: preview before a manual set, Undo, No alarms tomorrow, calendar changes.
final class ManualSetTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)
    private func at(_ minutes: Double) -> Date { now.addingTimeInterval(minutes * 60) }
    private func f(_ d: Date) -> String { WakePlanner.format(d) }

    // MARK: Item 1

    func testItem1ManualSetIsAPlainButtonThatPreviewsFirst() {
        XCTAssertFalse(BarAction.setAlarms.isProtected, "it only adds alarms: no slide-and-hold")
        XCTAssertFalse(BarAction.replan.isProtected)
        let plan = WakePlan(source: .shift, alarmTimes: [at(400)], reason: "Days shift")
        let preview = PlanPreview(plan: plan, settings: BridgeSettings(), replan: false)
        XCTAssertEqual(preview.plan, plan, "the preview sets exactly the plan it shows")
    }

    // MARK: Item 2

    private func record(kind: UndoRecord.Kind = .set, previous: [Date], left: [Date], saved: Date? = nil) -> UndoRecord {
        UndoRecord(kind: kind, previousTimes: previous, previousWake: previous.last, previousSource: previous.isEmpty ? .none : .shift,
                   previousReason: "Days shift", previousCause: "Days", previousCleared: nil, leftTimes: left, savedAt: saved ?? now)
    }

    func testItem2UndoUntilBedtimeOrAnotherChange() {
        let set = [at(400), at(410), at(420)]
        let undo = record(previous: [], left: set)
        XCTAssertTrue(undo.available(currentTimes: set, bedtimeRanAt: nil, now: at(1)))
        XCTAssertTrue(undo.available(currentTimes: set, bedtimeRanAt: at(-60), now: at(1)), "bedtime before the set doesn't count")
        XCTAssertFalse(undo.available(currentTimes: set, bedtimeRanAt: at(30), now: at(31)), "gone once bedtime runs")
        XCTAssertFalse(undo.available(currentTimes: [at(430)], bedtimeRanAt: nil, now: at(1)), "gone once the alarms change another way")
        XCTAssertEqual(undo.status(alarmsSet: 3), "3 alarms set · Undo")
        XCTAssertNil(undo.previousPlan, "nothing was set before: Undo clears")
    }

    func testItem2UndoRestoresThePreviousAlarms() {
        let before = [at(380), at(390)]
        let undo = record(previous: before, left: [at(400)])
        XCTAssertEqual(undo.previousPlan?.alarmTimes, before)
        XCTAssertEqual(undo.previousPlan?.cause, "Days", "Home Assistant gets the same cause back")
        XCTAssertFalse(undo.available(currentTimes: [at(400)], bedtimeRanAt: nil, now: at(395)), "the old alarms have all rung")
        XCTAssertTrue(BarAction.undo.isProtected)
    }

    func testItem2BarShowsUndo() {
        var i = BottomBar.Inputs(now: now)
        i.alarmsSet = 3
        i.firstAlarm = at(400)
        i.undo = "3 alarms set · Undo"
        XCTAssertEqual(BottomBar.make(i).top, .undo("3 alarms set · Undo"))
        i.upEarlyWindow = true
        XCTAssertNotEqual(BottomBar.make(i).top, .undo("3 alarms set · Undo"), "the morning's own states win")
    }

    // MARK: Item 3

    func testItem3NoAlarmsTomorrow() {
        XCTAssertTrue(BarAction.noAlarmsTomorrow.isProtected)
        XCTAssertTrue(BarAction.noAlarmsTomorrow.opensScreen, "the confirm has the Sleep In switch, then the slider")
        var i = BottomBar.Inputs(now: now)
        i.alarmsSet = 3
        i.firstAlarm = at(400)
        XCTAssertEqual(BottomBar.make(i).buttons, [.noAlarmsTomorrow, .editAlarms])
        XCTAssertTrue(BottomBar.menu(i, alarmStyleApp: true, morningKnown: true).contains(.noAlarmsTomorrow))
        i.snoozing = true
        XCTAssertFalse(BottomBar.menu(i, alarmStyleApp: true, morningKnown: true).contains(.noAlarmsTomorrow), "not during the morning")

        let start = at(500)
        XCTAssertEqual(NoAlarmsSheet.backstopNote(shift: ("Days", start)),
                       "As if Days at \(f(start)) weren't there: the wake failsafe and backstops are off that morning.")
        XCTAssertEqual(record(kind: .noAlarms, previous: [at(400)], left: []).status(alarmsSet: 0), "No alarms tomorrow · Undo")

        // Bedtime planning afterwards sets nothing for that morning.
        let plan = WakePlan(source: .shift, alarmTimes: [at(400)], reason: "Days shift")
        let cleared = PlanAdjustments.skipping(plan, morning: at(400), noAlarms: true)
        XCTAssertFalse(cleared.hasAlarm)
        XCTAssertTrue(cleared.reason.hasPrefix("No alarms"))
    }

    // MARK: Item 4

    func testItem4DescribesTheChangeAndNeverWhenUnchanged() {
        let set = [at(400), at(410)]
        let gone = WakePlan(source: .none, alarmTimes: [], reason: "No shift")
        XCTAssertEqual(PlanChange.describe(set: set, setCause: "Days", setLabel: "Days", new: gone),
                       "Tomorrow changed: Days shift deleted. Your \(f(at(400))) alarms are still set. Re-plan?")
        var same = WakePlan(source: .shift, wakeTime: set.last, alarmTimes: set, reason: "Days shift")
        same.shift = ShiftCandidate(title: "Days", start: at(480), wakeMinutesBefore: 70, cause: "Days")
        XCTAssertNil(PlanChange.describe(set: set, setCause: "Days", setLabel: nil, new: same))
        let moved = same.waking(at: at(380))
        XCTAssertEqual(PlanChange.describe(set: set, setCause: "Days", setLabel: nil, new: moved),
                       "Tomorrow changed: First alarm would be \(f(at(370))). Your \(f(at(400))) alarms are still set. Re-plan?")
    }
}
