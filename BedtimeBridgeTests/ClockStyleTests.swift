import XCTest
@testable import BedtimeBridge

/// v0.4.7 item 10: Settings → Clock.
final class ClockStyleTests: XCTestCase {
    private let evening = Calendar.current.date(bySettingHour: 21, minute: 50, second: 0, of: Date())!

    func testTwelveAndTwentyFourHour() {
        XCTAssertEqual(evening.clockTime(style: .twentyFourHour), "21:50")
        XCTAssertTrue(evening.clockTime(style: .twelveHour).contains("9:50"))
        XCTAssertTrue(evening.clockTime(style: .twelveHour).uppercased().contains("PM"))
    }

    func testPhoneSettingAndWhatHomeAssistantGets() {
        XCTAssertTrue(ClockStyle.twentyFourHour.uses24Hour(phone24Hour: false))
        XCTAssertFalse(ClockStyle.twelveHour.uses24Hour(phone24Hour: true))
        XCTAssertTrue(ClockStyle.phone.uses24Hour(phone24Hour: true))
        var settings = BridgeSettings()
        settings.clockStyle = .twentyFourHour
        XCTAssertEqual(SettingsStore.everyMessage(settings)["clock_24h"] as? Bool, true)
    }

    func testTheAppsTimesUseIt() {
        let before = ClockStyle.current
        defer { ClockStyle.current = before }
        ClockStyle.current = .twentyFourHour
        XCTAssertEqual(WakePlanner.format(evening), "21:50")
    }
}
