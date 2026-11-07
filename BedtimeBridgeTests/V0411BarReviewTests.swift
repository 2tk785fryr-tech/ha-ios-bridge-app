import XCTest
@testable import BedtimeBridge

/// v0.4.11 items 35–48: the bar review.
final class V0411BarReviewTests: XCTestCase {
    private func date(_ day: Int, _ hour: Int, _ minute: Int = 0) -> Date {
        Calendar.current.date(from: DateComponents(year: 2026, month: 11, day: day, hour: hour, minute: minute))!
    }

    // MARK: Items 35 and 36

    func testSleepingInStartsAtBedtimePlusGoalMinusAnHour() {
        let ran = date(6, 22, 47)
        func at(_ d: Date, awakeAt: Date? = nil, awakeForDay: Bool = false, stop: Date? = nil) -> Bool {
            OptionWindows.sleepingIn(bedtimeRanAt: ran, lastStop: stop, alarmsSet: false, napping: false, sleepGoalMinutes: 390,
                                     awakeAt: awakeAt, awakeForDay: awakeForDay, now: d)
        }
        XCTAssertFalse(at(date(7, 4, 16)))
        XCTAssertTrue(at(date(7, 4, 17)))
        XCTAssertTrue(at(date(7, 9, 30)), "past Good morning from, until I'm awake")
        XCTAssertFalse(at(date(7, 9, 30), awakeAt: date(7, 9)), "I'm awake ran")
        XCTAssertFalse(at(date(7, 9, 30), awakeForDay: true), "Awake For Day in Home Assistant")
        XCTAssertFalse(at(date(7, 9, 30), stop: date(7, 6)))
        XCTAssertFalse(at(date(7, 17)), "18 hours after bedtime")
    }

    func testSleepingInNotBeforeFour() {
        XCTAssertEqual(OptionWindows.awakeFrom(ran: date(6, 20), sleepGoalMinutes: 390), date(7, 4))
        XCTAssertEqual(OptionWindows.awakeFrom(ran: date(7, 1), sleepGoalMinutes: 390), date(7, 6, 30), "a bedtime after midnight")
    }

    func testSleepingInBarIsThePurpleSlider() {
        var i = BottomBar.Inputs(now: date(7, 4, 17))
        i.evening = true
        i.inBedNoAlarms = true
        i.sleepingIn = true
        i.sleepingInDay = "Saturday"
        let bar = BottomBar.make(i)
        XCTAssertEqual(bar.top, .status("Sleeping in · no alarms Saturday", .accent))
        XCTAssertEqual(bar.hold, .imAwake)
        XCTAssertEqual(bar.actionRow, [.setAlarmsForTime])
        XCTAssertEqual(bar.buttons, [.addTemporary, .previewPlan])
        i.alarmsSet = 2
        i.firstAlarm = date(7, 8)
        XCTAssertNotEqual(BottomBar.make(i).hold, .imAwake, "alarms set: as now")
    }

    // MARK: Items 37–40

    func testItem37OneNameForUndoingBedtime() {
        var i = BottomBar.Inputs(now: date(6, 23))
        i.alarmsSet = 3
        i.firstAlarm = date(7, 4, 38)
        i.notReadyWindow = true
        i.plansChanged = "Calendar changed · re-plan"
        XCTAssertEqual(BottomBar.make(i).hold, .notReadyForBed)
        let menu = BottomBar.menu(i, alarmStyleApp: true, morningKnown: true)
        XCTAssertFalse(menu.contains(.notGoingToSleep))
        XCTAssertFalse(menu.contains(.notReadyForBed), "item 45: it's the bar's slider")
    }

    func testItem38MiddleOfTheNight() {
        var i = BottomBar.Inputs(now: date(7, 1))
        i.alarmsSet = 3
        i.firstAlarm = date(7, 4, 38)
        i.sleepLaterWindow = true
        XCTAssertEqual(BottomBar.make(i).buttons, [.sleepLater, .addTemporary])
        XCTAssertTrue(BottomBar.menu(i, alarmStyleApp: true, morningKnown: true).contains(.noAlarmsTomorrow), "No alarms is in ⋯")
    }

    func testItem39AlarmsSetAfterANoAlarmBedtimeKeepGoodNight() {
        var i = BottomBar.Inputs(now: date(6, 23, 30))
        i.alarmsSet = 3
        i.firstAlarm = date(7, 8)
        i.goodNight = true
        XCTAssertEqual(BottomBar.make(i).hold, .goodNight)
    }

