import XCTest
@testable import BedtimeBridge

/// v0.4.3 item 16: quick actions per moment, and their settings.
final class ShortcutsTests: XCTestCase {
    func testDefaultsPerMoment() {
        let settings = BridgeSettings()
        XCTAssertEqual(QuickActions.items(for: .daytime, settings: settings), [.nap, .previewTomorrow, .addWakeUpEvent, .addLeave])
        XCTAssertEqual(QuickActions.items(for: .evening, settings: settings), [.sleepLater, .noAlarmsTomorrow, .startWindDown, .previewTomorrow])
        XCTAssertEqual(QuickActions.items(for: .morning, settings: settings), [.wakeLater, .upEarlyOrEnd, .backToBed])
    }

    func testTheMomentFollowsTheBar() {
        var i = BottomBar.Inputs()
        XCTAssertEqual(QuickActionMoment.now(i), .daytime)
        i.evening = true
        XCTAssertEqual(QuickActionMoment.now(i), .daytime, "evening without alarms set")
        i.alarmsSet = 3
        XCTAssertEqual(QuickActionMoment.now(i), .evening)
        i.upEarlyWindow = true
        XCTAssertEqual(QuickActionMoment.now(i), .morning)
    }

    func testChosenUpToFourAndReset() {
        var settings = BridgeSettings()
        settings.quickActions["daytime"] = ["addLeave", "nap", "sleepLater", "previewTomorrow", "backToBed"]
        XCTAssertEqual(QuickActions.items(for: .daytime, settings: settings), [.addLeave, .nap, .sleepLater, .previewTomorrow], "at most 4, in your order")
        settings.resetToDefaults(SettingsPages.shortcuts)
        XCTAssertEqual(QuickActions.items(for: .daytime, settings: settings), QuickActionMoment.defaults[.daytime])
        XCTAssertFalse(settings.windDownControlOpensApp, "Wind-down acts directly by default")
        XCTAssertFalse(settings.napControlNapsNow, "Nap opens the nap screen by default")
        XCTAssertFalse(settings.widgetTapAlwaysTonight, "the widget opens what matters now by default")
    }

    func testQuickActionURLsOpenTheApp() {
        XCTAssertEqual(QuickAction.noAlarmsTomorrow.url.absoluteString, "bedtimebridge://action/noAlarmsTomorrow")
        XCTAssertEqual(QuickAction(rawValue: QuickAction.backToBed.url.lastPathComponent), .backToBed)
    }
}
