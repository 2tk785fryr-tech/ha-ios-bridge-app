import WeatherKit
import XCTest
@testable import BedtimeBridge

/// Apple Weather as a forecast source: its conditions read as Home Assistant's names, so the
/// bad-weather settings work the same with it.
final class AppleWeatherTests: XCTestCase {
    func testConditionsMapToTheBadWeatherNames() {
        XCTAssertEqual(AppleWeatherForecast.condition(.heavyRain), "pouring")
        XCTAssertEqual(AppleWeatherForecast.condition(.snow), "snowy")
        XCTAssertEqual(AppleWeatherForecast.condition(.freezingRain), "snowy-rainy")
        XCTAssertEqual(AppleWeatherForecast.condition(.thunderstorms), "lightning-rainy")
        XCTAssertEqual(AppleWeatherForecast.condition(.hail), "hail")
        XCTAssertEqual(AppleWeatherForecast.condition(.partlyCloudy), "partlycloudy")
        XCTAssertEqual(AppleWeatherForecast.condition(.clear), "sunny")
        let bad = BridgeSettings().badWeatherConditions
        XCTAssertTrue(bad.contains(AppleWeatherForecast.condition(.heavySnow)), "heavy snow adds time by default")
        XCTAssertFalse(bad.contains(AppleWeatherForecast.condition(.drizzle)), "drizzle doesn't")
    }

    func testOfferedAsASource() {
        XCTAssertTrue(WeatherSource.allCases.contains(.apple))
        XCTAssertEqual(WeatherSource.apple.displayName, "Apple Weather")
    }
}
