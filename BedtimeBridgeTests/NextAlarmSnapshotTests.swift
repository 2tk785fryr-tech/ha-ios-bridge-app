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
}
