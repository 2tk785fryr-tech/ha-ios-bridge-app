import XCTest
@testable import BedtimeBridge

final class PlanAdjustmentsTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)
    private let settings = BridgeSettings()

    private func hours(_ h: Double) -> Date { now.addingTimeInterval(h * 3600) }
    private var daysShift: ShiftCandidate { ShiftCandidate(title: "Days", start: hours(9), wakeMinutesBefore: 60, cause: "Days") }

    // MARK: Skipped morning

    func testSkippedMorningDropsItsAlarms() {
        let plan = WakePlanner.plan(shift: daysShift, appointments: [], settings: settings, now: now)
        XCTAssertTrue(plan.hasAlarm)
        let skipped = PlanAdjustments.skipping(plan, morning: plan.firstAlarm)
        XCTAssertFalse(skipped.hasAlarm)
        XCTAssertEqual(skipped.source, .none)
        XCTAssertEqual(skipped.cause, AlarmCause.none)
        XCTAssertEqual(skipped.shift, daysShift)
        XCTAssertTrue(skipped.warnings.first?.contains("turned off") == true)
    }

    func testOtherMorningsKeepTheirAlarms() {
        let plan = WakePlanner.plan(shift: daysShift, appointments: [], settings: settings, now: now)
        let dayBefore = plan.firstAlarm!.addingTimeInterval(-86400)
        XCTAssertEqual(PlanAdjustments.skipping(plan, morning: dayBefore), plan)
        XCTAssertEqual(PlanAdjustments.skipping(plan, morning: nil), plan)
    }

    // MARK: Shift override

    func testAutoLeavesCalendarShift() {
        let result = PlanAdjustments.applyShiftOverride("Auto", to: daysShift, rules: settings.shiftRules)
        XCTAssertEqual(result.shift, daysShift)
        XCTAssertNil(result.warning)
    }

    func testOffDropsWorkAlarm() {
        let result = PlanAdjustments.applyShiftOverride("Off", to: daysShift, rules: settings.shiftRules)
        XCTAssertNil(result.shift)
        XCTAssertNotNil(result.warning)
    }

    func testShiftNameSwapsRule() {
        let rules = [ShiftRule(keyword: "Days", wakeMinutesBefore: 60), ShiftRule(keyword: "Swings", wakeMinutesBefore: 90)]
        let result = PlanAdjustments.applyShiftOverride("Swings", to: daysShift, rules: rules)
        XCTAssertEqual(result.shift?.cause, "Swings")
        XCTAssertEqual(result.shift?.wakeMinutesBefore, 90)
        XCTAssertEqual(result.shift?.start, daysShift.start)
    }

    func testOverrideWithoutCalendarShiftWarns() {
        let result = PlanAdjustments.applyShiftOverride("Days", to: nil, rules: settings.shiftRules)
        XCTAssertNil(result.shift)
        XCTAssertNotNil(result.warning)
    }

    // MARK: HA cross-check

    func testMatchingShiftStartsHaveNoWarning() {
        XCTAssertNil(PlanAdjustments.shiftMismatchWarning(calendarShift: daysShift, haNextShiftStart: hours(9), lookAheadEnd: hours(24)))
    }

    func testHaExpectingNoShiftWarns() {
        XCTAssertNotNil(PlanAdjustments.shiftMismatchWarning(calendarShift: daysShift, haNextShiftStart: hours(40), lookAheadEnd: hours(24)))
    }

    func testCalendarMissingShiftWarns() {
        XCTAssertNotNil(PlanAdjustments.shiftMismatchWarning(calendarShift: nil, haNextShiftStart: hours(9), lookAheadEnd: hours(24)))
    }

    // MARK: Weather

    func testBadConditionInWindowAddsTime() {
        let forecast = [
            ForecastHour(start: hours(6), condition: "cloudy", temperature: 60),
            ForecastHour(start: hours(8), condition: "pouring", temperature: 60),
            ForecastHour(start: hours(12), condition: "snowy", temperature: 20),
        ]
        let result = PlanAdjustments.weather(forecast: forecast, window: hours(7)...hours(9), conditions: settings.badWeatherConditions, freezingAt: 32, extraMinutes: 15)
        XCTAssertEqual(result?.minutes, 15)
        XCTAssertTrue(result?.reason.hasPrefix("pouring") ?? false)
    }

    func testWeatherOutsideWindowIgnored() {
        let forecast = [ForecastHour(start: hours(12), condition: "pouring", temperature: 60)]
        XCTAssertNil(PlanAdjustments.weather(forecast: forecast, window: hours(7)...hours(9), conditions: settings.badWeatherConditions, freezingAt: 32, extraMinutes: 15))
    }

    func testFreezingRainCounts() {
        let forecast = [ForecastHour(start: hours(7), condition: "rainy", temperature: 31)]
        let result = PlanAdjustments.weather(forecast: forecast, window: hours(7)...hours(9), conditions: [], freezingAt: 32, extraMinutes: 10)
        XCTAssertEqual(result?.minutes, 10)
    }

    func testWeatherMovesShiftAlarmAndAppointmentDrive() {
        let weather = WeatherAdjustment(minutes: 15, reason: "pouring at 8 AM")
        let shiftPlan = WakePlanner.plan(shift: daysShift, appointments: [], settings: settings, now: now, weather: weather)
        XCTAssertEqual(shiftPlan.wakeTime, hours(8).addingTimeInterval(-15 * 60))

        let appointment = AppointmentCandidate(title: "Dentist", start: hours(7), location: "Main St", travelSeconds: 1800)
        let plan = WakePlanner.plan(shift: nil, appointments: [appointment], settings: settings, now: now, weather: weather)
        // 7h − 10 min early − (30 + 15) min drive − 60 min ready
        XCTAssertEqual(plan.wakeTime, hours(7).addingTimeInterval(-(10 + 45 + 60) * 60))
    }

    // MARK: Are you really up?

    func testStillInBedKeepsTheRest() {
        XCTAssertEqual(PlanAdjustments.isUp(latchState: "off", bedState: "on", bedUnchangedFor: 600), false)
        XCTAssertEqual(PlanAdjustments.isUp(latchState: "off", bedState: "unavailable", bedUnchangedFor: nil), false)
    }

    func testDoorOpenedOrBedEmptyAWhileMeansUp() {
        XCTAssertEqual(PlanAdjustments.isUp(latchState: "on", bedState: "on", bedUnchangedFor: 0), true)
        XCTAssertEqual(PlanAdjustments.isUp(latchState: "off", bedState: "off", bedUnchangedFor: 90), true)
    }

    func testBriefBedDropoutIsNotUp() {
        XCTAssertEqual(PlanAdjustments.isUp(latchState: "off", bedState: "off", bedUnchangedFor: 19), false)
    }

    func testNoSensorsIsUnknown() {
        XCTAssertNil(PlanAdjustments.isUp(latchState: nil, bedState: nil, bedUnchangedFor: nil))
    }

    // MARK: Pairing link

    func testPairingLinkGivesBothAddresses() {
        let link = URL(string: "bedtimebridge://pair?remote=https%3A%2F%2Fhooks.nabu.casa%2Fabc&local=http%3A%2F%2F192.168.1.10%3A8123%2Fapi%2Fwebhook%2Fxyz")!
        let addresses = HomeAssistantLinks.addresses(in: link)
        XCTAssertEqual(addresses?.remote, "https://hooks.nabu.casa/abc")
        XCTAssertEqual(addresses?.local, "http://192.168.1.10:8123/api/webhook/xyz")
    }

    func testOtherLinksAreNotPairingLinks() {
        XCTAssertNil(HomeAssistantLinks.addresses(in: URL(string: "bedtimebridge://replan")!))
        XCTAssertNil(HomeAssistantLinks.addresses(in: URL(string: "https://hooks.nabu.casa/abc")!))
        XCTAssertNil(HomeAssistantLinks.addresses(in: URL(string: "bedtimebridge://pair")!))
    }

    // MARK: Settings from the Home Assistant integration

    func testHomeAssistantSettingsOverridePhone() {
        let remote: [String: Any] = [
            "get_ready_minutes": 45,
            "snooze_minutes": 5,
            "shift_lead_minutes": ["days": 75],
        ]
        let merged = settings.applying(remote)
        XCTAssertEqual(merged.getReadyMinutes, 45)
        XCTAssertEqual(merged.snoozeMinutes, 5)
        XCTAssertEqual(merged.shiftRules.first { $0.keyword == "Days" }?.wakeMinutesBefore, 75)
        XCTAssertEqual(merged.shiftRules.first { $0.keyword == "Swings" }?.wakeMinutesBefore, 60)
        XCTAssertEqual(merged.arrivalBufferMinutes, settings.arrivalBufferMinutes)
    }

    func testPayloadHasIntegrationKeys() {
        let appointment = AppointmentCandidate(title: "Dentist", start: hours(7), location: "Main St", travelSeconds: 1800)
        let plan = WakePlanner.plan(shift: nil, appointments: [appointment], settings: settings, now: now)
        let payload = plan.homeAssistantPayload(settings: settings)
        XCTAssertEqual(payload["alarm_cause"] as? String, "calendar")
        XCTAssertEqual(payload["label"] as? String, "Dentist")
        XCTAssertEqual(payload["drive_minutes"] as? Int, 30)
        XCTAssertNotNil(payload["leave_by"] as? String)
        XCTAssertEqual((payload["alarm_times"] as? [String])?.count, 3)
    }
}
