import XCTest
@testable import BedtimeBridge

/// v0.4.7 item 6: Vacations.
final class VacationTests: XCTestCase {
    private let cal = Calendar.current
    private func day(_ d: Int, _ h: Int = 0, _ m: Int = 0) -> Date {
        cal.date(from: DateComponents(year: 2026, month: 11, day: d, hour: h, minute: m))!
    }

    private var vacation: Vacation { Vacation(id: "v", title: "Leave", first: day(3), last: day(7), travelling: false) }

    func testBackToWorkTheEveningBefore() {
        var settings = BridgeSettings()
        settings.alarmCount = 3
        settings.alarmSpacingMinutes = 5
        settings.wakeTimeIs = .last
        let rule = settings.shiftRules.first { $0.keyword == "Days" }!
        let monday = ShiftCandidate.make(title: "Days", start: day(9, 6, 30), rule: rule).0
        let duringVacation = ShiftCandidate.make(title: "Days", start: day(5, 6, 30), rule: rule).0
        let reminders = Vacations.backToWork(vacations: [vacation], shifts: [duringVacation, monday], settings: settings, now: day(1))
        XCTAssertEqual(reminders.count, 1)
        XCTAssertEqual(reminders[0].shift.start, day(9, 6, 30), "the first shift after the vacation")
        XCTAssertEqual(reminders[0].remindAt, day(8, 18), "6 PM the evening before")
        let text = Vacations.reminderText(reminders[0])
        XCTAssertTrue(text.hasPrefix("Back to work tomorrow: Days at"))
        XCTAssertTrue(text.contains("first alarm"))
        XCTAssertTrue(Vacations.backToWork(vacations: [vacation], shifts: [monday], settings: settings, now: day(8, 19)).isEmpty, "not once it's passed")
    }

    func testNoShiftWithinAWeekNoReminder() {
        let rule = BridgeSettings().shiftRules[0]
        let later = ShiftCandidate.make(title: rule.keyword, start: day(20, 6, 30), rule: rule).0
        XCTAssertTrue(Vacations.backToWork(vacations: [vacation], shifts: [later], settings: BridgeSettings(), now: day(1)).isEmpty)
    }

    func testTravellingAndDays() {
        XCTAssertTrue(Vacations.isTravelling(notes: Vacations.travellingNote))
        XCTAssertTrue(Vacations.isTravelling(notes: "Flight UA 12\ntraveling"))
        XCTAssertFalse(Vacations.isTravelling(notes: "Staycation"))
        XCTAssertEqual(Vacations.lastDay(start: day(3), end: day(8)), day(7), "an all-day event ends at the next midnight")
        XCTAssertEqual(Vacations.lastDay(start: day(3), end: day(7, 23, 59)), day(7))
        XCTAssertTrue(vacation.covers(day(7, 12)))
        XCTAssertFalse(vacation.covers(day(8)))
        XCTAssertTrue(vacation.rangeText.contains("–"))
    }

    func testThePlanTellsHomeAssistant() {
        var plan = WakePlan(source: .none, alarmTimes: [], reason: "Leave")
        plan.vacationMorning = true
        plan.vacations = [DayRange(first: day(3), last: day(7))]
        let payload = plan.homeAssistantPayload(settings: BridgeSettings())
        XCTAssertEqual(payload["vacation"] as? Bool, true)
        XCTAssertEqual((payload["vacations"] as? [[String: String]])?.first?["first"], "2026-11-03")
    }

    func testMenuTitles() {
        XCTAssertEqual(BarAction.addLeave.title(day: ""), "Add vacation")
    }
}
