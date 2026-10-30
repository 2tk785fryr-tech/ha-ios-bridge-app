import AppIntents
import XCTest
@testable import BedtimeBridge

/// v0.4.3 item 11: Siri and Shortcuts actions.
final class SiriIntentTests: XCTestCase {
    func testEveryNewActionHasASiriPhraseWithinAppleLimit() {
        let shortcuts = BedtimeBridgeShortcuts.appShortcuts
        XCTAssertLessThanOrEqual(shortcuts.count, 10, "Apple allows 10 App Shortcuts")
        XCTAssertEqual(shortcuts.count, 10, "v0.4.6 item 2 added I'm awake")
    }

    func testSleepLaterAmounts() {
        XCTAssertEqual(SleepLaterAmount.thirty.choice, .later(minutes: 30))
        XCTAssertEqual(SleepLaterAmount.twoHours.choice, .later(minutes: 120))
        if case .at(let date) = SleepLaterAmount.eightHours.choice {
            XCTAssertEqual(date.timeIntervalSinceNow, 8 * 3600, accuracy: 5)
        } else {
            XCTFail("8 hours from now is a time")
        }
    }

    func testNapLengthsComeFromSettings() async throws {
        let lengths = try await NapLengthQuery().suggestedEntities().map(\.minutes)
        let expected = await MainActor.run { SettingsStore.shared.settings.napLengths }
        XCTAssertEqual(lengths, expected)
    }
}
