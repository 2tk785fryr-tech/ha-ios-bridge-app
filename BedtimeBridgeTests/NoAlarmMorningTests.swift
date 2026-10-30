import XCTest
@testable import BedtimeBridge

/// v0.4.6 item 2: I'm awake on mornings with no alarms.
final class NoAlarmMorningTests: XCTestCase {
    private func at(_ hour: Int, _ minute: Int = 0) -> Date {
        Calendar.current.date(bySettingHour: hour, minute: minute, second: 0, of: Date())!
    }

    func testBarOffersImAwakeOnAMorningWithNoAlarms() {
        var i = BottomBar.Inputs(now: at(7, 30))
        i.evening = ScreenClock.isEvening(i.now)
        i.awakeOffered = true
        let bar = BottomBar.make(i)
        XCTAssertEqual(bar.top, .main(.imAwake, "I'm awake · good morning"))
        XCTAssertTrue(BarAction.imAwake.isProtected, "slide-and-hold in the bar")
        XCTAssertTrue(BottomBar.menu(i, alarmStyleApp: true, morningKnown: false).contains(.imAwake))
    }

    func testNotOfferedWithAlarmsANapOrInTheEvening() {
        var i = BottomBar.Inputs(now: at(7, 30))
        i.awakeOffered = true
        i.alarmsSet = 2
        i.firstAlarm = at(8)
        XCTAssertNotEqual(BottomBar.make(i).top, .main(.imAwake, "I'm awake · good morning"))
        XCTAssertFalse(BottomBar.menu(i, alarmStyleApp: true, morningKnown: false).contains(.imAwake))
        i.alarmsSet = 0
        i.napUpAt = at(8)
        XCTAssertEqual(BottomBar.make(i).buttons, [.endNap, .changeNap])
        XCTAssertFalse(NoAlarmMorning.barOffers(offered: true, alarmsSet: 0, napping: false, evening: true))
        XCTAssertFalse(NoAlarmMorning.barOffers(offered: false, alarmsSet: 0, napping: false, evening: false))
    }

    func testSettingsGoToHomeAssistantWithEveryMessage() {
        var settings = BridgeSettings()
        XCTAssertEqual(settings.noAlarmEarliest, "08:00")
        XCTAssertEqual(settings.noAlarmUpMinutes, 15)
        XCTAssertEqual(settings.noAlarmWaitMinutes, 10)
        settings.noAlarmEarliest = "07:30"
        let sent = SettingsStore.everyMessage(settings)["awake_settings"] as? [String: Any]
        XCTAssertEqual(sent?["earliest"] as? String, "07:30")
        XCTAssertEqual(sent?["up_minutes"] as? Int, 15)
        XCTAssertEqual(sent?["wait_minutes"] as? Int, 10)
        XCTAssertEqual(sent?["enabled"] as? Bool, true)
    }

    func testWhatSiriAndTheControlSay() {
        XCTAssertTrue(NoAlarmMorning.dialog(.done).hasPrefix("Good morning"))
        XCTAssertTrue(NoAlarmMorning.dialog(.noHomeAssistant).contains("Home Assistant"))
        XCTAssertEqual(NotificationKind.upForDay.rawValue, "up_for_day")
        XCTAssertTrue(NotificationKind.upForDay.fromHomeAssistant)
    }
}
