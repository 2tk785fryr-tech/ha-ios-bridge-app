import XCTest
@testable import BedtimeBridge

final class BackstopInfoTests: XCTestCase {
    private let leaveBy = Date(timeIntervalSince1970: 1_800_000_000)
    private let offsets = (early: 50, deadline: 35, late: 20, firstDayBack: 15)
    private func before(_ minutes: Double) -> Date { leaveBy.addingTimeInterval(-minutes * 60) }

    func testArmedLadder() {
        let context = MorningContext(ladderArmed: true, ladderStatus: "armed", ladderKind: "shift",
                                     backstops: ["early": before(50), "deadline": before(35), "late": before(20)],
                                     houseSource: "bridge")
        let info = BackstopInfo.make(context: context, leaveBy: leaveBy, offsets: offsets, firstDayBack: false)
        XCTAssertEqual(info?.status, "Backstops armed")
        XCTAssertEqual(info?.rungs.map(\.time), [before(50), before(35), before(20)])
        XCTAssertEqual(info?.houseOldTimes, false)
    }

    func testUntilTheCutoverTheOldTimesAreShown() {
        let context = MorningContext(ladderArmed: true, ladderStatus: "armed", ladderKind: "shift",
                                     backstops: ["early": before(50)], houseSource: "old",
                                     houseTimes: ["early": before(48), "deadline": before(33), "late": before(18)])
        let info = BackstopInfo.make(context: context, leaveBy: leaveBy, offsets: offsets, firstDayBack: false)
        XCTAssertEqual(info?.houseOldTimes, true)
        XCTAssertEqual(info?.rungs.first?.time, before(48), "what actually fires")
    }

    func testEstimateWithoutHomeAssistant() {
        let info = BackstopInfo.make(context: nil, leaveBy: leaveBy, offsets: offsets, firstDayBack: true)
        XCTAssertEqual(info?.estimate, true)
        XCTAssertEqual(info?.rungs.map(\.time), [before(65), before(50), before(35)], "first day back: 15 min earlier")
        XCTAssertEqual(info?.firstDayBackMinutes, 15)
    }

    func testIdleAndFault() {
        let idle = MorningContext(ladderArmed: false, ladderStatus: "idle_override_off", ladderReason: "Shift override is Off",
                                  ladderKind: nil, backstops: [:], houseSource: "bridge")
        XCTAssertEqual(BackstopInfo.make(context: idle, leaveBy: nil, offsets: offsets, firstDayBack: false)?.status,
                       "Backstops off: Shift override is Off")
        let fault = MorningContext(ladderArmed: false, ladderStatus: "fault", ladderReason: "Shift sensor unavailable",
                                   ladderKind: nil, backstops: [:], houseSource: "bridge")
        let info = BackstopInfo.make(context: fault, leaveBy: nil, offsets: offsets, firstDayBack: false)
        XCTAssertEqual(info?.status, "Backstop fault: Shift sensor unavailable")
        XCTAssertEqual(info?.isFault, true)
    }
}
