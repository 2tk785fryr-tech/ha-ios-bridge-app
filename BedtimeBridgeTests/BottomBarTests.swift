import XCTest
@testable import BedtimeBridge

/// v0.4.2 item 6: the bottom bar's states.
final class BottomBarTests: XCTestCase {
    private let first = Date(timeIntervalSince1970: 1_800_000_000)
    private func f(_ d: Date) -> String { WakePlanner.format(d) }

    func testDaytimeNothingSet() {
        var i = BottomBar.Inputs(now: first.addingTimeInterval(-14 * 3600))
        i.tomorrow = first
        i.napEnabled = true
        let bar = BottomBar.make(i)
        XCTAssertEqual(bar.top, .status("Tomorrow \(f(first)) · not set yet", .muted))
        XCTAssertEqual(bar.buttons, [.nap, .previewPlan])
        i.napEnabled = false
        XCTAssertEqual(BottomBar.make(i).buttons, [.previewPlan], "the Nap button only shows when on")
    }

    func testEveningPlanReady() {
        var i = BottomBar.Inputs(now: first.addingTimeInterval(-7 * 3600))
        i.evening = true
        i.napEnabled = true
        i.planReady = (3, first.addingTimeInterval(600))
        let bar = BottomBar.make(i)
        XCTAssertEqual(bar.top, .main(.setAlarms, "Set 3 alarms · up \(f(first.addingTimeInterval(600)))"))
        XCTAssertEqual(bar.buttons, [.previewPlan, .nap])
    }

    func testAlarmsSetBeforeBed() {
        var i = BottomBar.Inputs(now: first.addingTimeInterval(-6 * 3600))
        i.alarmsSet = 3
        i.firstAlarm = first
        i.sleepLaterWindow = true
        i.napEnabled = true
        i.notReadyWindow = true
        XCTAssertEqual(BottomBar.make(i), BottomBar(top: .status("✓ 3 alarms set", .good), buttons: [.notReadyForBed, .sleepLater]))
        i.notReadyWindow = false
        XCTAssertEqual(BottomBar.make(i).buttons, [.sleepLater, .noAlarmsTomorrow], "Nap hidden once the bedtime alarms are set; v0.4.3 item 3 takes Edit alarms' place")
    }

    func testPlansChangedTakesTheTopRow() {
        var i = BottomBar.Inputs(now: first.addingTimeInterval(-6 * 3600))
        i.alarmsSet = 3
        i.plansChanged = "Calendar changed · re-plan"
        XCTAssertEqual(BottomBar.make(i), BottomBar(top: .main(.replan, "Calendar changed · re-plan"), buttons: [.previewPlan, .editAlarms]))
    }

    func testUpEarlySnoozingUpAndNapping() {
        var i = BottomBar.Inputs(now: first.addingTimeInterval(-3600))
        i.alarmsSet = 3
        i.firstAlarm = first
        i.upEarlyWindow = true
        XCTAssertEqual(BottomBar.make(i), BottomBar(top: .status("3 alarms set · first at \(f(first))", .good), buttons: [.upEarly, .sleepLater]))

        var snooze = BottomBar.Inputs(now: first.addingTimeInterval(60))
        snooze.snoozing = true
        snooze.snoozingUntil = first.addingTimeInterval(540)
        XCTAssertEqual(BottomBar.make(snooze), BottomBar(top: .status("Snoozing · rings \(f(first.addingTimeInterval(540)))", .snoozing), buttons: [.endAlarms, .wakeLater]))

        var up = BottomBar.Inputs(now: first.addingTimeInterval(1800))
        up.backToBedWindow = true
        up.leaveBy = first.addingTimeInterval(4800)
        XCTAssertEqual(BottomBar.make(up), BottomBar(top: .status("Alarms off · leave by \(f(first.addingTimeInterval(4800)))", .muted), buttons: [.backToBed, .previewPlan]))

        var nap = BottomBar.Inputs(now: first)
        nap.napUpAt = first.addingTimeInterval(1200)
        nap.alarmsSet = 3
        XCTAssertEqual(BottomBar.make(nap), BottomBar(top: .status("Napping · up at \(f(first.addingTimeInterval(1200)))", .accent), buttons: [.endNap, .changeNap]))
    }

    func testMenuHidesWhatDoesntApplyAndProtectedActions() {
        var i = BottomBar.Inputs(now: first.addingTimeInterval(-6 * 3600))
        XCTAssertEqual(BottomBar.menu(i, alarmStyleApp: true, morningKnown: false), [.previewPlan, .addTemporary, .addWakeUpEvent, .addLeave, .settings])
        i.alarmsSet = 3
        i.sleepLaterWindow = true
        i.notReadyWindow = true
        i.napEnabled = true
        XCTAssertEqual(BottomBar.menu(i, alarmStyleApp: true, morningKnown: true),
                       [.previewPlan, .editAlarms, .sleepLater, .nap, .noAlarmsTomorrow, .skip, .notGoingToSleep, .addTemporary, .addWakeUpEvent, .addLeave, .settings])
        XCTAssertTrue(BarAction.endAlarms.isProtected)
        XCTAssertFalse(BarAction.previewPlan.isProtected)
        XCTAssertEqual(BarAction.endNap.knob, .stop)
        XCTAssertEqual(BarAction.backToBed.knob, .moon)
        XCTAssertEqual(BarAction.skip.knob, .clock)
    }
}

/// Reported 30 Oct: after End nap the bar kept "End nap". The screen now refreshes its own copy
/// of the nap; with no nap alarms left the bar is back to the normal states.
final class NapEndedBarTests: XCTestCase {
    func testNoNapNoNapBar() {
        var i = BottomBar.Inputs()
        i.napUpAt = Date().addingTimeInterval(1200)
        XCTAssertEqual(BottomBar.make(i).buttons, [.endNap, .changeNap])
        i.napUpAt = nil
        XCTAssertFalse(BottomBar.make(i).buttons.contains(.endNap))
        XCTAssertFalse(BottomBar.menu(i, alarmStyleApp: true, morningKnown: false).contains(.endNap))
    }
}
