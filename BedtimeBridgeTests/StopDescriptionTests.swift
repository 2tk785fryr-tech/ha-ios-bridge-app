import XCTest
@testable import BedtimeBridge

final class StopDescriptionTests: XCTestCase {
    private let first = Date(timeIntervalSince1970: 1_800_000_000)
    private var series: [Date] { [0, 300, 600].map { first.addingTimeInterval($0) } }

    func testMiddleAlarmSaysItsPlaceAndWhatIsNext() {
        let stop = StopDescription.make(kind: .series, alarmTime: series[1], series: series, remaining: [series[2]])
        XCTAssertEqual(stop.title, "\(WakePlanner.format(series[1])) · alarm 2 of 3")
        XCTAssertEqual(stop.detail, "Next: \(WakePlanner.format(series[2]))")
        XCTAssertTrue(stop.canEndAll)
    }

    func testLastAlarmSaysSo() {
        let stop = StopDescription.make(kind: .series, alarmTime: series[2], series: series, remaining: [])
        XCTAssertEqual(stop.title, "\(WakePlanner.format(series[2])) · alarm 3 of 3")
        XCTAssertEqual(stop.detail, "Last alarm")
        XCTAssertFalse(stop.canEndAll, "nothing left for the hold to end")
    }

    func testFirstAlarmWithTheRestStillSet() {
        let stop = StopDescription.make(kind: .series, alarmTime: series[0], series: series, remaining: Array(series.dropFirst()))
        XCTAssertEqual(stop.title, "\(WakePlanner.format(series[0])) · alarm 1 of 3")
        XCTAssertEqual(stop.detail, "Next: \(WakePlanner.format(series[1]))")
    }

    func testTemporaryAlarm() {
        let stop = StopDescription.make(kind: .temporary, alarmTime: first, series: series, remaining: series)
        XCTAssertEqual(stop.title, "\(WakePlanner.format(first)) · Temporary alarm")
        XCTAssertEqual(stop.detail, "Your regular alarms are unchanged.")
        XCTAssertFalse(stop.canEndAll, "temporary alarms never end the series")
    }

    func testUnknownSeriesStillShowsTheTime() {
        let stop = StopDescription.make(kind: .series, alarmTime: series[1], series: [], remaining: [])
        XCTAssertEqual(stop.title, WakePlanner.format(series[1]))
        XCTAssertEqual(stop.detail, "Last alarm")
    }
}
