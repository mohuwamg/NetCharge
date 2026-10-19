import XCTest
@testable import NetChargeCore

final class NativeChargeControllerTests: XCTestCase {
    func testReadsSystemChargeLimitWhenAvailable() throws {
        guard let controller = NativeChargeController() else {
            throw XCTSkip("系统充电上限在这台机器上不可用")
        }
        let state = try controller.readState()
        XCTAssertEqual(state.backend, .native)
        XCTAssertTrue((80...100).contains(try XCTUnwrap(state.upperLimit)))
    }

    func testRejectsLimitBelowNativeMinimum() throws {
        guard let controller = NativeChargeController() else {
            throw XCTSkip("系统充电上限在这台机器上不可用")
        }
        let before = try controller.readState()
        XCTAssertThrowsError(try controller.setLimit(75))
        XCTAssertEqual(try controller.readState(), before)
    }

    func testChangesAndRestoresLimitOnOptInHardware() throws {
        guard ProcessInfo.processInfo.environment["NETCHARGE_TEST_NATIVE_WRITE"] == "1" else {
            throw XCTSkip("仅在明确启用硬件写入测试时运行")
        }
        let controller = try XCTUnwrap(NativeChargeController())
        let original = try controller.readState()
        guard original.active, original.upperLimit == 80 else {
            throw XCTSkip("写入测试只在当前上限为 80% 时运行")
        }
        defer { _ = try? controller.setLimit(80) }
        XCTAssertEqual(try controller.setLimit(85).upperLimit, 85)
        XCTAssertEqual(try controller.setLimit(80).upperLimit, 80)
        XCTAssertFalse(try controller.setLimit(100).active)
        XCTAssertEqual(try controller.setLimit(80).upperLimit, 80)
    }
}
