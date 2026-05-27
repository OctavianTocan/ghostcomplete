import ApplicationServices
import Foundation

struct PermissionRetryPolicy: Equatable {
    let delays: [TimeInterval]

    static let production = PermissionRetryPolicy(delays: [1, 2, 5, 10, 20, 30])

    var limit: Int {
        delays.count
    }

    func delay(forAttempt attempt: Int) -> TimeInterval? {
        guard attempt > 0, attempt <= delays.count else {
            return nil
        }
        return delays[attempt - 1]
    }
}

struct PermissionSnapshot: Equatable {
    let accessibilityTrusted: Bool?
    let inputMonitoringReady: Bool?
    let automaticRetryCount: Int
    let automaticRetryLimit: Int
    let inputMonitoringRetryExhausted: Bool
    let identity: AppIdentitySnapshot
}

@MainActor
final class PermissionCoordinator {
    typealias Handler = @MainActor (CGKeyCode, CGEventFlags) -> KeyDecision
    typealias SnapshotHandler = @MainActor (PermissionSnapshot) -> Void

    var onUpdate: SnapshotHandler?

    private let keyHandler: Handler
    private let retryPolicy: PermissionRetryPolicy
    private let identity = AppIdentity.current()

    private var keyMonitor: KeyMonitor?
    private var retryTimer: Timer?
    private var automaticRetryCount = 0
    private var retryExhaustionLogged = false
    private var accessibilityTrusted: Bool?
    private var inputMonitoringReady: Bool?
    private var lastPublishedSnapshot: PermissionSnapshot?

    init(
        retryPolicy: PermissionRetryPolicy = .production,
        keyHandler: @escaping Handler
    ) {
        self.retryPolicy = retryPolicy
        self.keyHandler = keyHandler
    }

    func start(promptForAccessibility: Bool) {
        TraceLogger.shared.info("permission_checks_started", fields: identity.traceFields)
        refresh(promptForAccessibility: promptForAccessibility, source: "launch")
    }

    func refresh(promptForAccessibility: Bool = false, source: String = "manual") {
        retryTimer?.invalidate()
        retryTimer = nil
        automaticRetryCount = 0
        retryExhaustionLogged = false
        runChecks(promptForAccessibility: promptForAccessibility, source: source, isAutomaticRetry: false)
    }

    func retryNow() {
        TraceLogger.shared.info("permission_manual_retry", fields: identity.traceFields)
        refresh(promptForAccessibility: false, source: "manual_retry")
    }

    func stop() {
        retryTimer?.invalidate()
        retryTimer = nil
        keyMonitor?.stop()
    }

    private func runChecks(promptForAccessibility: Bool, source: String, isAutomaticRetry: Bool) {
        accessibilityTrusted = checkAccessibility(prompt: promptForAccessibility, source: source)
        inputMonitoringReady = installKeyMonitor(source: source, isAutomaticRetry: isAutomaticRetry)
        publishSnapshot()
        scheduleInputMonitoringRetryIfNeeded(source: source)
    }

    private func checkAccessibility(prompt: Bool, source: String) -> Bool {
        let trusted: Bool
        if prompt {
            let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
            trusted = AXIsProcessTrustedWithOptions(options)
        } else {
            trusted = AXIsProcessTrusted()
        }

        var fields = identity.traceFields
        fields["trusted"] = trusted
        fields["prompt"] = prompt
        fields["source"] = source
        TraceLogger.shared.info("accessibility_trust_checked", fields: fields)
        return trusted
    }

    private func installKeyMonitor(source: String, isAutomaticRetry: Bool) -> Bool {
        if keyMonitor?.isRunning == true {
            return true
        }

        if keyMonitor == nil {
            keyMonitor = KeyMonitor(handler: keyHandler)
        }

        guard keyMonitor?.start() == true else {
            var fields = identity.traceFields
            fields["source"] = source
            fields["automaticRetry"] = isAutomaticRetry
            fields["retryCount"] = automaticRetryCount
            fields["retryLimit"] = retryPolicy.limit

            if isAutomaticRetry {
                TraceLogger.shared.debug("input_monitoring_event_tap_still_blocked", fields: fields)
            } else {
                TraceLogger.shared.warn("input_monitoring_event_tap_blocked", fields: fields)
            }
            return false
        }

        automaticRetryCount = 0
        retryExhaustionLogged = false
        retryTimer?.invalidate()
        retryTimer = nil

        var fields = identity.traceFields
        fields["source"] = source
        TraceLogger.shared.info("input_monitoring_event_tap_started", fields: fields)
        return true
    }

    private func scheduleInputMonitoringRetryIfNeeded(source: String) {
        guard inputMonitoringReady != true else {
            publishSnapshot()
            return
        }
        guard retryTimer == nil else {
            return
        }

        let nextAttempt = automaticRetryCount + 1
        guard let delay = retryPolicy.delay(forAttempt: nextAttempt) else {
            if !retryExhaustionLogged {
                var fields = identity.traceFields
                fields["source"] = source
                fields["retryCount"] = automaticRetryCount
                fields["retryLimit"] = retryPolicy.limit
                TraceLogger.shared.warn("input_monitoring_retry_exhausted", fields: fields)
                retryExhaustionLogged = true
            }
            publishSnapshot()
            return
        }

        automaticRetryCount = nextAttempt
        var fields = identity.traceFields
        fields["source"] = source
        fields["retryCount"] = automaticRetryCount
        fields["retryLimit"] = retryPolicy.limit
        fields["delaySeconds"] = delay
        TraceLogger.shared.info("input_monitoring_retry_scheduled", fields: fields)
        publishSnapshot()

        retryTimer = Timer.scheduledTimer(withTimeInterval: delay, repeats: false) { [weak self] _ in
            Task { @MainActor in
                guard let self else {
                    return
                }
                self.retryTimer = nil
                self.runChecks(
                    promptForAccessibility: false,
                    source: "automatic_retry",
                    isAutomaticRetry: true
                )
            }
        }
    }

    private func publishSnapshot() {
        let snapshot = PermissionSnapshot(
            accessibilityTrusted: accessibilityTrusted,
            inputMonitoringReady: inputMonitoringReady,
            automaticRetryCount: automaticRetryCount,
            automaticRetryLimit: retryPolicy.limit,
            inputMonitoringRetryExhausted: inputMonitoringReady == false && automaticRetryCount >= retryPolicy.limit,
            identity: identity
        )

        onUpdate?(snapshot)
        guard snapshot != lastPublishedSnapshot else {
            return
        }

        var fields = identity.traceFields
        fields["accessibilityTrusted"] = accessibilityTrusted ?? false
        fields["inputMonitoringReady"] = inputMonitoringReady ?? false
        fields["automaticRetryCount"] = automaticRetryCount
        fields["automaticRetryLimit"] = retryPolicy.limit
        fields["inputMonitoringRetryExhausted"] = snapshot.inputMonitoringRetryExhausted
        TraceLogger.shared.info("permission_snapshot_updated", fields: fields)
        lastPublishedSnapshot = snapshot
    }
}
