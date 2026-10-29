import XCTest
@testable import BedtimeBridge

/// v0.4.2 item 7: when the situational options show.
final class OptionWindowsTests: XCTestCase {
    private let first = Date(timeIntervalSince1970: 1_800_000_000)
    private var series: [Date] { [0, 300, 600].map { first.addingTimeInterval($0) } }
    private func h(_ hours: Double, from date: Date) -> Date { date.addingTimeInterval(hours * 3600) }

    func testDefaults() {
        let s = BridgeSettings()
        XCTAssertEqual([s.endAlarmsEarlyHours, s.notReadyForBedHours, s.backToBedHours], [2, 2, 3])
    }

    func testUpEarlyFromTwoHoursBefore() {
        XCTAssertFalse(OptionWindows.upEarly(firstAlarm: first, anyLeft: true, hours: 2, now: h(-2.1, from: first)))
        XCTAssertTrue(OptionWindows.upEarly(firstAlarm: first, anyLeft: true, hours: 2, now: h(-1.9, from: first)))
        XCTAssertFalse(OptionWindows.upEarly(firstAlarm: first, anyLeft: false, hours: 2, now: first))
    }

    func testNotReadyForBedForTwoHoursAfterBedtime() {
        let bedtime = h(-6, from: first)
        XCTAssertTrue(OptionWindows.notReadyForBed(bedtimeRanAt: bedtime, alarmsSet: true, hours: 2, now: h(1.5, from: bedtime)))
        XCTAssertFalse(OptionWindows.notReadyForBed(bedtimeRanAt: bedtime, alarmsSet: true, hours: 2, now: h(2.5, from: bedtime)))
        XCTAssertFalse(OptionWindows.notReadyForBed(bedtimeRanAt: nil, alarmsSet: true, hours: 2, now: bedtime))
        XCTAssertFalse(OptionWindows.notReadyForBed(bedtimeRanAt: bedtime, alarmsSet: false, hours: 2, now: bedtime))
    }

    func testBackToBedUntilThreeHoursAfterWakeUpOrLastStop() {
        let last = series.max()!
        XCTAssertTrue(OptionWindows.backToBed(series: series, lastStop: nil, anyLeft: false, upEarlyHours: 2, hours: 3, now: h(2.9, from: last)))
        // The afternoon after an appointment: gone (it was 12 h).
        XCTAssertFalse(OptionWindows.backToBed(series: series, lastStop: nil, anyLeft: false, upEarlyHours: 2, hours: 3, now: h(3.1, from: last)))
        // A later stop extends it.
        let stop = h(1, from: last)
        XCTAssertTrue(OptionWindows.backToBed(series: series, lastStop: stop, anyLeft: false, upEarlyHours: 2, hours: 3, now: h(3.5, from: last)))
        XCTAssertFalse(OptionWindows.backToBed(series: series, lastStop: nil, anyLeft: true, upEarlyHours: 2, hours: 3, now: last))
    }

    func testSleepLaterUntilTheFirstAlarm() {
        XCTAssertTrue(OptionWindows.sleepLater(firstAlarm: first, stopped: false, now: h(-8, from: first)))
        XCTAssertFalse(OptionWindows.sleepLater(firstAlarm: first, stopped: false, now: first))
        XCTAssertFalse(OptionWindows.sleepLater(firstAlarm: first, stopped: true, now: h(-1, from: first)))
    }
}
