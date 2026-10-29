import XCTest
@testable import BedtimeBridge

final class MorningChangeTests: XCTestCase {
    private let wake = Date(timeIntervalSince1970: 1_800_000_000)
    private var settings: BridgeSettings {
        var s = BridgeSettings()
        s.alarmCount = 3
        s.alarmSpacingMinutes = 10
        s.wakeTimeIs = .last
        return s
    }

    func testTwoHoursLaterUsesTheUsualSeries() {
        let change = MorningChange.make(.later(minutes: 120), currentWake: wake, settings: settings)
        let newWake = wake.addingTimeInterval(7200)
        XCTAssertEqual(change.alarmTimes, [-1200, -600, 0].map { newWake.addingTimeInterval($0) })
        XCTAssertEqual(change.delayMinutes, 120)
    }

    func testPickATimeCountsTheDelayFromTheCurrentWake() {
        let change = MorningChange.make(.at(wake.addingTimeInterval(45 * 60)), currentWake: wake, settings: settings)
        XCTAssertEqual(change.delayMinutes, 45)
        let earlier = MorningChange.make(.at(wake.addingTimeInterval(-30 * 60)), currentWake: wake, settings: settings)
        XCTAssertEqual(earlier.delayMinutes, -30, "earlier works too")
    }

    func testNoAlarms() {
        let change = MorningChange.make(.noAlarms, currentWake: wake, settings: settings)
        XCTAssertTrue(change.alarmTimes.isEmpty)
        XCTAssertEqual(change.delayMinutes, 0)
        let backstops = ["early": wake]
        XCTAssertEqual(change.backstops(backstops), backstops, "backstops stay")
        XCTAssertNil(change.sleepIn(curtainsOpenAt: wake))
    }

    func testBackstopsMoveWithTheWake() {
        let change = MorningChange.make(.later(minutes: 30), currentWake: wake, settings: settings)
        XCTAssertEqual(change.backstops(["early": wake])["early"], wake.addingTimeInterval(1800))
    }

    func testSleepInFollowsTheCurtains() {
        let change = MorningChange.make(.later(minutes: 120), currentWake: wake, settings: settings)
        XCTAssertEqual(change.sleepIn(curtainsOpenAt: wake.addingTimeInterval(3600)), true)
        XCTAssertEqual(change.sleepIn(curtainsOpenAt: wake.addingTimeInterval(3 * 3600)), false)
        XCTAssertNil(change.sleepIn(curtainsOpenAt: nil))
    }

    func testAChangeLandingInThePastIsntOffered() {
        let change = MorningChange.make(.later(minutes: 30), currentWake: wake, settings: settings)
        XCTAssertTrue(change.isPossible(now: wake))
        XCTAssertFalse(change.isPossible(now: wake.addingTimeInterval(3600)))
    }

    func testCurrentWakeFollowsTheSetting() {
        let series = [wake, wake.addingTimeInterval(600)]
        XCTAssertEqual(MorningChange.currentWake(series: series, wakeIs: .last), series[1])
        XCTAssertEqual(MorningChange.currentWake(series: series, wakeIs: .first), series[0])
    }

    /// v0.4.1 item 2: once an alarm was stopped, a change is "back to bed" even from the snooze screen.
    func testPhaseIsUpOnceAnAlarmWasStopped() {
        XCTAssertEqual(BedtimeCoordinator.changePhase(requested: .snoozing, stopped: false), .snoozing)
        XCTAssertEqual(BedtimeCoordinator.changePhase(requested: .snoozing, stopped: true), .up)
        XCTAssertEqual(BedtimeCoordinator.changePhase(requested: .up, stopped: false), .up)
    }

    /// v0.4.1 item 3 (28 Oct): Days is 3 alarms, 5 min apart, wake = last; +30 from 4:30 is
    /// 4:50 / 4:55 / 5:00, not the general 4:40 / 4:50 / 5:00.
    func testAChangeKeepsTheMorningsOwnPattern() {
        let days = [0, 300, 600].map { wake.addingTimeInterval($0) }
        var general = settings
        general.alarmSpacingMinutes = 10
        let pattern = SeriesPattern.from(series: days, wake: days[2], fallback: general)
        XCTAssertEqual(pattern, SeriesPattern(count: 3, spacingMinutes: 5, wakeIs: .last))
        let change = MorningChange.make(.later(minutes: 30), currentWake: days[2], pattern: pattern)
        let newWake = days[2].addingTimeInterval(1800)
        XCTAssertEqual(change.alarmTimes, [-600, -300, 0].map { newWake.addingTimeInterval($0) })

        // Pick a time uses the same pattern.
        let picked = MorningChange.make(.at(newWake), currentWake: days[2], pattern: pattern)
        XCTAssertEqual(picked.alarmTimes, change.alarmTimes)
    }

    func testPatternWithTheWakeAsTheFirstAlarm() {
        let swings = [0, 600, 1200].map { wake.addingTimeInterval($0) }
        XCTAssertEqual(SeriesPattern.from(series: swings, wake: swings[0], fallback: settings),
                       SeriesPattern(count: 3, spacingMinutes: 10, wakeIs: .first))
    }
}
