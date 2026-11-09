import XCTest
@testable import NTFSManager

final class DiskErrorTests: XCTestCase {
    func testPermissionDenialTakesPriorityOverGenericWindowsAdvice() {
        let raw = """
        Error opening '/dev/disk6s1': Operation not permitted
        The NTFS partition is in an unsafe state. Please resume and shutdown
        Windows fully (no hibernation or fast restarting), or mount the volume read-only.
        """
        let error = DiskService.explain(ShellError.failed(raw))
        XCTAssertFalse(error is HibernatedError)
        XCTAssertTrue(error.localizedDescription.contains("完全磁盘访问"))
    }

    func testGenericUnsafeStateDoesNotOfferDeletionOfHibernationFile() {
        let error = DiskService.explain(ShellError.failed(
            "The NTFS partition is in an unsafe state. Windows fully (no hibernation or fast restarting)"))
        XCTAssertFalse(error is HibernatedError)
    }

    func testDirtyVolumeDoesNotImplyHibernation() {
        XCTAssertFalse(DiskService.explain(ShellError.failed("Volume is unclean")) is HibernatedError)
    }

    func testExplicitHibernationCanOfferRecoveryChoice() {
        XCTAssertTrue(DiskService.explain(ShellError.failed("Windows is hibernated, refused to mount.")) is HibernatedError)
    }

    func testCancellationIsPreserved() {
        guard case ShellError.cancelled = DiskService.explain(ShellError.cancelled) else {
            return XCTFail("取消授权不应变成挂载故障")
        }
    }
}
