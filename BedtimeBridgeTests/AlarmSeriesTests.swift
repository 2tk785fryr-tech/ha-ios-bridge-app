import XCTest
@testable import BedtimeBridge

/// v0.4.7 item 7: the two alarm series, and Set Wake-Up Alarms using your own.
final class AlarmSeriesTests: XCTestCase {
    func testSetWakeUpAlarmsUsesYourOwnSeries() {
        var settings = BridgeSettings()
        settings.ownAlarmCount = 3
        settings.ownAlarmSpacingMinutes = 10
        settings.ownAlarmWakeIs = .first
        settings.alarmCount = 2
        settings.alarmSpacingMinutes = 5
        settings.wakeTimeIs = .last
        let eight = Calendar.current.date(bySettingHour: 8, minute: 0, second: 0, of: .now.addingTimeInterval(86400))!
        let own = OwnAlarmSeries.replacement(wake: eight, wakeIs: nil, settings: settings)
        XCTAssertEqual(own.wakeIs, .first)
        XCTAssertEqual(own.times, [0, 10, 20].map { eight.addingTimeInterval(Double($0) * 60) }, "starts at your time")
        // The action's Time Is still wins.
        XCTAssertEqual(OwnAlarmSeries.replacement(wake: eight, wakeIs: .last, settings: settings).times?.last, eight)
    }

    func testSummaries() {
        XCTAssertEqual(AlarmSeriesText.summary(count: 3, spacing: 10), "3 alarms, 10 min apart")
        XCTAssertEqual(AlarmSeriesText.summary(count: 1, spacing: 10), "1 alarm")
        XCTAssertEqual(AlarmSeriesText.alarmsRow(style: .app, snooze: 9), "\(AlarmStyle.app.displayName) · snooze 9 min")
        XCTAssertTrue(AlarmSeriesText.example(count: 3, spacing: 10, wakeIs: .last).hasPrefix("Up at"))
    }

    func testPageResetsOnlyItsOwnSeries() {
        var settings = BridgeSettings()
        settings.alarmCount = 5
        settings.ownAlarmCount = 4
        settings.snoozeMinutes = 7
        settings.resetToDefaults(SettingsPages.appointmentAlarms)
        XCTAssertEqual(settings.alarmCount, BridgeSettings().alarmCount)
        XCTAssertEqual(settings.ownAlarmCount, 4)
        XCTAssertEqual(settings.snoozeMinutes, 7)
        XCTAssertFalse(SettingsPages.alarms.contains("alarmCount"))
    }
}
