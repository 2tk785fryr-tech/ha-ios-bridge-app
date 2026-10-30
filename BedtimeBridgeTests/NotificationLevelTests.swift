import XCTest
@testable import BedtimeBridge

/// Settings → Notifications.
final class NotificationLevelTests: XCTestCase {
    func testDefaultsMatchWhatEachUsedBefore() {
        let settings = BridgeSettings()
        XCTAssertEqual(NotificationKind.goToBed.level(settings), .critical)
        XCTAssertEqual(NotificationKind.stillUp.level(settings), .timeSensitive)
        XCTAssertEqual(NotificationKind.leaveReminder.level(settings), .timeSensitive)
        XCTAssertEqual(NotificationKind.missingLocation.level(settings), .normal, "stays quiet: you're dozing off")
        XCTAssertEqual(NotificationKind.weekly.level(settings), .normal)
    }

    func testCriticalOnlyForHomeAssistantsOnes() {
        XCTAssertEqual(NotificationKind.goToBed.levels, [.normal, .timeSensitive, .critical])
        XCTAssertEqual(NotificationKind.leaveReminder.levels, [.normal, .timeSensitive])
        var settings = BridgeSettings()
        settings.notificationLevels["leaveReminder"] = "critical"
        XCTAssertEqual(NotificationKind.leaveReminder.level(settings), .timeSensitive, "an unavailable level falls back to the default")
    }

    func testHomeAssistantGetsItsLevels() {
        var settings = BridgeSettings()
        settings.notificationLevels["wind_down_bed"] = "time_sensitive"
        let sent = NotificationKind.forHomeAssistant(settings)
        XCTAssertEqual(sent["wind_down_bed"], "time_sensitive")
        XCTAssertEqual(sent["wind_down_reminder"], "time_sensitive")
        XCTAssertNil(sent["leaveReminder"], "the app's own aren't sent")
        XCTAssertEqual((SettingsStore.everyMessage(settings)["notification_levels"] as? [String: String])?["charge"], "time_sensitive")
    }
}
