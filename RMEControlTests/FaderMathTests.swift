import XCTest
@testable import RME_Control

final class FaderMathTests: XCTestCase {
    func testEndpoints() {
        XCTAssertEqual(FaderMath.db(for: 0), -65, accuracy: 0.001)
        XCTAssertEqual(FaderMath.db(for: 1), 6, accuracy: 0.001)
        XCTAssertEqual(FaderMath.position(forDB: -65), 0, accuracy: 0.001)
        XCTAssertEqual(FaderMath.position(forDB: 6), 1, accuracy: 0.001)
    }

    func testMonotonicIncreasing() {
        var prev = -Double.infinity
        for i in stride(from: 0.0, through: 1.0, by: 0.01) {
            let db = FaderMath.db(for: i)
            XCTAssertGreaterThanOrEqual(db, prev)
            prev = db
        }
    }

    func testClamps() {
        XCTAssertEqual(FaderMath.db(for: -5), FaderMath.db(for: 0))
        XCTAssertEqual(FaderMath.db(for: 50), FaderMath.db(for: 1))
        XCTAssertEqual(FaderMath.position(forDB: -1000), 0)
        XCTAssertEqual(FaderMath.position(forDB: 1000), 1)
    }

    func testRoundTripAtTablePoints() {
        for point in FaderMath.curve {
            let position = FaderMath.position(forDB: point.1)
            XCTAssertEqual(position, point.0, accuracy: 0.01)
        }
    }
}
