import XCTest
@testable import BedtimeBridge

final class DriveTimeComparisonTests: XCTestCase {
    private let answers: [DriveEstimate.Service: TimeInterval] = [
        .apple: 28 * 60, .tomTom: 30 * 60, .googleTypical: 29 * 60, .googleWorst: 41 * 60,
    ]

    func testChosenServiceIsUsed() {
        XCTAssertEqual(DriveTimeComparison.choose(from: answers, source: .apple, googlePessimistic: false)?.seconds, 28 * 60)
        XCTAssertEqual(DriveTimeComparison.choose(from: answers, source: .tomTom, googlePessimistic: false)?.seconds, 30 * 60)
    }

    func testGoogleModePicksTypicalOrWorstCase() {
        XCTAssertEqual(DriveTimeComparison.choose(from: answers, source: .google, googlePessimistic: false)?.service, .googleTypical)
        XCTAssertEqual(DriveTimeComparison.choose(from: answers, source: .google, googlePessimistic: true)?.service, .googleWorst)
    }

    func testLongestUsesGoogleModeSetting() {
        // Typical Google: TomTom's 30 beats Apple 28 and Google 29; the worst case doesn't count.
        XCTAssertEqual(DriveTimeComparison.choose(from: answers, source: .longest, googlePessimistic: false)?.service, .tomTom)
        XCTAssertEqual(DriveTimeComparison.choose(from: answers, source: .longest, googlePessimistic: true)?.service, .googleWorst)
    }

    func testLongestSkipsServicesWithoutAnAnswer() {
        let appleOnly: [DriveEstimate.Service: TimeInterval] = [.apple: 28 * 60]
        XCTAssertEqual(DriveTimeComparison.choose(from: appleOnly, source: .longest, googlePessimistic: false)?.service, .apple)
        XCTAssertNil(DriveTimeComparison.choose(from: appleOnly, source: .google, googlePessimistic: false))
    }
}
