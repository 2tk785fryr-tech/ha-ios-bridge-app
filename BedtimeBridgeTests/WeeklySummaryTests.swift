import XCTest
@testable import BedtimeBridge

/// v0.4.6 item 5: this week so far, and the 8 weeks before it.
final class WeeklySummaryTests: XCTestCase {
    private let reply: [[String: Any]] = [
        ["from": "2026-10-25T22:00:00+00:00", "to": "2026-10-30T13:00:00+00:00", "current": true, "mornings": 2, "naps": 1],
        ["from": "2026-10-18T22:00:00+00:00", "to": "2026-10-25T22:00:00+00:00", "current": false, "mornings": 5],
        ["from": "2026-10-04T22:00:00+00:00", "to": "2026-10-11T22:00:00+00:00", "current": false, "mornings": 1],
    ]

    func testWeeksFromTheReply() {
        let weeks = reply.map(WeeklySummary.init)
        XCTAssertEqual(weeks.map(\.current), [true, false, false])
        XCTAssertEqual(weeks.map(\.mornings), [2, 5, 1])
        XCTAssertTrue(weeks[0].rangeText?.hasSuffix("– now") == true)
        XCTAssertFalse(weeks[1].rangeText?.hasSuffix("– now") == true)
    }

    /// Opened from Settings: this week so far. From the weekly notification: the week that just ended.
    func testWhereTheScreenOpens() {
        let weeks = reply.map(WeeklySummary.init)
        XCTAssertEqual(WeeklySummary.startIndex(weeks, justEnded: false), 0)
        XCTAssertEqual(WeeklySummary.startIndex(weeks, justEnded: true), 1)
        XCTAssertEqual(WeeklySummary.startIndex([weeks[0]], justEnded: true), 0)
        XCTAssertEqual(WeeklySummary.startIndex([], justEnded: true), 0)
    }

    func testWeeksAreKept() {
        let before = WeeklySummary.cachedWeeks
        defer { WeeklySummary.cachedWeeks = before }
        WeeklySummary.cachedWeeks = reply.map(WeeklySummary.init)
        XCTAssertEqual(WeeklySummary.cachedWeeks.count, 3)
        XCTAssertTrue(WeeklySummary.cachedWeeks[0].current)
    }
}
