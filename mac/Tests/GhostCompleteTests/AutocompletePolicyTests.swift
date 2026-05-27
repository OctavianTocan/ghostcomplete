import ApplicationServices
import XCTest
@testable import GhostComplete

final class AutocompletePolicyTests: XCTestCase {
    func testPrintableKeysScheduleAutocomplete() {
        XCTAssertTrue(AutocompletePolicy.shouldScheduleCompletion(keyCode: 0, flags: []))
        XCTAssertTrue(AutocompletePolicy.shouldScheduleCompletion(keyCode: 49, flags: []))
        XCTAssertTrue(AutocompletePolicy.shouldScheduleCompletion(keyCode: 43, flags: []))
    }

    func testNavigationEditShortcutsAndModifiersDoNotScheduleAutocomplete() {
        XCTAssertFalse(AutocompletePolicy.shouldScheduleCompletion(keyCode: 0, flags: .maskCommand))
        XCTAssertFalse(AutocompletePolicy.shouldScheduleCompletion(keyCode: 0, flags: .maskControl))
        XCTAssertFalse(AutocompletePolicy.shouldScheduleCompletion(keyCode: 48, flags: []))
        XCTAssertFalse(AutocompletePolicy.shouldScheduleCompletion(keyCode: 51, flags: []))
        XCTAssertFalse(AutocompletePolicy.shouldScheduleCompletion(keyCode: 36, flags: []))
        XCTAssertFalse(AutocompletePolicy.shouldScheduleCompletion(keyCode: 123, flags: []))
        XCTAssertFalse(AutocompletePolicy.shouldScheduleCompletion(keyCode: 56, flags: []))
    }

    func testPrefixGateUsesTrailingWhitespaceOnly() {
        XCTAssertFalse(AutocompletePolicy.hasEnoughVisiblePrefix("ab"))
        XCTAssertFalse(AutocompletePolicy.hasEnoughVisiblePrefix("ab   "))
        XCTAssertTrue(AutocompletePolicy.hasEnoughVisiblePrefix("abc"))
        XCTAssertTrue(AutocompletePolicy.hasEnoughVisiblePrefix("  abc   "))
    }

    func testRequestSignatureIncludesAppSelectionAndContextHash() {
        let snapshot = FocusSnapshot(
            context: "hello",
            caretRect: nil,
            elementRect: nil,
            anchorSource: "default",
            app: AppContext(bundleId: "com.apple.TextEdit", name: "TextEdit"),
            selection: SelectionRange(location: 5, length: 0)
        )

        let signature = AutocompletePolicy.requestSignature(for: snapshot)

        XCTAssertEqual(signature.appBundleId, "com.apple.TextEdit")
        XCTAssertEqual(signature.contextHash, "hello".ghostCompleteSHA256)
        XCTAssertEqual(signature.selectionLocation, 5)
        XCTAssertEqual(signature.selectionLength, 0)
    }
}
