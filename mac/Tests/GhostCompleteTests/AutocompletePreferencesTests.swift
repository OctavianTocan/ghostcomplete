import XCTest
@testable import GhostComplete

final class AutocompletePreferencesTests: XCTestCase {
    func testDefaultDebounceIsResponsiveButStillTrailing() {
        let preferences = AutocompletePreferences.default
        XCTAssertEqual(preferences.debounceMs, 120)
        XCTAssertFalse(preferences.rawTextLoggingEnabled)
        XCTAssertLessThan(preferences.delay(for: 49), preferences.debounceDelay)
    }

    func testSanitizesTunableRanges() {
        let preferences = AutocompletePreferences(
            debounceMs: 1,
            revealAnimationEnabled: true,
            revealStepMs: 500,
            overlayNudgeX: 200,
            overlayNudgeY: -200,
            rawTextLoggingEnabled: true
        ).sanitized()

        XCTAssertEqual(preferences.debounceMs, 60)
        XCTAssertEqual(preferences.revealStepMs, 120)
        XCTAssertEqual(preferences.overlayNudgeX, 40)
        XCTAssertEqual(preferences.overlayNudgeY, -40)
        XCTAssertTrue(preferences.rawTextLoggingEnabled)
    }
}
