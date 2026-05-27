import XCTest
@testable import GhostComplete

final class CoordinateConverterTests: XCTestCase {
    func testOverlayOriginUsesCaretStart() {
        let origin = CoordinateConverter.overlayOrigin(
            caretRect: CGRect(x: 20, y: 30, width: 2, height: 18),
            fallbackElementRect: nil,
            panelHeight: 24
        )
        XCTAssertEqual(origin, CGPoint(x: 20, y: 27))
    }

    func testOverlayOriginFallsBackToElement() {
        let origin = CoordinateConverter.overlayOrigin(
            caretRect: nil,
            fallbackElementRect: CGRect(x: 40, y: 100, width: 300, height: 24),
            panelHeight: 24
        )
        XCTAssertEqual(origin, CGPoint(x: 46, y: 100))
    }
}
