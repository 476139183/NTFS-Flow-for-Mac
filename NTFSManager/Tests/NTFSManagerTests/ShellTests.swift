import XCTest
@testable import NTFSManager

final class ShellTests: XCTestCase {
    func testReadCommandTimeoutIsBounded() {
        let start = Date()
        let result = Shell.run("/bin/sleep", ["10"], timeout: 0.1)
        XCTAssertFalse(result.ok)
        XCTAssertTrue(result.output.contains("超时"))
        XCTAssertLessThan(Date().timeIntervalSince(start), 3)
    }

    func testReturnsWithoutWaitingForBackgroundChildToCloseOutput() {
        let start = Date()
        let result = Shell.run("/bin/sh", ["-c", "sleep 2 & printf ready"])
        XCTAssertTrue(result.ok)
        XCTAssertEqual(result.output, "ready")
        XCTAssertLessThan(Date().timeIntervalSince(start), 1.5)
    }

    func testCapturesBothOutputStreamsAndExitStatus() {
        let result = Shell.run("/bin/sh", ["-c", "printf out; printf err >&2; exit 7"])
        XCTAssertEqual(result.status, 7)
        XCTAssertEqual(result.output, "outerr")
    }

    func testPreservesBinaryOutput() {
        XCTAssertEqual(Shell.runData("/usr/bin/printf", ["hello"]), Data("hello".utf8))
    }
}
