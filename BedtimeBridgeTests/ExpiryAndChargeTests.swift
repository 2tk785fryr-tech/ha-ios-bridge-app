import XCTest
@testable import BedtimeBridge

/// v0.4.3 items 9 (app expiry) and 10 (phone not charging).
final class ExpiryAndChargeTests: XCTestCase {
    func testItem9ReadsTheExpiryFromTheProfile() {
        let plist = """
        <?xml version="1.0" encoding="UTF-8"?><!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
        <plist version="1.0"><dict><key>ExpirationDate</key><date>2026-11-07T21:14:00Z</date><key>TeamIdentifier</key><array><string>E3P6U6KP7P</string></array></dict></plist>
        """
        var data = Data([0x30, 0x82, 0x01, 0x02])  // the signature around it
        data.append(Data(plist.utf8))
        data.append(Data([0xA0, 0x00]))
        XCTAssertEqual(AppExpiry.expiration(inProfile: data), ISO8601DateFormatter().date(from: "2026-11-07T21:14:00Z"))
        XCTAssertEqual(AppExpiry.team(inProfile: data), "E3P6U6KP7P", "the team Home Assistant's push key signs for")
    }

    func testItem9BannerFromThreeDaysRedOnTheLastDay() {
        let calendar = Calendar.current
        let now = calendar.date(from: DateComponents(year: 2026, month: 11, day: 5, hour: 9))!
        let expires = calendar.date(from: DateComponents(year: 2026, month: 11, day: 7, hour: 21, minute: 14))!
        XCTAssertNil(AppExpiry.banner(expires: expires, now: calendar.date(byAdding: .day, value: -2, to: now)!), "hidden more than 3 days out")
        let banner = AppExpiry.banner(expires: expires, now: now)
        XCTAssertEqual(banner?.text.hasPrefix("Reinstall from Xcode in 2 days (expires "), true)
        XCTAssertEqual(banner?.urgent, false)
        XCTAssertEqual(AppExpiry.banner(expires: expires, now: calendar.date(byAdding: .day, value: 2, to: now)!)?.urgent, true, "red on the last day")
        XCTAssertNil(AppExpiry.banner(expires: nil, now: now), "no profile (simulator): nothing")
    }

    func testItem10SettingsGoToHomeAssistantWithEveryMessage() {
        var settings = BridgeSettings()
        XCTAssertTrue(settings.chargeWarningEnabled)
        XCTAssertEqual(settings.chargeWarningThreshold, 30)
        settings.chargeWarningThreshold = 20
        let warning = SettingsStore.everyMessage(settings)["charge_warning"] as? [String: Any]
        XCTAssertEqual(warning?["threshold"] as? Int, 20)
        XCTAssertEqual(warning?["enabled"] as? Bool, true)
    }
}
