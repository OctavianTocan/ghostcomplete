import XCTest
@testable import GhostComplete

final class DebouncerTests: XCTestCase {
    func testOnlyLatestScheduledActionRuns() {
        let queue = DispatchQueue(label: "debouncer-test")
        let debouncer = Debouncer(delay: 0.02, queue: queue)
        let expectation = XCTestExpectation(description: "latest action")
        var values: [Int] = []

        debouncer.schedule { values.append(1) }
        debouncer.schedule {
            values.append(2)
            expectation.fulfill()
        }

        wait(for: [expectation], timeout: 1.0)
        queue.sync {}
        XCTAssertEqual(values, [2])
    }
}
