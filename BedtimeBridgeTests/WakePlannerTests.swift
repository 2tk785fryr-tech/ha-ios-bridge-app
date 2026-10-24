import XCTest
@testable import BedtimeBridge

final class WakePlannerTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)
    private let settings = BridgeSettings()

    private func hours(_ h: Double) -> Date { now.addingTimeInterval(h * 3600) }

    func testShiftOnlyMakesThreeAlarmsTenMinutesApart() {
        let shift = ShiftCandidate(title: "Days", start: hours(9), wakeMinutesBefore: 60, cause: "Days")
        let plan = WakePlanner.plan(shift: shift, appointments: [], settings: settings, now: now)

        XCTAssertEqual(plan.cause, "Days")
        XCTAssertEqual(plan.alarmTimes, [hours(8), hours(8).addingTimeInterval(600), hours(8).addingTimeInterval(1200)])
    }

    func testEarlierAppointmentWins() {
        let shift = ShiftCandidate(title: "Swing shift", start: hours(10), wakeMinutesBefore: 60, cause: "Swings")
        // 7h start − 10 min early − 30 min drive − 60 min ready = 5h20m, before the 9h shift alarm.
        let appointment = AppointmentCandidate(title: "Dentist", start: hours(7), location: "Main St", travelSeconds: 1800)
        let plan = WakePlanner.plan(shift: shift, appointments: [appointment], settings: settings, now: now)

        XCTAssertEqual(plan.cause, "calendar")
        XCTAssertEqual(plan.firstAlarm, hours(5).addingTimeInterval(20 * 60))
        XCTAssertEqual(appointment.leaveBy(bufferMinutes: 10), hours(6).addingTimeInterval(20 * 60))
    }

    func testLaterAppointmentDoesNotOverrideShift() {
        let shift = ShiftCandidate(title: "Swings", start: hours(7), wakeMinutesBefore: 60, cause: "Swings")
        let appointment = AppointmentCandidate(title: "Lunch", start: hours(12), location: "Cafe", travelSeconds: 900)
        let plan = WakePlanner.plan(shift: shift, appointments: [appointment], settings: settings, now: now)

        XCTAssertEqual(plan.cause, "Swings")
        XCTAssertEqual(plan.firstAlarm, hours(6))
    }

    func testAppointmentWithoutShiftIsUsed() {
        let appointment = AppointmentCandidate(title: "Vet", start: hours(10), location: "Clinic", travelSeconds: 1200, fallbackReason: "offline")
        let plan = WakePlanner.plan(shift: nil, appointments: [appointment], settings: settings, now: now)

        XCTAssertEqual(plan.cause, "calendar")
        XCTAssertEqual(plan.firstAlarm, hours(10).addingTimeInterval(-600 - 1200 - 3600))
        XCTAssertEqual(plan.warnings.count, 1)
    }

    func testNothingFoundAsksForDayOff() {
        let plan = WakePlanner.plan(shift: nil, appointments: [], settings: settings, now: now)
        XCTAssertEqual(plan.cause, "noalarm")
        XCTAssertFalse(plan.hasAlarm)
    }

    func testRuleAndNoteMatchingIsCaseInsensitive() {
        XCTAssertEqual(WakePlanner.matchingRule(forTitle: "DAYS 0630-1900", rules: settings.shiftRules)?.keyword, "Days")
        XCTAssertEqual(WakePlanner.matchingRule(forTitle: "swings", rules: settings.shiftRules)?.keyword, "Swings")
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

    func testManualAlarmCause() {
        XCTAssertEqual(WakePlan(source: .manual, alarmTimes: [now], reason: "").cause, "automade")
    }

    // MARK: Departure-only services (Google)

    /// Rush hour: the later you leave, the longer the drive.
    private func rushHour(_ departure: Date) -> TimeInterval {
        let minutesAfterStart = departure.timeIntervalSince(hours(6)) / 60
        return (20 + max(0, minutesAfterStart) * 0.5) * 60
    }

    func testSolverArrivesOnTimeInRushHour() async throws {
        let arriveBy = hours(7)
        let allow = try await DepartureSolver.travelTime(arrivingBy: arriveBy, now: now) { self.rushHour($0) }
        let departure = arriveBy.addingTimeInterval(-allow)

        XCTAssertLessThanOrEqual(departure.addingTimeInterval(rushHour(departure)), arriveBy)
        // Shouldn't pad more than a few minutes beyond the real trip.
        XCTAssertLessThan(allow - rushHour(departure), 5 * 60)
    }

    func testSolverWithConstantDurationIsExact() async throws {
        var requests = 0
        let allow = try await DepartureSolver.travelTime(arrivingBy: hours(7), now: now) { _ in
            requests += 1
            return 25 * 60
        }
        XCTAssertEqual(allow, 25 * 60)
        XCTAssertLessThanOrEqual(requests, 2)
    }
}
