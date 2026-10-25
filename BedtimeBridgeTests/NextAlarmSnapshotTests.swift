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
}
