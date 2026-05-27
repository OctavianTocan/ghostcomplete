import XCTest
@testable import GhostComplete

final class GhostTextSegmenterTests: XCTestCase {
    func testSplitsLeadingSpaceAndFirstWord() {
        let split = GhostTextSegmenter.splitFirstWord(from: " world again")
        XCTAssertEqual(split.accepted, " world")
        XCTAssertEqual(split.remaining, " again")
    }

    func testCompletesMidWordFirst() {
        let split = GhostTextSegmenter.splitFirstWord(from: "ing the sentence")
        XCTAssertEqual(split.accepted, "ing")
        XCTAssertEqual(split.remaining, " the sentence")
    }

    func testAcceptsSingleWordSuggestion() {
        let split = GhostTextSegmenter.splitFirstWord(from: " done")
        XCTAssertEqual(split.accepted, " done")
        XCTAssertEqual(split.remaining, "")
    }
}