    func testItem40NoNapFromBedtimeUntilTheAlarmsEnd() {
        var i = BottomBar.Inputs(now: date(6, 23))
        i.napEnabled = true
        i.alarmsSet = 3
        i.firstAlarm = date(7, 4, 38)
        XCTAssertFalse(BottomBar.menu(i, alarmStyleApp: true, morningKnown: true).contains(.nap), "after bedtime")
        i.goodNight = true
        XCTAssertTrue(BottomBar.menu(i, alarmStyleApp: true, morningKnown: true).contains(.nap), "before bedtime")
        var morning = BottomBar.Inputs(now: date(7, 4, 50))
        morning.napEnabled = true
        morning.snoozing = true
        XCTAssertFalse(BottomBar.menu(morning, alarmStyleApp: true, morningKnown: true).contains(.nap))
        morning.snoozing = false
        morning.backToBedWindow = true
        XCTAssertTrue(BottomBar.menu(morning, alarmStyleApp: true, morningKnown: true).contains(.nap), "alarms over")
    }

    // MARK: Items 41 and 42

    func testItem42WindDownButtons() {
        let w = WindDownState(status: .windingDown, windDown: date(6, 21), goToBed: date(6, 22), firstAlarm: date(7, 4, 30))
        var i = BottomBar.Inputs(now: date(6, 21, 30))
        i.windDown = w
        XCTAssertEqual(BottomBar.make(i).buttons, [.goToBedLater, .setAlarms], "no alarms: Go to bed later and Set alarms")
        i.alarmsSet = 3
        XCTAssertEqual(BottomBar.make(i).buttons, [.cancelWindDown, .goToBedLater])
        XCTAssertFalse(BarAction.goToBedLater.isProtected, "a plain choice of minutes")
        XCTAssertEqual(BarAction.goToBedLater.title(day: ""), "Go to bed later…")
    }

    // MARK: Item 43

    func testItem43Wording() {
        var i = BottomBar.Inputs(now: date(7, 10))
        i.day = "Saturday"
        XCTAssertEqual(BottomBar.make(i).top, .status("Nothing set for Saturday", .muted))
        i.evening = true
        i.tomorrow = nil
        i.nothingFound = false
        var evening = BottomBar.Inputs(now: date(6, 19))
        evening.evening = true
        evening.day = "Saturday"
        evening.tomorrow = date(7, 6)
        XCTAssertEqual(BottomBar.make(evening).top, .status("No alarms · Saturday", .muted))

        var set = BottomBar.Inputs(now: date(7, 1))
        set.alarmsSet = 3
        set.firstAlarm = date(7, 4, 38)
        set.sleepLaterWindow = true
        XCTAssertEqual(BottomBar.make(set).top, .status("✓ 3 alarms · first \(WakePlanner.format(date(7, 4, 38)))", .good))

        var changed = BottomBar.Inputs(now: date(7, 10))
        changed.plansChanged = "Calendar changed · re-plan"
        XCTAssertEqual(BottomBar.make(changed).buttons, [.previewPlan, .setAlarmsForTime], "no alarms: nothing to edit")
    }

    // MARK: Item 44

    func testItem44NewStatusLines() {
        var i = BottomBar.Inputs(now: date(7, 10))
        i.day = "Saturday"
        i.vacationBack = "Monday"
        XCTAssertEqual(BottomBar.make(i).top, .status("On vacation · back Monday", .accent))
        i.vacationBack = nil
        i.away = true
        XCTAssertEqual(BottomBar.make(i).top, .status("Away from home", .muted))
        i.calendarOff = true
        XCTAssertEqual(BottomBar.make(i).top, .status("⚠ Calendar access off · Settings → Calendars", .snoozing))

        var bed = BottomBar.Inputs(now: date(6, 23))
        bed.inBedNoAlarms = true
        bed.inBedDay = "Saturday"
        bed.healthIssue = "Home Assistant not reachable"
        XCTAssertEqual(BottomBar.make(bed).top, .status("⚠ Home Assistant not reachable", .snoozing), "also on a no-alarm night")

        var set = BottomBar.Inputs(now: date(6, 23))
        set.alarmsSet = 3
        set.firstAlarm = date(7, 4, 38)
        set.vacationBack = "Monday"
        XCTAssertNotEqual(BottomBar.make(set).top, .status("On vacation · back Monday", .accent), "alarms keep their own line")
    }
}

/// v0.4.11 items 46–48: merged actions.
final class V0411MergedActionsTests: XCTestCase {
    func testItem46OneNameToEndTheMorning() {
        XCTAssertEqual(BarAction.upEarly.title(day: ""), "End this morning's alarms")
        XCTAssertEqual(BarAction.endAlarms.title(day: ""), "End this morning's alarms")
    }

    func testItem47WakeUpLaterThenBackToBed() {
        XCTAssertEqual(BarAction.sleepLater.title(day: ""), "Wake up later…")
        XCTAssertEqual(BarAction.wakeLater.title(day: ""), "Wake up later…")
        XCTAssertEqual(BarAction.backToBed.title(day: ""), "Back to bed", "once you're up")
    }
}
