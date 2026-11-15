import XCTest
@testable import RME_Control

@MainActor
final class OSCMonitorTests: XCTestCase {
    func testRecordingIsDisabledUntilEnabled() {
        let monitor = OSCMonitor()
        monitor.record(OSCActivity(direction: .incoming, address: "/output/0/volume", floatValue: -6))
        XCTAssertTrue(monitor.activities.isEmpty)

        monitor.isEnabled = true
        monitor.record(OSCActivity(direction: .incoming, address: "/output/0/volume", floatValue: -6))
        XCTAssertEqual(monitor.activities.map(\.address), ["/output/0/volume"])

        monitor.clear()
        XCTAssertTrue(monitor.activities.isEmpty)
    }

    func testHistoryKeepsOnlyLatestEntries() {
        let monitor = OSCMonitor()
        monitor.isEnabled = true
        for index in 0..<510 {
            monitor.record(OSCActivity(direction: .outgoing, address: "/test/\(index)", floatValue: Float(index)))
        }
        XCTAssertEqual(monitor.activities.count, 500)
        XCTAssertEqual(monitor.activities.first?.address, "/test/10")
        XCTAssertEqual(monitor.activities.last?.address, "/test/509")
    }

    func testActivityFormatsFloatAndStringValues() {
        let float = OSCActivity(direction: .outgoing, address: "/output/0/volume", floatValue: -6.125)
        XCTAssertEqual(float.value, "-6.125")

        let whole = OSCActivity(direction: .incoming, address: "/controlroom/dim", floatValue: 1)
        XCTAssertEqual(whole.value, "1")

        let string = OSCActivity(direction: .incoming, address: "/status/device", stringValue: "Fireface 802")
        XCTAssertEqual(string.value, "Fireface 802")
    }
}
