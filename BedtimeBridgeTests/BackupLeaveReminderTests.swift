import XCTest
@testable import BedtimeBridge

/// v0.4.7 item 2: one leave-time reminder on the phone when Home Assistant does the checks.
final class BackupLeaveReminderTests: XCTestCase {
    func testOnlyWhenHomeAssistantChecksAndYoureHome() {
        let settings = BridgeSettings()
        XCTAssertTrue(BedtimeCoordinator.needsBackupReminder(settings, atHome: true, checksHere: true))
        XCTAssertFalse(BedtimeCoordinator.needsBackupReminder(settings, atHome: false, checksHere: true), "away: the phone's own reminders run")
        XCTAssertFalse(BedtimeCoordinator.needsBackupReminder(settings, atHome: true, checksHere: false), "the phone checks: its reminders run")
        var off = settings
        off.leaveReminderEnabled = false
        XCTAssertFalse(BedtimeCoordinator.needsBackupReminder(off, atHome: true, checksHere: true))
    }

    func testSaysItWasntReChecked() {
        let leave = Date(timeIntervalSince1970: 1_800_000_000)
        let trip = PendingTrip(title: "Days", location: "1 Main St", start: leave.addingTimeInterval(45 * 60),
                               arriveBy: leave.addingTimeInterval(35 * 60), plannedTravelSeconds: 35 * 60)
        let text = LeaveReminder.backupText(trip)
        XCTAssertEqual(text.title, "Leave by \(WakePlanner.format(leave)) · not re-checked")
        XCTAssertTrue(text.body.hasPrefix("Home Assistant didn't answer"))
        XCTAssertTrue(text.body.contains("35 min"))
        XCTAssertEqual(LeaveReminder.checkedSignal, "leave_checked")
    }
}
