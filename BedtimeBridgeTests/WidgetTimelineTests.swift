import XCTest
@testable import BedtimeBridge

/// The medium and large widgets' timeline.
final class WidgetTimelineTests: XCTestCase {
    private let first = Date(timeIntervalSince1970: 1_800_000_000)
    private func at(_ minutes: Double) -> Date { first.addingTimeInterval(minutes * 60) }

    private var snapshot: NextAlarmSnapshot {
        var s = NextAlarmSnapshot(alarmTimes: [at(0), at(5), at(10)], cause: "Days", label: "Days shift", leaveBy: at(85))
        s.wakeTime = at(10)
        s.temporaryAlarms = [at(-120)]
        s.windDownAt = at(-450)
        s.goToBedAt = at(-390)
        return s
    }

    func testTheWholeNightInOrder() {
        let steps = snapshot.steps(after: at(-500))
        XCTAssertEqual(steps.map(\.kind), [.windDown, .goToBed, .temporary, .alarm, .alarm, .wakeUp, .leaveBy])
        XCTAssertEqual(steps.last?.title, "Leave by")
    }

    func testOnlyWhatsAhead() {
        let steps = snapshot.steps(after: at(2))
        XCTAssertEqual(steps.map(\.kind), [.alarm, .wakeUp, .leaveBy], "past alarms and last night are gone")
        XCTAssertEqual(snapshot.steps(after: at(100)).map(\.title), ["Time to go"], "leave-by stays a while after it")
        XCTAssertTrue(snapshot.steps(after: at(200)).isEmpty)
    }

    func testSnoozeShows() {
        var s = snapshot
        s.snoozedUntil = at(9)
        XCTAssertEqual(s.steps(after: at(1)).first?.kind, .alarm)
        XCTAssertTrue(s.steps(after: at(1)).contains { $0.kind == .snooze && $0.time == at(9) })
    }
}
