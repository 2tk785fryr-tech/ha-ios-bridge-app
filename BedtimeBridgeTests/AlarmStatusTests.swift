import XCTest
@testable import BedtimeBridge

final class AlarmStatusTests: XCTestCase {
    private let first = Date(timeIntervalSince1970: 1_800_000_000)
    private var times: [Date] { [0, 300, 600].map { first.addingTimeInterval($0) } }

    func testWhatsSetIsListed() {
        let status = AlarmStatus.make(setTimes: times, shortfall: nil)
        XCTAssertEqual(status.kind, .set)
        XCTAssertEqual(status.text, "3 alarms set · " + times.map(WakePlanner.format).joined(separator: " "))
    }

    func testFewerThanAskedIsAnError() {
        let status = AlarmStatus.make(setTimes: [times[0]], shortfall: (set: 1, planned: 3))
        XCTAssertEqual(status.kind, .error)
        XCTAssertEqual(status.text, "Couldn't set 2 of 3 alarms · set: \(WakePlanner.format(times[0]))")
    }

    func testNothingSet() {
        XCTAssertEqual(AlarmStatus.make(setTimes: [], shortfall: nil).kind, .notSet)
    }
}
