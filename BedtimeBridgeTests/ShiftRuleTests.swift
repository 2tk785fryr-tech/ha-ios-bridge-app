import XCTest
@testable import BedtimeBridge

final class ShiftRuleTests: XCTestCase {
    private var calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/New_York")!
        return calendar
    }()

    private func date(_ day: Int, _ hour: Int, _ minute: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 10, day: day, hour: hour, minute: minute))!
    }

    private let swings = ShiftRule(keyword: "Swings", timing: .fixedTime, fixedHour: 8, fixedMinute: 0, wakeIs: .first)

    func testSwingsHomeAtMidnightPlansAtTwoAMForEightAMSameDay() {
        // Planned at 1:45 AM after getting home from the last swing; next swing 2:30 PM today.
        let now = date(26, 1, 45)
        let (shift, warning) = ShiftCandidate.make(title: "Swings", start: date(26, 14, 30), rule: swings, calendar: calendar)
        XCTAssertNil(warning)
        let plan = WakePlanner.plan(shift: shift, appointments: [], settings: BridgeSettings(), now: now)
        XCTAssertEqual(plan.alarmTimes, [date(26, 8), date(26, 8, 10), date(26, 8, 20)])
        XCTAssertEqual(plan.cause, "Swings")
    }

    func testSwingsPlannedTheEveningBeforeUsesTheShiftDay() {
        let now = date(25, 22)
        let (shift, _) = ShiftCandidate.make(title: "Swings", start: date(26, 14, 30), rule: swings, calendar: calendar)
        let plan = WakePlanner.plan(shift: shift, appointments: [], settings: BridgeSettings(), now: now)
        XCTAssertEqual(plan.firstAlarm, date(26, 8))
    }

    func testFixedTimeIgnoresWeather() {
        let (shift, _) = ShiftCandidate.make(title: "Swings", start: date(26, 14, 30), rule: swings, calendar: calendar)
        let weather = WeatherAdjustment(minutes: 15, reason: "pouring")
        let plan = WakePlanner.plan(shift: shift, appointments: [], settings: BridgeSettings(), now: date(26, 1), weather: weather)
        XCTAssertEqual(plan.firstAlarm, date(26, 8))
        XCTAssertNil(plan.weather)
    }

    func testPerShiftSeriesOverridesGeneral() {
        // Days: up 80 min before 6:30 (5:10), 4 alarms 5 min apart ending at 5:10.
        let days = ShiftRule(keyword: "Days", wakeMinutesBefore: 80, wakeIs: .last, alarmCount: 4, alarmSpacingMinutes: 5)
        let (shift, _) = ShiftCandidate.make(title: "Days", start: date(26, 6, 30), rule: days, calendar: calendar)
        let plan = WakePlanner.plan(shift: shift, appointments: [], settings: BridgeSettings(), now: date(25, 22))
        XCTAssertEqual(plan.alarmTimes, [date(26, 4, 55), date(26, 5), date(26, 5, 5), date(26, 5, 10)])
    }

    func testAppointmentsKeepTheGeneralSeries() {
        let days = ShiftRule(keyword: "Days", wakeMinutesBefore: 80, wakeIs: .first, alarmCount: 4, alarmSpacingMinutes: 5)
        let (shift, _) = ShiftCandidate.make(title: "Days", start: date(26, 9), rule: days, calendar: calendar)
        let dentist = AppointmentCandidate(title: "Dentist", start: date(26, 7), location: "Main St", travelSeconds: 1800)
        let plan = WakePlanner.plan(shift: shift, appointments: [dentist], settings: BridgeSettings(), now: date(25, 22))
        // General: 3 alarms, 10 min apart, ending at wake-up (7:00 − 10 − 30 − 60 = 5:20).
        XCTAssertEqual(plan.alarmTimes, [date(26, 5), date(26, 5, 10), date(26, 5, 20)])
    }

    func testFixedTimeAfterShiftStartFallsBackWithWarning() {
        let odd = ShiftRule(keyword: "Days", timing: .fixedTime, wakeMinutesBefore: 60, fixedHour: 8)
        let (shift, warning) = ShiftCandidate.make(title: "Days", start: date(26, 6, 30), rule: odd, calendar: calendar)
        XCTAssertNil(shift.fixedWake)
        XCTAssertEqual(shift.wakeTime, date(26, 5, 30))
        XCTAssertNotNil(warning)
    }

    func testOverrideSwapsInTheOtherShiftsTiming() {
        let (days, _) = ShiftCandidate.make(title: "Days", start: date(26, 14, 30), rule: ShiftRule(keyword: "Days"), calendar: calendar)
        let result = PlanAdjustments.applyShiftOverride("Swings", to: days, rules: [ShiftRule(keyword: "Days"), swings])
        XCTAssertEqual(result.shift?.cause, "Swings")
        XCTAssertNotNil(result.shift?.fixedWake)
    }

    func testDefaultDaysGivesFourTwentyToFourThirty() {
        let days = BridgeSettings().shiftRules.first { $0.keyword == "Days" }!
        let (shift, _) = ShiftCandidate.make(title: "Days", start: date(26, 6, 30), rule: days, calendar: calendar)
        let plan = WakePlanner.plan(shift: shift, appointments: [], settings: BridgeSettings(), now: date(25, 21))
        XCTAssertEqual(plan.alarmTimes, [date(26, 4, 20), date(26, 4, 25), date(26, 4, 30)])
        XCTAssertEqual(plan.wakeTime, date(26, 4, 30))
    }

    func testOldSavedRulesStillLoad() throws {
        let json = #"{"id":"6F1C2B9E-6C1F-4C69-9C1A-2B8E1D3F4A5B","keyword":"Days","wakeMinutesBefore":75}"#
        let rule = try JSONDecoder().decode(ShiftRule.self, from: Data(json.utf8))
        XCTAssertEqual(rule.wakeMinutesBefore, 75)
        XCTAssertEqual(rule.timing, .beforeShift)
        XCTAssertNil(rule.alarmCount)
    }
}
