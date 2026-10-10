import XCTest
@testable import NetChargeCore

final class NetworkMonitorTests: XCTestCase {
    func testReadsCurrentInterfaceCounters() throws {
        let monitor = NetworkMonitor()
        let first = try XCTUnwrap(monitor.sample())
        XCTAssertFalse(first.interface.isEmpty)
        Thread.sleep(forTimeInterval: 0.1)
        let second = try XCTUnwrap(monitor.sample())
        XCTAssertEqual(second.interface, first.interface)
        XCTAssertGreaterThanOrEqual(second.downloadBytesPerSecond, 0)
        XCTAssertGreaterThanOrEqual(second.uploadBytesPerSecond, 0)
    }
}
