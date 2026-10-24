import XCTest
@testable import BedtimeBridge

final class WakePlannerTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)
    private let settings = BridgeSettings()

    private func hours(_ h: Double) -> Date { now.addingTimeInterval(h * 3600) }

    func testShiftOnlyMakesThreeAlarmsTenMinutesApart() {
        let shift = ShiftCandidate(title: "Days", start: hours(9), wakeMinutesBefore: 60)
        let plan = WakePlanner.plan(shift: shift, appointments: [], settings: settings, now: now)

        XCTAssertEqual(plan.source, .shift)
        XCTAssertEqual(plan.alarmTimes, [hours(8), hours(8).addingTimeInterval(600), hours(8).addingTimeInterval(1200)])
    }

    func testEarlierAppointmentWins() {
        let shift = ShiftCandidate(title: "Days", start: hours(10), wakeMinutesBefore: 60)
        // 7h start − 30 min drive − 60 min ready = 5.5h, before the 9h shift alarm.
        let appointment = AppointmentCandidate(title: "Dentist", start: hours(7), location: "Main St", travelSeconds: 1800, usedFallbackTravel: false)
        let plan = WakePlanner.plan(shift: shift, appointments: [appointment], settings: settings, now: now)

        XCTAssertEqual(plan.source, .appointment)
        XCTAssertEqual(plan.firstAlarm, hours(5.5))
    }

    func testLaterAppointmentDoesNotOverrideShift() {
        let shift = ShiftCandidate(title: "Days", start: hours(7), wakeMinutesBefore: 60)
        let appointment = AppointmentCandidate(title: "Lunch", start: hours(12), location: "Cafe", travelSeconds: 900, usedFallbackTravel: false)
        let plan = WakePlanner.plan(shift: shift, appointments: [appointment], settings: settings, now: now)

        XCTAssertEqual(plan.source, .shift)
        XCTAssertEqual(plan.firstAlarm, hours(6))
    }

    func testAppointmentWithoutShiftIsUsed() {
        let appointment = AppointmentCandidate(title: "Vet", start: hours(10), location: "Clinic", travelSeconds: 1200, usedFallbackTravel: true)
        let plan = WakePlanner.plan(shift: nil, appointments: [appointment], settings: settings, now: now)

        XCTAssertEqual(plan.source, .appointment)
        XCTAssertEqual(plan.firstAlarm, hours(10).addingTimeInterval(-1200 - 3600))
        XCTAssertEqual(plan.warnings.count, 1)
    }

    func testNothingFoundAsksForDayOff() {
        let plan = WakePlanner.plan(shift: nil, appointments: [], settings: settings, now: now)
        XCTAssertEqual(plan.source, .none)
        XCTAssertFalse(plan.hasAlarm)
    }

    func testRuleAndNoteMatchingIsCaseInsensitive() {
        XCTAssertEqual(WakePlanner.matchingRule(forTitle: "DAYS 0630-1900", rules: settings.shiftRules)?.keyword, "Days")
        XCTAssertNil(WakePlanner.matchingRule(forTitle: "Vacation", rules: settings.shiftRules))
        XCTAssertTrue(WakePlanner.notesRequestWakeUp("Bring forms. Wake Up", keyword: "wake up"))
        XCTAssertFalse(WakePlanner.notesRequestWakeUp(nil, keyword: "wake up"))
    }

    func testCustomAlarmSeries() {
        XCTAssertEqual(WakePlanner.alarmTimes(first: now, count: 2, spacingMinutes: 5), [now, now.addingTimeInterval(300)])
    }

    func testPastManualTimeRollsToTomorrow() {
        let calendar = Calendar(identifier: .gregorian)
        let earlier = now.addingTimeInterval(-3600)
        let next = BedtimeCoordinator.nextOccurrence(ofTimeIn: earlier, now: now, calendar: calendar)
        XCTAssertEqual(next, earlier.addingTimeInterval(86_400))
    }
}
