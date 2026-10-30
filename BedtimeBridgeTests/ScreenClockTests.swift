import XCTest
@testable import BedtimeBridge

/// v0.4.6 item 3: Tonight changes on time, not only on the next redraw.
final class ScreenClockTests: XCTestCase {
    private let calendar = Calendar.current

    private func at(_ hour: Int, _ minute: Int, _ second: Int = 0) -> Date {
        calendar.date(bySettingHour: hour, minute: minute, second: second, of: Date())!
    }

    func testNextTickIsTheNextWholeMinute() {
        XCTAssertEqual(ScreenClock.secondsToNextMinute(at(16, 59, 45)), 15, accuracy: 0.01)
        XCTAssertEqual(ScreenClock.secondsToNextMinute(at(16, 59, 0)), 60, accuracy: 0.01)
    }

    func testEveningStartsAtFiveAndEndsAtFour() {
        XCTAssertFalse(ScreenClock.isEvening(at(16, 59, 59)))
        XCTAssertTrue(ScreenClock.isEvening(at(17, 0)))
        XCTAssertTrue(ScreenClock.isEvening(at(3, 59)))
        XCTAssertFalse(ScreenClock.isEvening(at(4, 0)))
    }

    /// Left open across 5:00 PM, the bar switches to the evening one at the tick.
    func testBarSwitchesToEveningAtTheTick() {
        var i = BottomBar.Inputs(now: at(16, 59))
        i.evening = ScreenClock.isEvening(i.now)
        XCTAssertEqual(BottomBar.make(i).top, .status("Nothing set for tonight", .muted))
        i.now = at(17, 0)
        i.evening = ScreenClock.isEvening(i.now)
        XCTAssertEqual(BottomBar.make(i).top, .main(.setAlarms, "Plan and set alarms"))
    }

    /// Wind-down's times and alarm times passing between two ticks make the screen refresh.
    func testMomentsPassingBetweenTicks() {
        let bed = at(22, 0)
        let w = WindDownState(status: .scheduled, windDown: at(21, 0), goToBed: bed, firstAlarm: at(5, 0).addingTimeInterval(86400))
        let moments = ScreenClock.moments(alarms: [at(23, 30)], windDown: w, startWindDownHours: 2)
        XCTAssertTrue(ScreenClock.passed(moments, from: at(19, 59), to: at(20, 0)), "Start wind-down now appears")
        XCTAssertTrue(ScreenClock.passed(moments, from: at(20, 59), to: at(21, 0)), "wind-down")
        XCTAssertTrue(ScreenClock.passed(moments, from: at(21, 59), to: at(22, 0)), "go to bed")
        XCTAssertTrue(ScreenClock.passed(moments, from: at(23, 29), to: at(23, 30)), "an alarm's time")
        XCTAssertFalse(ScreenClock.passed(moments, from: at(20, 0), to: at(20, 1)))
        XCTAssertEqual(ScreenClock.moments(alarms: [], windDown: nil, startWindDownHours: 2), [])
    }

    /// A window closing (here Undo's moment) is a change, so the screen refreshes.
    func testWindowChangeIsSeen() {
        var before = ScreenClock.Windows(undo: true)
        var after = before
        after.undo = false
        XCTAssertNotEqual(before, after)
        before.undo = false
        XCTAssertEqual(before, after)
    }
}

/// v0.4.6 item 1: once the nap's alarms are gone, the Napping card's state is too.
final class NapEndedScreenTests: XCTestCase {
    func testNoNapAlarmsNoNapWindow() {
        let nap = ScreenClock.Windows(napAlarms: [UUID()])
        XCTAssertNotEqual(nap, ScreenClock.Windows(), "ending the nap is a change the screen refreshes for")
    }
}
