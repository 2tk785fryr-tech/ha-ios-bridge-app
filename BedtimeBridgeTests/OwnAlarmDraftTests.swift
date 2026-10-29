import XCTest
@testable import BedtimeBridge

final class OwnAlarmDraftTests: XCTestCase {
    private var calendar: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "America/New_York")!
        return c
    }
    private func at(_ h: Int, _ m: Int, _ s: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 10, day: 28, hour: h, minute: m, second: s))!
    }

    func testDefaultTimeRoundsUpToTheInterval() {
        XCTAssertEqual(OwnAlarmDraft.defaultTime(now: at(0, 54), roundingMinutes: 15, calendar: calendar), at(7, 0))
        XCTAssertEqual(OwnAlarmDraft.defaultTime(now: at(1, 2), roundingMinutes: 15, calendar: calendar), at(7, 15))
        XCTAssertEqual(OwnAlarmDraft.defaultTime(now: at(1, 0), roundingMinutes: 15, calendar: calendar), at(7, 0), "already on the interval")
        XCTAssertEqual(OwnAlarmDraft.defaultTime(now: at(1, 2, 30), roundingMinutes: 0, calendar: calendar), at(7, 2, 30), "exact")
        // v0.4.2 item 2: 8 h from 10:52 PM = 6:52 → 7:00 with 15-min rounding; default 6 h.
        XCTAssertEqual(BridgeSettings().newAlarmHoursAhead, 6)
        XCTAssertEqual(OwnAlarmDraft.defaultTime(now: at(0, 0).addingTimeInterval(-68 * 60), hoursAhead: 8, roundingMinutes: 15, calendar: calendar), at(7, 0))
    }

    func testDraftMakesTheSeriesAndBackstopsAfterTheLastAlarm() {
        let draft = OwnAlarmDraft.make(wake: at(7, 0), count: 3, spacingMinutes: 10, wakeIs: .first, backstopsOn: true, settings: BridgeSettings())
        XCTAssertEqual(draft.times, [at(7, 0), at(7, 10), at(7, 20)])
        XCTAssertEqual(draft.backstops, ["early": at(7, 35), "deadline": at(7, 50), "late": at(8, 5)])
    }

    func testChangingTheAlarmsUndoesBackstopEdits() {
        var draft = OwnAlarmDraft.make(wake: at(7, 0), count: 2, spacingMinutes: 10, wakeIs: .first, backstopsOn: true, settings: BridgeSettings())
        draft.backstops["early"] = at(7, 45)
        draft.backstopsEdited = true
        XCTAssertNotNil(draft.replacement?.customBackstops)
        let undone = draft.setAlarms(draft.adding(.after, spacingMinutes: 10), settings: BridgeSettings())
        XCTAssertTrue(undone)
        XCTAssertEqual(draft.times, [at(7, 0), at(7, 10), at(7, 20)])
        XCTAssertEqual(draft.backstops["early"], at(7, 35), "from the new last alarm")
        XCTAssertNil(draft.replacement?.customBackstops)
    }

    func testAddingBeforeAndBetween() {
        let draft = OwnAlarmDraft.make(wake: at(7, 0), count: 2, spacingMinutes: 10, wakeIs: .first, backstopsOn: false, settings: BridgeSettings())
        XCTAssertEqual(draft.adding(.before, spacingMinutes: 10), [at(6, 50), at(7, 0), at(7, 10)])
        XCTAssertEqual(draft.adding(.between(0), spacingMinutes: 10), [at(7, 0), at(7, 5), at(7, 10)])
    }
}
