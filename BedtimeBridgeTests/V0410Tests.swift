import XCTest
@testable import BedtimeBridge

/// v0.4.10, by spec item.
final class V0410Tests: XCTestCase {
    private let newYork: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/New_York")!
        return calendar
    }()

    private func at(_ hour: Int, _ minute: Int, _ second: Int = 0, day: Int = 1) -> Date {
        newYork.date(from: DateComponents(year: 2026, month: 11, day: day, hour: hour, minute: minute, second: second))!
    }

    // MARK: Item 1, Stop on the banner and the alarm next to it

    func testItem1TheBannerStopFoldsIntoTheNextAlarmInsteadOfAddingOne() {
        // 1 Nov 08:09:12: the snoozed 8:00 is stopped on the banner; a 9-min snooze would ring
        // at 08:18:12, and the 8:10 rings first.
        let eightTen = StopDescription.Upcoming(id: UUID(), set: at(8, 10), rings: at(8, 10))
        let eightTwenty = StopDescription.Upcoming(id: UUID(), set: at(8, 20), rings: at(8, 20))
        XCTAssertEqual(StopDescription.foldsInto(snoozeAt: at(8, 18, 12), upcoming: [eightTwenty, eightTen]), eightTen,
                       "no 4th alarm at 08:18")
    }

    func testItem1WithNothingSoonerTheSnoozeAlarmIsStillSet() {
        let eightTwenty = StopDescription.Upcoming(id: UUID(), set: at(8, 20), rings: at(8, 20))
        XCTAssertNil(StopDescription.foldsInto(snoozeAt: at(8, 18, 12), upcoming: [eightTwenty]))
        XCTAssertNil(StopDescription.foldsInto(snoozeAt: at(8, 18), upcoming: []), "the last alarm")
    }

    func testItem1ASnoozingAlarmCountsAtItsSnoozeEnd() {
        // The 8:10 snoozed to 8:19 rings after an 8:18 snooze: no fold.
        let snoozed = StopDescription.Upcoming(id: UUID(), set: at(8, 10), rings: at(8, 19, 17))
        XCTAssertNil(StopDescription.foldsInto(snoozeAt: at(8, 18, 12), upcoming: [snoozed]))
    }

    func testItem1TheStopScreenNamesTheAlarmBySetTimeAndListsWhatsLeft() {
        let series = [at(8, 0), at(8, 10), at(8, 20)]
        let left = [StopDescription.Upcoming(id: UUID(), set: at(8, 20), rings: at(8, 20)),
                    StopDescription.Upcoming(id: UUID(), set: at(8, 10), rings: at(8, 19, 17))]
        let stop = StopDescription.make(kind: .series, alarmTime: at(8, 0), series: series, remaining: [at(8, 10), at(8, 20)],
                                        snoozes: 2, left: left)
        XCTAssertEqual(stop.title, "The \(WakePlanner.format(at(8, 0))) alarm · alarm 1 of 3 · 2nd snooze")
        XCTAssertEqual(stop.left, ["\(WakePlanner.format(at(8, 10))) → rings \(WakePlanner.format(at(8, 19, 17)))",
                                   WakePlanner.format(at(8, 20))])
        XCTAssertTrue(stop.canEndAll)
    }

    func testItem1FoldedSaysWhichAlarmIsNext() {
        let next = StopDescription.Upcoming(id: UUID(), set: at(8, 10), rings: at(8, 10))
        let stop = StopDescription.make(kind: .series, alarmTime: at(8, 0), series: [at(8, 0), at(8, 10), at(8, 20)], remaining: [at(8, 10), at(8, 20)],
                                        snoozes: 1, left: [next], foldedInto: next, now: at(8, 9, 12))
        XCTAssertEqual(stop.detail, "Next: the \(WakePlanner.format(at(8, 10))) alarm, in 1 min")
    }

    func testItem1Ordinals() {
        XCTAssertEqual([1, 2, 3, 4, 11, 12, 13, 21, 22].map(StopDescription.ordinal),
                       ["1st", "2nd", "3rd", "4th", "11th", "12th", "13th", "21st", "22nd"])
    }

    func testItem1NoSnoozeKeepsTheShortTitle() {
        let series = [at(8, 0), at(8, 10), at(8, 20)]
        let stop = StopDescription.make(kind: .series, alarmTime: series[1], series: series, remaining: [series[2]])
        XCTAssertEqual(stop.title, "\(WakePlanner.format(series[1])) · alarm 2 of 3")
    }

    // MARK: Items 2 and 3, only the Stop screen ends a ring

    func testItem3TheStopBehaviorSettingIsGone() throws {
        // An old saved value still decodes, and nothing reads it.
        var json = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(BridgeSettings())) as? [String: Any])
        json["stopBehavior"] = "cancelRest"
        let data = try JSONSerialization.data(withJSONObject: json)
        XCTAssertNoThrow(try JSONDecoder().decode(BridgeSettings.self, from: data))
        XCTAssertFalse(SettingsPages.alarms.contains("stopBehavior"))
    }
}
