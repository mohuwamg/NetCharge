import XCTest
@testable import NetChargeCore

final class ChargeControllerTests: XCTestCase {
    private final class FakeSMC: SMCTransport {
        var values: [String: [UInt8]] = [
            "bfF0": [2], "bfD0": [80, 0, 0, 0], "bfE0": [78, 0, 0, 0]
        ]
        var writes: [String] = []

        func read(_ key: String) throws -> [UInt8] { values[key] ?? [] }
        func write(_ key: String, bytes: [UInt8]) throws {
            writes.append(key)
            values[key] = bytes
        }
    }

    func testChangingLimitUsesFirmwareOrderAndVerifiesResult() throws {
        let fake = FakeSMC()
        let state = try ChargeController(smc: fake).setLimit(90)
        XCTAssertEqual(fake.writes, ["bfF0", "bfD0", "bfE0", "bfF0"])
        XCTAssertEqual(state.upperLimit, 90)
        XCTAssertEqual(state.lowerLimit, 88)
        XCTAssertTrue(state.active)
    }

    func testOneHundredDisablesLimit() throws {
        let fake = FakeSMC()
        let state = try ChargeController(smc: fake).setLimit(100)
        XCTAssertEqual(fake.writes, ["bfF0"])
        XCTAssertFalse(state.active)
    }

    func testSameLimitDoesNotWriteAgain() throws {
        let fake = FakeSMC()
        _ = try ChargeController(smc: fake).setLimit(80)
        XCTAssertTrue(fake.writes.isEmpty)
    }

    func testInvalidFirmwareStateDoesNotWrite() {
        let fake = FakeSMC()
        fake.values["bfF0"] = [1]
        XCTAssertThrowsError(try ChargeController(smc: fake).setLimit(90))
        XCTAssertTrue(fake.writes.isEmpty)
    }
}
