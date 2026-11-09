import XCTest
@testable import NTFSManager

final class DiskScanTests: XCTestCase {
    func testMalformedDiskListIsAnErrorRatherThanAnEmptyDiskList() throws {
        XCTAssertThrowsError(try DiskService.decodeDiskList(Data("not a plist".utf8)))
    }

    func testEmptyValidListIsNotAnError() throws {
        let data = try PropertyListSerialization.data(fromPropertyList: ["AllDisksAndPartitions": []],
                                                      format: .xml, options: 0)
        XCTAssertTrue(try DiskService.decodeDiskList(data).isEmpty)
    }

    func testMissingDiskListKeyIsAnError() throws {
        let data = try PropertyListSerialization.data(fromPropertyList: ["Unexpected": []],
                                                      format: .xml, options: 0)
        XCTAssertThrowsError(try DiskService.decodeDiskList(data))
    }

    func testMountTableDistinguishesRootFromAnOrdinaryPath() {
        XCTAssertTrue(DiskService.isMountPoint("/"))
        XCTAssertFalse(DiskService.isMountPoint("/a-nonexistent-ntfs-mount"))
    }

    func testCapacityComesFromCachedMountMetadata() throws {
        let capacity = try XCTUnwrap(DiskService.cachedCapacity("/"))
        XCTAssertGreaterThan(capacity.total, 0)
        XCTAssertGreaterThanOrEqual(capacity.free, 0)
        XCTAssertNil(DiskService.cachedCapacity("/a-nonexistent-ntfs-mount"))
    }
}
