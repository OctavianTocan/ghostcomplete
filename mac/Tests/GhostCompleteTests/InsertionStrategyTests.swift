import XCTest
@testable import GhostComplete

final class InsertionStrategyTests: XCTestCase {
    func testUsesPasteboardForFallbackApps() {
        XCTAssertEqual(
            InsertionStrategySelector.strategy(for: "com.tinyspeck.slackmacgap", fallbackBundleIds: ["com.tinyspeck.slackmacgap"]),
            .pasteboardFallback
        )
    }

    func testUsesSyntheticUnicodeByDefault() {
        XCTAssertEqual(
            InsertionStrategySelector.strategy(for: "com.apple.TextEdit", fallbackBundleIds: []),
            .syntheticUnicode
        )
    }
}
