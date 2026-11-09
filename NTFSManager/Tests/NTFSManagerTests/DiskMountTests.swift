import XCTest
@testable import NTFSManager

final class DiskMountTests: XCTestCase {
    private let label = "段雨田文档"

    func testRecognizesExistingFuseMountAlongsideSystemReadOnlyMount() {
        let mounts = [
            MountedVolume(path: "/Volumes/段雨田文档", source: "fuse-t:/段雨田文档", type: "nfs", readOnly: false),
            MountedVolume(path: "/Volumes/段雨田文档 1", source: "/dev/disk6s1", type: "ntfs", readOnly: true)
        ]
        XCTAssertEqual(DiskMountResolver.existingMount(device: "/dev/disk6s1", label: label,
            labelIsUnique: true, processOutput: "", mounts: mounts), "/Volumes/段雨田文档")
    }

    func testDoesNotGuessForTwoDisksWithTheSameLabel() {
        let mounts = [MountedVolume(path: "/Volumes/段雨田文档", source: "fuse-t:/段雨田文档", type: "nfs", readOnly: false)]
        XCTAssertNil(DiskMountResolver.existingMount(device: "/dev/disk6s1", label: label,
            labelIsUnique: false, processOutput: "", mounts: mounts))
    }

    func testProcessOptionsBeforeMountPathAreSupported() {
        let mounts = [MountedVolume(path: "/Volumes/My disk", source: "fuse-t:/My disk", type: "nfs", readOnly: false)]
        XCTAssertEqual(DiskMountResolver.existingMount(device: "/dev/disk6s1", label: "My disk",
            labelIsUnique: false, processOutput: "/usr/local/bin/ntfs-3g -o local /dev/disk6s1 -o allow_other /Volumes/My disk",
            mounts: mounts), "/Volumes/My disk")
    }

    func testDeviceAndPathMustMatchExactly() {
        let mounts = [MountedVolume(path: "/Volumes/My disk", source: "fuse-t:/My disk", type: "nfs", readOnly: false)]
        XCTAssertNil(DiskMountResolver.existingMount(device: "/dev/disk6s1", label: "My disk",
            labelIsUnique: false, processOutput: "/usr/local/bin/ntfs-3g /dev/disk6s10 /Volumes/My disk", mounts: mounts))
        XCTAssertNil(DiskMountResolver.existingMount(device: "/dev/disk6s1", label: "My disk",
            labelIsUnique: false, processOutput: "/usr/local/bin/ntfs-3g /dev/disk6s1 /Volumes/My disk 1", mounts: mounts))
    }

    func testReadOnlyFuseMountIsNotReportedAsWritable() {
        let mounts = [MountedVolume(path: "/Volumes/My disk", source: "fuse-t:/My disk", type: "nfs", readOnly: true)]
        XCTAssertNil(DiskMountResolver.existingMount(device: "/dev/disk6s1", label: "My disk",
            labelIsUnique: true, processOutput: "", mounts: mounts))
    }
}
