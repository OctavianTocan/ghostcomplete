import XCTest
@testable import GhostComplete

final class CoordinateConverterTests: XCTestCase {
    func testOverlayOriginUsesCaretEnd() {
        let origin = CoordinateConverter.overlayOrigin(
            caretRect: CGRect(x: 20, y: 30, width: 2, height: 18),
            fallbackElementRect: nil
        )
        XCTAssertEqual(origin, CGPoint(x: 24, y: 28))
    }

    func testOverlayOriginFallsBackToElement() {
        let origin = CoordinateConverter.overlayOrigin(
            caretRect: nil,
            fallbackElementRect: CGRect(x: 40, y: 100, width: 300, height: 24)
        )
        XCTAssertEqual(origin, CGPoint(x: 44, y: 74))
    }
}
