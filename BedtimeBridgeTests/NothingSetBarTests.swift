import XCTest
@testable import BedtimeBridge

/// v0.4.7 item 8: with nothing set, the bar holds Set alarms for a time, Nap, Temporary alarm and
/// Preview plan.
final class NothingSetBarTests: XCTestCase {
    private func at(_ hour: Int) -> Date { Calendar.current.date(bySettingHour: hour, minute: 0, second: 0, of: Date())! }

    func testOnOpeningInTheDaytime() {
        var i = BottomBar.Inputs(now: at(13))
        i.napEnabled = true
        let bar = BottomBar.make(i)
        XCTAssertEqual(bar.top, .status("Nothing set for tonight", .muted))
        XCTAssertEqual(bar.actionRow, [.setAlarmsForTime, .nap])
        XCTAssertEqual(bar.buttons, [.addTemporary, .previewPlan])
        XCTAssertFalse(BarAction.setAlarmsForTime.isProtected)
    }

    func testNapOffAndClockAlarms() {
        var i = BottomBar.Inputs(now: at(13))
        i.alarmStyleApp = false
        let bar = BottomBar.make(i)
        XCTAssertEqual(bar.actionRow, [.setAlarmsForTime])
        XCTAssertEqual(bar.buttons, [.previewPlan])
    }

    func testAPreviewThatFoundNothingInTheEvening() {
        var i = BottomBar.Inputs(now: at(21))
        i.evening = true
        XCTAssertEqual(BottomBar.make(i).top, .main(.setAlarms, "Plan and set alarms"), "before a preview, the evening still offers to plan")
        i.nothingFound = true
        XCTAssertEqual(BottomBar.make(i).actionRow, [.setAlarmsForTime])
    }

    func testOtherStatesKeepOneRow() {
        var i = BottomBar.Inputs(now: at(13))
        i.tomorrow = at(23)
        XCTAssertTrue(BottomBar.make(i).actionRow.isEmpty, "a plan for tomorrow: the usual bar")
        i.alarmsSet = 3
        i.firstAlarm = at(23)
        XCTAssertTrue(BottomBar.make(i).actionRow.isEmpty)
    }
}
