import XCTest
@testable import NTFSManager

final class DiskOperationTests: XCTestCase {
    func testPartitionsOfSameDiskShareAnOperationLock() {
        var coordinator = DiskOperationCoordinator()
        XCTAssertTrue(coordinator.begin("disk6"))
        XCTAssertFalse(coordinator.begin("disk6"))
        XCTAssertTrue(coordinator.begin("disk7"))
        coordinator.finish("disk6")
        XCTAssertTrue(coordinator.begin("disk6"))
    }
}
