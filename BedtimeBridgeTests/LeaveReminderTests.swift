import XCTest
@testable import BedtimeBridge

/// v0.4.1 item 17: several leave reminders, each with a fresh drive time.
final class LeaveReminderTests: XCTestCase {
    private let leaveBy = Date(timeIntervalSince1970: 1_800_000_000)

    func testDefaultIs15BeforeAndAtLeaveTime() {
        XCTAssertEqual(BridgeSettings().leaveReminderOffsets, [15, 0])
    }

    func testOnlyRemindersStillAheadEarliestFirst() {
        let now = leaveBy.addingTimeInterval(-12 * 60)
        let due = LeaveReminder.dueTimes(leaveBy: leaveBy, offsets: [0, 15, 10, 10], now: now)
        XCTAssertEqual(due.map(\.minutes), [10, 0])
        XCTAssertEqual(due.map(\.due), [leaveBy.addingTimeInterval(-600), leaveBy])
    }

    func testMessageSaysHowMuchWorse() {
        let now = leaveBy.addingTimeInterval(-15 * 60)
        XCTAssertEqual(
            LeaveReminder.message(leaveBy: leaveBy, travelSeconds: 32 * 60, bedtimeSeconds: 27 * 60, now: now),
            "Leave by \(WakePlanner.format(leaveBy)) · 32 min drive (5 min worse than planned)"
        )
        XCTAssertEqual(
            LeaveReminder.message(leaveBy: leaveBy, travelSeconds: 23 * 60, bedtimeSeconds: 27 * 60, now: now),
            "Leave by \(WakePlanner.format(leaveBy)) · 23 min drive (4 min lighter than planned)"
        )
        XCTAssertEqual(
            LeaveReminder.message(leaveBy: leaveBy, travelSeconds: 28 * 60, bedtimeSeconds: 27 * 60, now: now),
            "Leave by \(WakePlanner.format(leaveBy)) · 28 min drive"
        )
    }

    func testAtLeaveTimeItSaysLeaveNow() {
        XCTAssertEqual(
            LeaveReminder.message(leaveBy: leaveBy, travelSeconds: 35 * 60, bedtimeSeconds: 35 * 60, now: leaveBy),
            "Leave now · 35 min drive"
        )
    }

    func testOpeningTheAppRechecksOnTheMorningAtMostEvery10Minutes() {
        let before = leaveBy.addingTimeInterval(-3600)
        XCTAssertTrue(BedtimeCoordinator.shouldRecheckOnOpen(leaveBy: leaveBy, lastCheck: nil, now: before))
        XCTAssertFalse(BedtimeCoordinator.shouldRecheckOnOpen(leaveBy: leaveBy, lastCheck: before.addingTimeInterval(-300), now: before))
        XCTAssertTrue(BedtimeCoordinator.shouldRecheckOnOpen(leaveBy: leaveBy, lastCheck: before.addingTimeInterval(-600), now: before))
        // The night before, and once 15 min past leave-by: no.
        XCTAssertFalse(BedtimeCoordinator.shouldRecheckOnOpen(leaveBy: leaveBy, lastCheck: nil, now: leaveBy.addingTimeInterval(-4 * 3600)))
        XCTAssertFalse(BedtimeCoordinator.shouldRecheckOnOpen(leaveBy: leaveBy, lastCheck: nil, now: leaveBy.addingTimeInterval(16 * 60)))
    }

    // v0.4.2 item 1: with no alarms left, reminders stay while the calendar still shows the shift.
    func testRemindersStayWhileTheShiftIsOnTheCalendar() {
        let start = leaveBy.addingTimeInterval(45 * 60)
        let trip = PendingTrip(title: "Days", location: "Work", start: start, arriveBy: start, plannedTravelSeconds: 1800)
        XCTAssertTrue(BedtimeCoordinator.tripStillOnCalendar(trip, events: [("Days shift", start)]))
        XCTAssertFalse(BedtimeCoordinator.tripStillOnCalendar(trip, events: []))
        XCTAssertFalse(BedtimeCoordinator.tripStillOnCalendar(trip, events: [("Days shift", start.addingTimeInterval(86_400))]))
    }
}
