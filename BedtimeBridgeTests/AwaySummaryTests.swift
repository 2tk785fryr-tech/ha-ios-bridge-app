import XCTest
@testable import BedtimeBridge

final class AwaySummaryTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    func testAllGood() {
        let text = AwaySummary.text(
            alarms: [now.addingTimeInterval(3600), now.addingTimeInterval(4200)],
            temporary: [],
            weather: .init(high: 78, condition: "sunny", isToday: false),
            houseAlarm: "Arm Stay",
            homeIssues: [],
            signOff: "Good night handsome!"
        )
        XCTAssertTrue(text.hasPrefix("First alarm \(WakePlanner.format(now.addingTimeInterval(3600)))."))
        XCTAssertTrue(text.contains("Tomorrow will be warm and sunny."))
        XCTAssertTrue(text.hasSuffix("Everything at home is good. Good night handsome!"))
    }

    func testProblemsAtHome() {
        XCTAssertEqual(
            AwaySummary.home(houseAlarm: "Disarm", issues: ["Garage Door is open"]),
            "At home, the house alarm is disarmed and Garage Door is open."
        )
        XCTAssertEqual(AwaySummary.home(houseAlarm: "Arm Away", issues: nil), "Couldn't check the house.")
        XCTAssertEqual(AwaySummary.home(houseAlarm: "Arm Away", issues: []), "Everything at home is good.")
    }

    func testNoAlarms() {
        let text = AwaySummary.text(alarms: [], temporary: [], weather: nil, houseAlarm: nil, homeIssues: [], signOff: "")
        XCTAssertEqual(text, "No alarms are set. Everything at home is good.")
    }

    func testWeatherUsesTheHighAndWorstDaytimeSky() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        let day = calendar.date(from: DateComponents(year: 2026, month: 10, day: 27))!
        let hours = [
            ForecastHour(start: day.addingTimeInterval(3 * 3600), condition: "snowy", temperature: -1),  // 3 AM: night
            ForecastHour(start: day.addingTimeInterval(9 * 3600), condition: "cloudy", temperature: 18),
            ForecastHour(start: day.addingTimeInterval(14 * 3600), condition: "rainy", temperature: 24),
        ]
        let weather = try XCTUnwrap(AwaySummary.weather(from: hours, wakeDay: day, today: day.addingTimeInterval(-86400), calendar: calendar))
        XCTAssertEqual(weather.condition, "rainy")
        XCTAssertEqual(weather.high, 24 * 9 / 5 + 32, accuracy: 0.01)
        XCTAssertEqual(AwaySummary.sentence(for: weather), "Tomorrow will be warm and rainy.")
    }
}
