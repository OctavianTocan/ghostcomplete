import XCTest
@testable import GhostComplete

final class SidecarRequestHandleTests: XCTestCase {
    func testCancelRunsOnlyOnce() {
        var cancelCount = 0
        let handle = SidecarRequestHandle {
            cancelCount += 1
        }

        handle.cancel()
        handle.cancel()

        XCTAssertTrue(handle.isCancelled)
        XCTAssertEqual(cancelCount, 1)
    }
}
