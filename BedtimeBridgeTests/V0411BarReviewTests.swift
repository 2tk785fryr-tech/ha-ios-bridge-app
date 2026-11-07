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
}
