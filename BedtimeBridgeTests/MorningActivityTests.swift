import XCTest
@testable import BedtimeBridge

/// v0.4.3 item 14: the morning Live Activity's lines.
final class MorningActivityTests: XCTestCase {
    private let calendar = Calendar.current
    private func at(_ h: Int, _ m: Int = 0) -> Date { calendar.date(from: DateComponents(year: 2026, month: 10, day: 30, hour: h, minute: m))! }

    func testWorstCase() {
        let apple = DriveEstimate(service: .apple, seconds: 32 * 60)
        let tomTom = DriveEstimate(service: .tomTom, seconds: 36 * 60)
        let google = DriveEstimate(service: .googleWorst, seconds: 41 * 60)
        XCTAssertEqual(MorningActivity.worstCaseMinutes([apple, tomTom, google]), 41, "Google's pessimistic estimate")
        XCTAssertEqual(MorningActivity.worstCaseMinutes([apple, tomTom]), 36, "else the longest asked")
        XCTAssertNil(MorningActivity.worstCaseMinutes([apple]), "else left out")
    }

    func testWeatherForTheDriveAndTheDay() {
        let hours = [
            ForecastHour(start: at(5), condition: "rainy", temperature: 58),
            ForecastHour(start: at(6), condition: "rainy", temperature: 58),
            ForecastHour(start: at(9), condition: "cloudy", temperature: 63),
            ForecastHour(start: at(12), condition: "cloudy", temperature: 71),
            ForecastHour(start: at(13), condition: "cloudy", temperature: 70),
            ForecastHour(start: at(15), condition: "rainy", temperature: 66),
            ForecastHour(start: at(22), condition: "cloudy", temperature: 55),
        ]
        let lines = MorningActivity.weatherLines(hours: hours, leaveBy: at(5, 45), now: at(5))
        XCTAssertEqual(lines.drive, "Rain · 58°")
        XCTAssertEqual(lines.day, "Cloudy · 71°/55° · rain after \(at(15).formatted(.dateTime.hour()))")
    }

    func testNextBackstopAndEnd() {
        let next = MorningActivity.nextBackstop(["early": at(4, 55), "deadline": at(5, 10), "late": at(5, 25)], now: at(5))
        XCTAssertEqual(next?.name, "Deadline")
        XCTAssertEqual(next?.at, at(5, 10))
        XCTAssertNil(MorningActivity.nextBackstop(["late": at(5, 25)], now: at(6)))
        XCTAssertEqual(MorningActivity.endsAt(leaveBy: at(5, 45)), at(6), "15 min after leave-by")
    }
}
