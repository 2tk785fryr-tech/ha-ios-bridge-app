import XCTest
@testable import BedtimeBridge

final class PrimaryActionTests: XCTestCase {
    private func make(set: Bool = true, changed: String? = nil, missing: Bool = false, calendar: Bool = false, plan: Bool = false) -> PrimaryAction {
        PrimaryAction.make(alarmsSet: set, defaultTitle: "Set 3 alarms, up by 4:30 AM", changedThisMorning: changed,
                           missingAlarms: missing, calendarChanged: calendar, planChanged: plan)
    }

    func testNothingSetShowsTheButton() {
        XCTAssertEqual(make(set: false).buttonTitle, "Set 3 alarms, up by 4:30 AM")
    }

    func testSetAndUnchangedShowsNoButton() {
        XCTAssertNil(make().buttonTitle)
    }

    func testTheButtonComesBackRewordedOnlyWhenSomethingChanged() {
        XCTAssertEqual(make(missing: true).buttonTitle, "Set the missing alarms")
        XCTAssertEqual(make(calendar: true).buttonTitle, "Calendar changed: re-plan alarms")
        XCTAssertEqual(make(plan: true).buttonTitle, "Plan changed: update alarms")
    }

    func testAChangeThisMorningIsNeverUndoneByTheButton() {
        let action = make(changed: "Tired", calendar: true, plan: true)
        XCTAssertNil(action.buttonTitle)
        XCTAssertEqual(action.note, "Changed this morning: Tired")
    }
}
