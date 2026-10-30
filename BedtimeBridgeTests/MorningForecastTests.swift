import XCTest
@testable import BedtimeBridge

/// v0.4.7 item 5: Morning weather shows the condition and the temperature.
final class MorningForecastTests: XCTestCase {
    private let us = Locale(identifier: "en_US")
    private let uk = Locale(identifier: "en_GB")

    private func at(_ hour: Int, _ minute: Int = 0, day: Int = 31) -> Date {
        Calendar.current.date(from: DateComponents(year: 2026, month: 10, day: day, hour: hour, minute: minute))!
    }

    private var hours: [ForecastHour] {
        (4...10).map { ForecastHour(start: at($0), condition: $0 < 6 ? "clear-night" : "rainy", temperature: Double(30 + $0)) }
    }

    func testCommuteUsesLeaveBy() {
        let (moment, time) = MorningForecast.moment(leaveBy: at(5, 50), wakeUp: at(4, 30), goodMorningFrom: "08:00", now: at(21, day: 30))
        XCTAssertEqual(moment, .commute)
        let forecast = MorningForecast.pick(hours: hours, at: time, moment: moment, unit: "°F")
        XCTAssertEqual(forecast?.text(locale: us), "Clear, 35° at \(WakePlanner.format(at(5, 50)))")
    }

    func testAlarmsWithoutAnEventUseTheWakeUp() {
        let (moment, time) = MorningForecast.moment(leaveBy: nil, wakeUp: at(7), goodMorningFrom: "08:00", now: at(21, day: 30))
        XCTAssertEqual(moment, .wakeUp)
        XCTAssertEqual(MorningForecast.pick(hours: hours, at: time, moment: moment, unit: "°F")?.text(locale: us), "Rain, 37° at \(WakePlanner.format(at(7)))")
    }

    func testNoAlarmsUseGoodMorningFrom() {
        let (moment, time) = MorningForecast.moment(leaveBy: nil, wakeUp: nil, goodMorningFrom: "08:00", now: at(21, day: 30))
        XCTAssertEqual(moment, .goodMorning)
        XCTAssertEqual(time, at(8))
        // After midnight it's still this morning's 8:00.
        XCTAssertEqual(MorningForecast.moment(leaveBy: nil, wakeUp: nil, goodMorningFrom: "08:00", now: at(1)).1, at(8))
    }

    func testUnitsFollowThePhone() {
        let celsius = MorningForecast(moment: .wakeUp, at: at(7), condition: "snowy", temperature: 0, unit: "°C")
        XCTAssertEqual(celsius.temperatureText(locale: us), "32°")
        XCTAssertEqual(celsius.temperatureText(locale: uk), "0°")
        let fahrenheit = MorningForecast(moment: .wakeUp, at: at(7), condition: "partlycloudy", temperature: 50, unit: "°F")
        XCTAssertEqual(fahrenheit.temperatureText(locale: uk), "10°")
        XCTAssertEqual(MorningForecast.conditionName("partlycloudy"), "Partly cloudy")
    }

    func testNoForecastNearTheTime() {
        XCTAssertNil(MorningForecast.pick(hours: hours, at: at(20), moment: .wakeUp, unit: "°F"))
    }
}
