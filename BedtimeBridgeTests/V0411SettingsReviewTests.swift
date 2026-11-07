import XCTest
@testable import BedtimeBridge

/// v0.4.11 items 49–63: the Settings review.
final class V0411SettingsReviewTests: XCTestCase {
    func testMovedSettingsResetWithTheirNewPage() {
        XCTAssertTrue(SettingsPages.mornings.contains("arrivalBufferMinutes"), "item 53")
        XCTAssertFalse(SettingsPages.appointments.contains("arrivalBufferMinutes"))
        XCTAssertTrue(SettingsPages.driveTime.contains("homeAddress"), "item 54")
        XCTAssertTrue(SettingsPages.calendars.contains("lookAheadHours"), "item 60")
        XCTAssertFalse(SettingsPages.alarms.contains("lookAheadHours"))
        XCTAssertTrue(SettingsPages.notifications.contains("chargeWarningEnabled"), "item 63")
        XCTAssertFalse(SettingsPages.optionWindows.contains("startWindDownHours"), "item 55: on Wind-down only")
    }

    func testEverySettingIsOnOnePageOnly() {
        let keys = SettingsPages.all.flatMap { $0 }
        XCTAssertEqual(keys.count, Set(keys).count, "\(Dictionary(grouping: keys, by: { $0 }).filter { $0.value.count > 1 }.keys)")
    }

    func testNotificationNamesAndWhenTheyreSent() {
        XCTAssertEqual(NotificationKind.tomorrow.title, "Alarm time moved")
        XCTAssertEqual(NotificationKind.napControl.title, "Nap won't fit")
        XCTAssertEqual(NotificationKind.appExpiry.title, "App expires soon")
        XCTAssertTrue(NotificationKind.allCases.allSatisfy { !$0.detail.isEmpty })
    }
}
