import XCTest
@testable import GhostComplete

final class SkipRulesTests: XCTestCase {
    func testSkipsDenylistedApps() {
        XCTAssertEqual(
            SkipRules.shouldSkipApp(bundleId: "com.bitwarden.desktop", windowTitle: nil, denylist: ["com.bitwarden.desktop"]),
            .denylistedApp
        )
    }

    func testSkipsPrivateWindows() {
        XCTAssertEqual(
            SkipRules.shouldSkipApp(bundleId: "com.apple.Safari", windowTitle: "Private Browsing", denylist: []),
            .privateWindow
        )
    }

    func testAllowsEditableTextFields() {
        let metadata = ElementMetadata(
            role: "AXTextField",
            subrole: nil,
            title: nil,
            help: nil,
            description: nil,
            isEnabled: true,
            hasSelectedRange: true,
            hasStringValue: true
        )
        XCTAssertNil(SkipRules.shouldSkipElement(metadata))
    }

    func testSkipsPasswordFields() {
        let metadata = ElementMetadata(
            role: "AXTextField",
            subrole: nil,
            title: "Password",
            help: nil,
            description: nil,
            isEnabled: true,
            hasSelectedRange: true,
            hasStringValue: true
        )
        XCTAssertEqual(SkipRules.shouldSkipElement(metadata), .secureField)
    }
}
