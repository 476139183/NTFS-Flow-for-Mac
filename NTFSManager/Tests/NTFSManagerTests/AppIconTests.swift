import XCTest
import AppKit

final class AppIconTests: XCTestCase {
    func testPackagedIconCanBeDecodedByAppKit() throws {
        let project = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let url = project.appendingPathComponent("Resources/AppIcon.icns")
        let image = try XCTUnwrap(NSImage(contentsOf: url))
        XCTAssertTrue(image.isValid)
        XCTAssertGreaterThanOrEqual(image.representations.count, 1)
    }
}
