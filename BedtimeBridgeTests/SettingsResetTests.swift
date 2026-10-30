import XCTest
@testable import BedtimeBridge

/// v0.4.3 items 6–8: the Alarms page tidy, the resets, and each setting's default.
final class SettingsResetTests: XCTestCase {
    private func keys(_ settings: BridgeSettings) -> Set<String> {
        let object = try! JSONSerialization.jsonObject(with: JSONEncoder().encode(settings)) as! [String: Any]
        return Set(object.keys)
    }

    func testItem6YourOwnAlarmsHoldsTheStartTimeAndTheBackstops() {
        XCTAssertEqual(SettingsPages.ownAlarms.first, "newAlarmHoursAhead", "Start new alarms this far from now, at the top")
        for key in ["ownBackstopsDayOff", "ownBackstopsLeave", "ownEarlyMinutes", "ownDeadlineMinutes", "ownLateMinutes", "ownBackstopsFull"] {
            XCTAssertTrue(SettingsPages.ownAlarms.contains(key), "\(key) folded into Your own alarms")
        }
        XCTAssertFalse(SettingsPages.alarms.contains("newAlarmHoursAhead"), "moved off the main Alarms page")
    }

    func testItem7ResetSettingsKeepsTheLinkAndItem7aSaysWhatItLeaves() {
        var changed = BridgeSettings()
        changed.alarmCount = 5
        changed.homeAssistantURL = "http://ha.local:8123"
        let reset = ResetActions.defaultSettings(keeping: changed)
        XCTAssertEqual(reset.alarmCount, BridgeSettings().alarmCount)
        XCTAssertEqual(reset.homeAssistantURL, "http://ha.local:8123", "HA links stay")
        XCTAssertEqual(ResetKind.allCases.count, 4)
        XCTAssertTrue(ResetKind.alarms.leaves.joined().contains("Sleep In"))
        XCTAssertNotNil(ResetKind.homeAssistant.warning)
    }

    func testItem8EverySettingIsOnAPageWithAReset() {
        let covered = Set(SettingsPages.all.flatMap { $0 })
        let notOnAPage: Set<String> = [
            // Kept for Home Assistant's own copy (v0.4) and written by the app itself.
            "leaveReminderLeadMinutes",
        ]
        let missing = keys(BridgeSettings()).subtracting(covered).subtracting(notOnAPage)
        XCTAssertEqual(missing, [], "settings with no page reset")
        XCTAssertTrue(covered.isSubset(of: keys(BridgeSettings())), "page lists name real settings")
    }

    func testItem8ResetThisPageOnlyTouchesThatPage() {
        var settings = BridgeSettings()
        settings.napAlarmCount = 4
        settings.alarmCount = 7
        settings.resetToDefaults(SettingsPages.nap)
        XCTAssertEqual(settings.napAlarmCount, BridgeSettings().napAlarmCount)
        XCTAssertEqual(settings.alarmCount, 7)
    }

    func testItem8DefaultsReadAsSpecified() {
        XCTAssertEqual(DurationText.hours(390), "6.5 h")
        XCTAssertEqual(DurationText.hours(120), "2 h")
    }
}
