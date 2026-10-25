import XCTest
@testable import BedtimeBridge

final class OpenMeteoForecastTests: XCTestCase {
    func testWeatherCodesBecomeHomeAssistantConditions() {
        XCTAssertEqual(OpenMeteoForecast.condition(code: 75, gustsKPH: nil), "snowy")
        XCTAssertEqual(OpenMeteoForecast.condition(code: 65, gustsKPH: nil), "pouring")
        XCTAssertEqual(OpenMeteoForecast.condition(code: 61, gustsKPH: nil), "rainy")
        XCTAssertEqual(OpenMeteoForecast.condition(code: 67, gustsKPH: nil), "snowy-rainy")
        XCTAssertEqual(OpenMeteoForecast.condition(code: 45, gustsKPH: nil), "fog")
        XCTAssertEqual(OpenMeteoForecast.condition(code: 95, gustsKPH: nil), "lightning-rainy")
        XCTAssertEqual(OpenMeteoForecast.condition(code: 99, gustsKPH: nil), "hail")
    }

    func testStrongGustsOnACalmHourAreWindy() {
        XCTAssertEqual(OpenMeteoForecast.condition(code: 3, gustsKPH: 70), "windy")
        XCTAssertEqual(OpenMeteoForecast.condition(code: 3, gustsKPH: 30), "cloudy")
        // Snow stays snow however windy it is.
        XCTAssertEqual(OpenMeteoForecast.condition(code: 73, gustsKPH: 90), "snowy")
    }

    func testParsesHourlyResponse() throws {
        let json = """
        {"hourly":{"time":[1800000000,1800003600],"weather_code":[73,null],"temperature_2m":[-2.5,1.0],"wind_gusts_10m":[20,10]}}
        """
        let hours = try OpenMeteoForecast.hours(from: Data(json.utf8))
        XCTAssertEqual(hours.count, 1, "An hour with no code is skipped")
        XCTAssertEqual(hours.first?.condition, "snowy")
        XCTAssertEqual(hours.first?.temperature, -2.5)
        XCTAssertEqual(hours.first?.start, Date(timeIntervalSince1970: 1_800_000_000))
    }
}
