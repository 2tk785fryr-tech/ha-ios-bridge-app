import XCTest
@testable import BedtimeBridge

final class AlarmReasonTextTests: XCTestCase {
    func testPlainWords() {
        XCTAssertEqual(AlarmReasonText.make(cause: "Days", label: "Days shift"), "Reason for alarm: Days shift")
        XCTAssertEqual(AlarmReasonText.make(cause: "Swings", label: "Swings shift"), "Reason for alarm: Swings shift")
        XCTAssertEqual(AlarmReasonText.make(cause: "calendar", label: "Dentist"), "Reason for alarm: Appointment: Dentist")
        XCTAssertEqual(AlarmReasonText.make(cause: "automade", label: "Day off"), "Reason for alarm: Your own time")
        XCTAssertEqual(AlarmReasonText.make(cause: "noalarm", label: nil), "Reason for alarm: No alarm")
    }

    func testChangedAndInsteadOfAShift() {
        XCTAssertEqual(AlarmReasonText.make(cause: "Days", label: nil, changeReason: "Tired"),
                       "Reason for alarm: Days shift (morning changed: Tired)")
        XCTAssertEqual(AlarmReasonText.make(cause: "calendar", label: "Ultrasound", insteadOfShift: "Days"),
                       "Reason for alarm: Appointment: Ultrasound (instead of Days)")
    }
}
