import XCTest
@testable import BedtimeBridge

/// v0.4.3 item 5: wind-down times, the bar's states 9–11 and Home Assistant's reply.
final class WindDownTests: XCTestCase {
    private let first = Date(timeIntervalSince1970: 1_800_000_000)  // tomorrow's 4:20-ish
    private func at(_ minutes: Double) -> Date { first.addingTimeInterval(minutes * 60) }
    private func f(_ d: Date) -> String { WakePlanner.format(d) }

    func testTimesFromTheFirstAlarm() {
        let times = WindDownTimes.compute(firstAlarm: first, sleepGoal: 390, length: 60, free: 30, minimum: 30)
        XCTAssertEqual(times.goToBed, at(-390), "go to bed = first alarm − 6.5 h")
        XCTAssertEqual(times.windDown, at(-450), "wind-down = go to bed − 60 min")
    }

    func testHomeLateMovesBedtimeLaterRatherThanCuttingWindDown() {
        let home = at(-420)  // 30 min before go to bed
        let times = WindDownTimes.compute(firstAlarm: first, sleepGoal: 390, length: 60, free: 30, minimum: 30, homeAt: home)
        XCTAssertEqual(times.windDown, at(-390), "home + 30 min free")
        XCTAssertEqual(times.goToBed, at(-360), "at least 30 min of wind-down: bedtime later")
    }

    private func state(_ status: WindDownState.Status) -> WindDownState {
        WindDownState(status: status, windDown: at(-450), goToBed: at(-390), firstAlarm: first)
    }

    func testBarState9BeforeWindDown() {
        var i = BottomBar.Inputs(now: at(-500))
        i.windDown = state(.scheduled)
        i.alarmsSet = 3
        XCTAssertEqual(BottomBar.make(i), BottomBar(top: .status("Wind-down \(f(at(-450))) · bed \(f(at(-390)))", .accent), buttons: [.startWindDown, .sleepLater]))
        i.now = at(-600)
        XCTAssertNotEqual(BottomBar.make(i).buttons.first, .startWindDown, "only within 2 h of go to bed")
    }

    func testBarState10WindingDown() {
        var i = BottomBar.Inputs(now: at(-420))
        i.windDown = state(.windingDown)
        XCTAssertEqual(BottomBar.make(i), BottomBar(top: .status("Winding down · bed \(f(at(-390)))", .accent), buttons: [.cancelWindDown, .sleepLater]))
        XCTAssertTrue(BottomBar.menu(i, alarmStyleApp: true, morningKnown: true).contains(.cancelWindDown))
        XCTAssertFalse(BarAction.cancelWindDown.isProtected, "a plain confirm, not the slider")
    }

    func testBarState11AfterGoToBedNotInBed() {
        var i = BottomBar.Inputs(now: at(-380))
        i.windDown = state(.bedtime)
        XCTAssertEqual(BottomBar.make(i), BottomBar(top: .status("Time for bed · first alarm \(f(first))", .accent), buttons: [.stopReminders, .notReadyForBed]))
        i.windDown?.inBed = true
        XCTAssertNotEqual(BottomBar.make(i).buttons.first, .stopReminders, "in bed: nothing to stop")
    }

    func testReplyFromHomeAssistant() {
        let reply: [String: Any] = ["status": "winding_down", "wind_down": "2026-10-27T20:50:00-04:00", "go_to_bed": "2026-10-27T21:50:00-04:00",
                                    "first_alarm": "2026-10-28T04:20:00-04:00", "appointments_checked": false, "in_bed": false]
        let parsed = WindDownState(reply)
        XCTAssertEqual(parsed.status, .windingDown)
        XCTAssertEqual(parsed.goToBed?.timeIntervalSince(parsed.windDown!), 3600)
        XCTAssertFalse(parsed.appointmentsChecked)
    }

    func testMovedFromUsualForTheEveningNote() {
        let settings = BridgeSettings()
        var shift = ShiftCandidate(title: "Days", start: at(130), wakeMinutesBefore: 130, cause: "Days")
        shift.alarmCount = 1
        var plan = WakePlan(source: .shift, wakeTime: shift.wakeTime, alarmTimes: [shift.wakeTime], reason: "Days shift")
        plan.shift = shift
        XCTAssertNil(BedtimeCoordinator.movedFromUsual(plan, settings: settings), "a normal shift morning gets no note")
        plan.weather = WeatherAdjustment(minutes: 15, reason: "snowy at 5 AM")
        XCTAssertEqual(BedtimeCoordinator.movedFromUsual(plan, settings: settings), "snowy at 5 AM")
    }
}

/// Review fixes (29 Oct).
final class WindDownReviewFixTests: XCTestCase {
    private let bed = Date(timeIntervalSince1970: 1_800_000_000)

    func testControlWorksOutTheWindowWhenAsked() {
        var snapshot = NextAlarmSnapshot()
        snapshot.windDownStatus = "scheduled"
        snapshot.windDownAt = bed.addingTimeInterval(-3600)
        snapshot.goToBedAt = bed
        snapshot.startWindDownHours = 2
        XCTAssertFalse(snapshot.canStartWindDown(at: bed.addingTimeInterval(-3 * 3600)), "before the window: Not yet")
        XCTAssertTrue(snapshot.canStartWindDown(at: bed.addingTimeInterval(-90 * 60)), "inside it: Start")
        XCTAssertFalse(snapshot.canStartWindDown(at: bed.addingTimeInterval(-30 * 60)), "wind-down already due")
    }

    func testSleepLaterIsNotACalendarChange() {
        // Set at 4:20 4:30, then Sleep later moved them; tomorrow's plan is still 4:20 4:30.
        let planned = [bed, bed.addingTimeInterval(600)]
        var same = WakePlan(source: .shift, alarmTimes: planned, reason: "Days shift")
        same.shift = ShiftCandidate(title: "Days", start: bed.addingTimeInterval(7200), wakeMinutesBefore: 110, cause: "Days")
        XCTAssertNil(PlanChange.describe(set: planned, shownFirst: bed.addingTimeInterval(1800), setCause: "Days", setLabel: nil, new: same))
        let gone = WakePlan(source: .none, alarmTimes: [], reason: "")
        XCTAssertEqual(PlanChange.describe(set: planned, shownFirst: bed.addingTimeInterval(1800), setCause: "Days", setLabel: nil, new: gone),
                       "Tomorrow changed: Days shift deleted. Your \(WakePlanner.format(bed.addingTimeInterval(1800))) alarms are still set. Re-plan?",
                       "the message names the alarms set now")
    }
}
