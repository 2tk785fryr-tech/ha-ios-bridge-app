import XCTest
@testable import BedtimeBridge

/// v0.4 item 6: what the plan tells Home Assistant for the backstop ladder.
final class LadderBlockTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)
    private func hours(_ h: Double) -> Date { now.addingTimeInterval(h * 3600) }
    private let iso: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.timeZone = .current
        return f
    }()

    func testShiftMorningSendsLeaveByAndFirstDayBack() {
        var settings = BridgeSettings()
        settings.workArrivalBufferMinutes = 10
        let shift = ShiftCandidate(title: "Days", start: hours(9), wakeMinutesBefore: 60, cause: "Days")
        var plan = WakePlanner.plan(shift: shift, appointments: [], settings: settings, now: now)
        plan.commute = Commute(travelSeconds: 35 * 60)
        plan.firstDayBack = true

        let block = plan.ladderBlock(settings: settings)
        XCTAssertEqual(block["type"] as? String, "shift")
        XCTAssertEqual(block["shift_start"] as? String, iso.string(from: hours(9)))
        XCTAssertEqual(block["leave_by"] as? String, iso.string(from: hours(9).addingTimeInterval(-45 * 60)))
        XCTAssertEqual(block["first_day_back"] as? Bool, true)
        XCTAssertEqual(block["work_buffer_minutes"] as? Int, 10)
    }

    func testShiftWithoutLocationLeavesLeaveByToTheCalendar() {
        let settings = BridgeSettings()
        let shift = ShiftCandidate(title: "Days", start: hours(9), wakeMinutesBefore: 60, cause: "Days")
        let block = WakePlanner.plan(shift: shift, appointments: [], settings: settings, now: now).ladderBlock(settings: settings)
        XCTAssertEqual(block["type"] as? String, "shift")
        XCTAssertNil(block["leave_by"])
        XCTAssertNil(block["first_day_back"], "unknown: Home Assistant checks its own calendar")
    }

    func testAppointmentMorning() {
        var settings = BridgeSettings()
        settings.arrivalBufferMinutes = 10
        let dentist = AppointmentCandidate(title: "Dentist", start: hours(7), location: "Main St", travelSeconds: 1800)
        let block = WakePlanner.plan(shift: nil, appointments: [dentist], settings: settings, now: now).ladderBlock(settings: settings)
        XCTAssertEqual(block["type"] as? String, "appointment")
        XCTAssertEqual(block["appointment"] as? String, "Dentist")
        XCTAssertEqual(block["appointment_start"] as? String, iso.string(from: hours(7)))
        XCTAssertEqual(block["leave_by"] as? String, iso.string(from: hours(7).addingTimeInterval(-40 * 60)))
    }

    func testWeatherMinutesPerCondition() {
        var settings = BridgeSettings()
        settings.weatherExtraMinutes = 15
        settings.weatherConditionMinutes = ["snowy": 30, "hail": 0]
        let plan = WakePlanner.plan(shift: nil, appointments: [], settings: settings, now: now)
        let minutes = plan.ladderBlock(settings: settings)["weather_minutes"] as? [String: Int]
        XCTAssertEqual(minutes?["snowy"], 30)
        XCTAssertEqual(minutes?["pouring"], 15)
        XCTAssertNil(minutes?["hail"], "a condition set to 0 adds nothing")
        XCTAssertEqual(minutes?["freezing"], 15)
        XCTAssertEqual(plan.ladderBlock(settings: settings)["type"] as? String, "none")
    }

    /// v0.4.1 item 14: your own alarm carries type own, on/off, offsets and firing.
    func testOwnAlarmBlock() {
        var settings = BridgeSettings()
        settings.ownBackstopsFull = false
        let wake = hours(8)
        var plan = WakePlan(source: .manual, wakeTime: wake, alarmTimes: [wake.addingTimeInterval(-600), wake], reason: "Day off alarm")
        let off = plan.ladderBlock(settings: settings)
        XCTAssertEqual(off["type"] as? String, "own")
        XCTAssertEqual(off["on"] as? Bool, false, "off by default")
        XCTAssertEqual(off["last_alarm"] as? String, iso.string(from: wake))
        XCTAssertEqual(off["offsets"] as? [String: Int], ["early": 15, "deadline": 30, "late": 45])
        XCTAssertEqual(off["firing"] as? String, "gentle")
        plan.ownBackstops = true
        XCTAssertEqual(plan.ladderBlock(settings: settings)["on"] as? Bool, true)
    }
}
