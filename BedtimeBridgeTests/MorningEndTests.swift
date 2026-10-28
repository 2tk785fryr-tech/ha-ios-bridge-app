import XCTest
@testable import BedtimeBridge

final class MorningEndTests: XCTestCase {
    private let first = Date(timeIntervalSince1970: 1_800_000_000)
    private var series: [Date] { [0, 300, 600].map { first.addingTimeInterval($0) } }

    func testHiddenUntilTheWindowBeforeTheFirstAlarm() {
        XCTAssertNil(MorningEnd.make(now: first.addingTimeInterval(-3 * 3600), series: series, remaining: series, snoozedUntil: nil, windowHours: 2))
        let early = MorningEnd.make(now: first.addingTimeInterval(-3600), series: series, remaining: series, snoozedUntil: nil, windowHours: 2)
        XCTAssertEqual(early?.early, true)
        XCTAssertEqual(early?.detail, series.map(WakePlanner.format).joined(separator: ", ") + " still to ring")
    }

    func testSnoozingAndStillToRing() {
        let now = first.addingTimeInterval(400)
        let snoozeEnds = first.addingTimeInterval(840)
        let status = MorningEnd.make(now: now, series: series, remaining: [series[0], series[1], series[2]], snoozedUntil: snoozeEnds, windowHours: 2)
        XCTAssertEqual(status?.early, false)
        XCTAssertEqual(status?.detail, "2 snoozing until \(WakePlanner.format(snoozeEnds)) · \(WakePlanner.format(series[2])) still to ring")
    }

    func testFirstStoppedTheRestToRing() {
        let now = first.addingTimeInterval(60)
        let status = MorningEnd.make(now: now, series: series, remaining: [series[1], series[2]], snoozedUntil: nil, windowHours: 2)
        XCTAssertEqual(status?.early, false, "an alarm already rang")
        XCTAssertEqual(status?.detail, "\(WakePlanner.format(series[1])), \(WakePlanner.format(series[2])) still to ring")
    }

    func testNothingLeftNothingToEnd() {
        XCTAssertNil(MorningEnd.make(now: first.addingTimeInterval(700), series: series, remaining: [], snoozedUntil: nil, windowHours: 2))
    }
}
