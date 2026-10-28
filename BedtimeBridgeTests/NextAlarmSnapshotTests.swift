import XCTest
@testable import BedtimeBridge

final class NextAlarmSnapshotTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    func testNextAlarmSkipsPassedAlarms() {
        let times = [now.addingTimeInterval(-600), now.addingTimeInterval(600), now.addingTimeInterval(1200)]
        let snapshot = NextAlarmSnapshot(alarmTimes: times)
        XCTAssertEqual(snapshot.nextAlarm(after: now), times[1])
        XCTAssertNil(snapshot.nextAlarm(after: now.addingTimeInterval(1800)))
    }

    func testRunningSnoozeComesFirst() {
        var snapshot = NextAlarmSnapshot(alarmTimes: [now.addingTimeInterval(600)])
        snapshot.snoozedUntil = now.addingTimeInterval(300)
        XCTAssertEqual(snapshot.nextAlarm(after: now), now.addingTimeInterval(300))
        XCTAssertEqual(snapshot.changeDates(after: now), [now.addingTimeInterval(300), now.addingTimeInterval(600)])
    }

    func testTemporaryAlarmShowsFirstWithItsOwnLabel() {
        var snapshot = NextAlarmSnapshot(alarmTimes: [now.addingTimeInterval(7200)], label: "Swings shift")
        snapshot.temporaryAlarms = [now.addingTimeInterval(1800)]
        XCTAssertEqual(snapshot.nextAlarm(after: now), now.addingTimeInterval(1800))
        XCTAssertEqual(snapshot.label(after: now), "Temporary wake-up")
        // Once it has passed, the regular series is next again.
        XCTAssertEqual(snapshot.label(after: now.addingTimeInterval(3600)), "Swings shift")
    }

    func testSnapshotsSavedBeforeTemporaryAlarmsStillLoad() throws {
        let old = #"{"alarmTimes":[],"cause":"noalarm","label":"","alarmStyle":"app"}"#
        let snapshot = try JSONDecoder().decode(NextAlarmSnapshot.self, from: Data(old.utf8))
        XCTAssertNil(snapshot.temporaryAlarms)
    }

    func testSetSummaryCountsAlarmsStillToRing() {
        let snapshot = NextAlarmSnapshot(alarmTimes: [now.addingTimeInterval(-60), now.addingTimeInterval(600), now.addingTimeInterval(1200)])
        XCTAssertEqual(snapshot.setSummary(after: now), "2 alarms set")
        XCTAssertEqual(snapshot.setSummary(after: now.addingTimeInterval(900)), "1 alarm set")
        XCTAssertNil(snapshot.setSummary(after: now.addingTimeInterval(1800)))
    }

    func testLeaveByStaysAfterTheLastAlarmUntilThirtyMinutesPast() {
        let leaveBy = now.addingTimeInterval(3600)
        var snapshot = NextAlarmSnapshot(alarmTimes: [now.addingTimeInterval(600)], label: "Days shift", leaveBy: leaveBy)
        XCTAssertNil(snapshot.leaveByAfterAlarms(at: now), "an alarm is still to ring")
        XCTAssertEqual(snapshot.leaveByAfterAlarms(at: now.addingTimeInterval(900)), leaveBy)
        XCTAssertEqual(snapshot.leaveByAfterAlarms(at: leaveBy.addingTimeInterval(29 * 60)), leaveBy)
        XCTAssertNil(snapshot.leaveByAfterAlarms(at: leaveBy.addingTimeInterval(30 * 60)))
        // The widget redraws when it goes away.
        XCTAssertTrue(snapshot.changeDates(after: now).contains(leaveBy.addingTimeInterval(30 * 60)))

        snapshot.leaveByShownMinutes = 10
        XCTAssertNil(snapshot.leaveByAfterAlarms(at: leaveBy.addingTimeInterval(10 * 60)))
    }

    func testNoLeaveByMeansTheNormalDisplay() {
        let snapshot = NextAlarmSnapshot(alarmTimes: [now.addingTimeInterval(-600)], label: "Day off")
        XCTAssertNil(snapshot.leaveByAfterAlarms(at: now))
    }
}
