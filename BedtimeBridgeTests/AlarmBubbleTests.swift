import XCTest
@testable import BedtimeBridge

/// v0.4.2 item 5: each bubble's ring shows its real state.
final class AlarmBubbleTests: XCTestCase {
    private let first = Date(timeIntervalSince1970: 1_800_000_000)
    private var series: [Date] { [0, 300, 600].map { first.addingTimeInterval($0) } }

    func testAllSetBeforeTheyRing() {
        let bubbles = AlarmBubble.make(morning: series, held: series, wake: series[2], snoozedUntil: nil, stopped: false, now: first.addingTimeInterval(-60))
        XCTAssertEqual(bubbles.map(\.ring), [.set, .set, .set])
        XCTAssertEqual(bubbles.map(\.isWake), [false, false, true])
        XCTAssertEqual(AlarmBubble.header(bubbles, shortfall: nil).text, "3 alarms set")
    }

    func testSnoozingThenOff() {
        let until = first.addingTimeInterval(540)
        let now = first.addingTimeInterval(120)
        let snoozing = AlarmBubble.make(morning: series, held: series, wake: nil, snoozedUntil: until, stopped: false, now: now)
        XCTAssertEqual(snoozing.map(\.ring), [.snoozing(until: until), .set, .set])
        XCTAssertEqual(snoozing[0].label, "snoozing · rings \(WakePlanner.format(until))")

        // Stopped, the rest cancelled: all off, and the header still says 3 set.
        let off = AlarmBubble.make(morning: series, held: [], wake: nil, snoozedUntil: nil, stopped: true, now: now)
        XCTAssertEqual(off.map(\.ring), [.off, .off, .off])
        XCTAssertEqual(off[0].label, "off")
        XCTAssertEqual(AlarmBubble.header(off, shortfall: nil).text, "3 alarms set")
    }

    func testMissingAlarmIsNotSet() {
        let bubbles = AlarmBubble.make(morning: series, held: [series[0], series[2]], wake: nil, snoozedUntil: nil, stopped: false, now: first.addingTimeInterval(-60))
        XCTAssertEqual(bubbles.map(\.ring), [.set, .notSet, .set])
        XCTAssertEqual(bubbles[1].label, "not set")
    }

    func testPreviewHasNoOutline() {
        let bubbles = AlarmBubble.preview(series, wake: series[2])
        XCTAssertEqual(bubbles.map(\.ring), [.none, .none, .none])
        XCTAssertEqual(AlarmBubble.header([], shortfall: nil).text, "Preview · not set")
    }

    func testRingsStayUntilLateBackstopPlusAnHour() {
        let late = first.addingTimeInterval(3600)
        XCTAssertEqual(AlarmBubble.morningOver(lateBackstop: late, lastAlarm: series.max()), late.addingTimeInterval(3600))
        XCTAssertEqual(AlarmBubble.morningOver(lateBackstop: nil, lastAlarm: series.max()), series.max()!.addingTimeInterval(3600))
    }
}
