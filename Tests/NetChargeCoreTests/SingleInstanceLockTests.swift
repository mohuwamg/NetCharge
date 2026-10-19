import XCTest
@testable import NetChargeCore

final class SingleInstanceLockTests: XCTestCase {
    func testOnlyOneLockCanBeHeldAndItIsReleasedOnExit() throws {
        let directory = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent(".build/single-instance-test-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let lockURL = directory.appendingPathComponent("instance.lock")

        var first: SingleInstanceLock? = try SingleInstanceLock(fileURL: lockURL)
        XCTAssertNotNil(first)
        XCTAssertThrowsError(try SingleInstanceLock(fileURL: lockURL)) { error in
            XCTAssertEqual(error as? SingleInstanceLock.LockError, .alreadyRunning)
        }

        first = nil
        XCTAssertNoThrow(try SingleInstanceLock(fileURL: lockURL))
    }
}
