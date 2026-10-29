import XCTest
@testable import BedtimeBridge

/// v0.4.2 item 3: nap lengths, the conflict check and the longest nap that fits.
final class NapPlannerTests: XCTestCase {
    private var calendar: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = .current
        return c
    }
    private func at(_ h: Int, _ m: Int) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 10, day: 29, hour: h, minute: m))!
    }

    func testDefaults() {
        let s = BridgeSettings()
        XCTAssertFalse(s.napEnabled)
        XCTAssertEqual([s.napAlarmCount, s.napSpacingMinutes, s.napReadyWithAddressMinutes, s.napReadyNoAddressMinutes], [2, 10, 30, 0])
        XCTAssertEqual(s.napLengths, [20, 30, 45, 60, 90, 120])
    }

    func testFirstAlarmIsNowPlusLengthThenTheSpacing() {
        let times = NapPlanner.times(now: at(13, 2), minutes: 20, count: 2, spacing: 10)
        XCTAssertEqual(times, [at(13, 22), at(13, 32)])
        XCTAssertEqual(NapPlanner.timesText(times), "\(WakePlanner.format(at(13, 22))) & \(WakePlanner.format(at(13, 32)))")
        XCTAssertEqual([20, 60, 90, 120].map(NapPlanner.lengthName), ["20 min", "1 hr", "1.5 hr", "2 hr"])
    }

    func testDentistWithAnAddress() {
        // Dentist 3:00 PM, 10 min early, 25 min drive → leave 2:25, ready 30 min → last alarm 1:55.
        let dentist = NapConflict(title: "Dentist", start: at(15, 0), hasAddress: true, driveMinutes: 25, arriveEarlyMinutes: 10, readyMinutes: 30)
        let limit = NapPlanner.limit(conflicts: [dentist], nextAlarm: at(4, 20).addingTimeInterval(86_400))!
        XCTAssertEqual(limit.latest, at(13, 55))
        XCTAssertEqual(limit.text, "Dentist at \(at(15, 0).formatted(.dateTime.hour().minute())), 25 min drive. Leave by \(WakePlanner.format(at(14, 25))), ready 30 min before, so your last nap alarm can be \(WakePlanner.format(at(13, 55))) at the latest")

        let now = at(13, 2)
        XCTAssertTrue(NapPlanner.fits(minutes: 30, now: now, count: 2, spacing: 10, limit: limit))  // 1:32 & 1:42
        XCTAssertFalse(NapPlanner.fits(minutes: 45, now: now, count: 2, spacing: 10, limit: limit)) // last 1:57
        // Longest: last alarm at 1:55 → first 1:45 → 43 min.
        XCTAssertEqual(NapPlanner.longest(now: now, count: 2, spacing: 10, limit: limit), 43)
    }

    func testNoAddressUsesItsOwnBuffer() {
        let call = NapConflict(title: "Call", start: at(15, 0), hasAddress: false, readyMinutes: 0)
        XCTAssertEqual(call.latestWake, at(15, 0))
        XCTAssertEqual(NapPlanner.limit(conflicts: [call], nextAlarm: nil)?.latest, at(15, 0))
    }

    func testTheNextRegularAlarmLimitsToo() {
        let limit = NapPlanner.limit(conflicts: [], nextAlarm: at(14, 0))!
        XCTAssertEqual(limit.reason, .nextAlarm(at(14, 0)))
        XCTAssertFalse(NapPlanner.fits(minutes: 60, now: at(13, 0), count: 2, spacing: 10, limit: limit))
        XCTAssertTrue(NapPlanner.fits(minutes: 50, now: at(13, 0), count: 2, spacing: 10, limit: limit))
        XCTAssertTrue(NapPlanner.fits(minutes: 600, now: at(13, 0), count: 2, spacing: 10, limit: nil))
    }

    func testStopScreenForANapAlarm() {
        let first = at(13, 22), second = at(13, 32)
        let stop = StopDescription.make(kind: .nap, alarmTime: first, series: [first, second], remaining: [second])
        XCTAssertEqual(stop.title, "\(WakePlanner.format(first)) · Nap")
        XCTAssertEqual(stop.detail, "Next: \(WakePlanner.format(second)) (backup)")
        XCTAssertEqual(StopDescription.make(kind: .nap, alarmTime: second, series: [first, second], remaining: []).detail, "Last nap alarm")
    }
}
