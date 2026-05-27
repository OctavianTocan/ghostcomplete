import XCTest
@testable import GhostComplete

final class PermissionCoordinatorTests: XCTestCase {
    func testRetryPolicyReturnsBoundedDelays() {
        let policy = PermissionRetryPolicy(delays: [0.5, 1.5])

        XCTAssertEqual(policy.delay(forAttempt: 1), 0.5)
        XCTAssertEqual(policy.delay(forAttempt: 2), 1.5)
        XCTAssertNil(policy.delay(forAttempt: 0))
        XCTAssertNil(policy.delay(forAttempt: 3))
    }

    func testPermissionSnapshotMarksInputMonitoringExhausted() {
        let identity = AppIdentitySnapshot(
            bundleId: "dev.octavian.GhostComplete",
            bundlePath: "/Applications/GhostComplete.app",
            executablePath: "/Applications/GhostComplete.app/Contents/MacOS/GhostComplete",
            designatedRequirement: "identifier \"dev.octavian.GhostComplete\""
        )
        let snapshot = PermissionSnapshot(
            accessibilityTrusted: true,
            inputMonitoringReady: false,
            automaticRetryCount: 2,
            automaticRetryLimit: 2,
            inputMonitoringRetryExhausted: true,
            identity: identity
        )

        XCTAssertTrue(snapshot.inputMonitoringRetryExhausted)
    }
}
