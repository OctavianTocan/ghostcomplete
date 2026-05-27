import ApplicationServices
import AppKit
import Foundation

@MainActor
final class CompletionCoordinator {
    private let settings: SettingsStore
    private let reader: AccessibilityReader
    private let insertion: InsertionController
    private let sidecar: SidecarClient
    private let overlay: OverlayPanel
    private let debouncer: Debouncer

    private var latestRequestId: String?
    private var activeSnapshot: FocusSnapshot?
    private var sidecarStartInFlight = false
    private var completionBackoffUntil: Date?
    private var activeCompletionRequest: SidecarRequestHandle?
    private var lastRequestedSignature: CompletionRequestSignature?
    var onCompletionStatus: ((CompletionStatusSnapshot) -> Void)?

    init(
        settings: SettingsStore,
        reader: AccessibilityReader = AccessibilityReader(),
        insertion: InsertionController = InsertionController(),
        overlay: OverlayPanel = OverlayPanel(),
        debouncer: Debouncer = Debouncer(delay: AutocompletePolicy.debounceDelay)
    ) {
        self.settings = settings
        self.reader = reader
        self.insertion = insertion
        self.overlay = overlay
        self.debouncer = debouncer
        self.sidecar = SidecarClient(settings: settings)
    }

    func startSidecarAsync(onStatus: (@MainActor (Bool) -> Void)? = nil) {
        if sidecar.isReady {
            onStatus?(true)
            return
        }
        guard !sidecarStartInFlight else {
            TraceLogger.shared.info("sidecar_start_already_in_flight")
            return
        }

        sidecarStartInFlight = true
        let envKey = ProcessInfo.processInfo.environment["AI_GATEWAY_API_KEY"]
        TraceLogger.shared.info("sidecar_start_requested", fields: [
            "hasEnvKey": envKey?.isEmpty == false
        ])

        if let envKey, !envKey.isEmpty {
            seedKeychainFromEnvironment(envKey)
            TraceLogger.shared.info("api_key_resolution_finished", fields: [
                "hasKeychainKey": false,
                "hasEnvKey": true,
                "hasApiKey": true,
                "keychainSkipped": true
            ])
            let ready = startSidecar(apiKey: envKey)
            sidecarStartInFlight = false
            onStatus?(ready)
            return
        }

        DispatchQueue.global(qos: .utility).async {
            TraceLogger.shared.info("api_key_resolution_started")
            let backgroundKeychain = KeychainStore()
            let keychainKey = backgroundKeychain.string(account: KeychainStore.gatewayAccount)
            let apiKey = keychainKey

            TraceLogger.shared.info("api_key_resolution_finished", fields: [
                "hasKeychainKey": keychainKey != nil,
                "hasEnvKey": false,
                "hasApiKey": apiKey?.isEmpty == false
            ])

            Task { @MainActor [weak self] in
                guard let self else {
                    return
                }
                let ready = self.startSidecar(apiKey: apiKey)
                self.sidecarStartInFlight = false
                onStatus?(ready)
            }
        }
    }

    private func seedKeychainFromEnvironment(_ key: String) {
        let sidecarSettingsURL = settings.sidecarSettingsURL
        DispatchQueue.global(qos: .utility).async {
            do {
                try KeychainStore().setString(key, account: KeychainStore.gatewayAccount)
                let runtimeSettings = SidecarRuntimeSettings.fromEnvironment()
                if !runtimeSettings.isEmpty {
                    try runtimeSettings.write(to: sidecarSettingsURL)
                    TraceLogger.shared.info("sidecar_runtime_settings_saved", fields: runtimeSettings.traceFields)
                }
                TraceLogger.shared.info("api_key_seeded_to_keychain", fields: [
                    "service": KeychainStore.gatewayService,
                    "account": KeychainStore.gatewayAccount,
                    "source": "environment"
                ])
            } catch {
                TraceLogger.shared.error("api_key_keychain_seed_failed", fields: [
                    "error": error.localizedDescription
                ])
            }
        }
    }

    @discardableResult
    private func startSidecar(apiKey: String?) -> Bool {
        TraceLogger.shared.info("sidecar_launch_requested", fields: [
            "hasApiKey": apiKey?.isEmpty == false
        ])
        do {
            try sidecar.start(apiKey: apiKey)
            TraceLogger.shared.info("sidecar_start_succeeded")
            return true
        } catch {
            TraceLogger.shared.error("sidecar_start_failed", fields: ["error": error.localizedDescription])
            NSLog("[GhostComplete] Sidecar launch failed: \(error.localizedDescription)")
            return false
        }
    }

    func stopSidecar() {
        TraceLogger.shared.info("sidecar_stop_requested")
        cancelPendingCompletion(reason: "sidecar_stop")
        sidecar.stop()
    }

    func restartSidecarAsync(onStatus: (@MainActor (Bool) -> Void)? = nil) {
        TraceLogger.shared.info("sidecar_restart_requested")
        cancelPendingCompletion(reason: "sidecar_restart")
        sidecar.stop()
        startSidecarAsync(onStatus: onStatus)
    }

    func handleKey(_ keyCode: CGKeyCode, flags: CGEventFlags) -> KeyDecision {
        if flags.contains(.maskCommand) || flags.contains(.maskControl) {
            cancelPendingCompletion(reason: "shortcut")
            dismissSuggestion()
            return .pass
        }

        switch keyCode {
        case 48:
            if overlay.isVisible {
                TraceLogger.shared.info("key_accept_suggestion")
                acceptSuggestion()
                return .swallow
            }
            cancelPendingCompletion(reason: "tab")
            dismissSuggestion()
            return .pass
        case 53:
            cancelPendingCompletion(reason: "escape")
            dismissSuggestion()
            if overlay.isVisible {
                TraceLogger.shared.info("key_dismiss_suggestion")
                return .swallow
            }
            return .pass
        case 36, 51, 117, 123, 124, 125, 126:
            TraceLogger.shared.debug("completion_debounce_suppressed", fields: [
                "reason": "navigation_or_edit",
                "keyCode": Int(keyCode)
            ])
            cancelPendingCompletion(reason: "navigation_or_edit")
            dismissSuggestion()
            return .pass
        default:
            guard AutocompletePolicy.shouldScheduleCompletion(keyCode: keyCode, flags: flags) else {
                TraceLogger.shared.debug("completion_debounce_suppressed", fields: [
                    "reason": "non_text_key",
                    "keyCode": Int(keyCode)
                ])
                cancelPendingCompletion(reason: "non_text_key")
                dismissSuggestion()
                return .pass
            }
            cancelPendingCompletion(reason: "typing")
            dismissSuggestion()
            scheduleCompletion()
        }

        return .pass
    }

    private func scheduleCompletion() {
        debouncer.schedule { [weak self] in
            self?.requestCompletion()
        }
    }

    private func requestCompletion() {
        if let completionBackoffUntil, completionBackoffUntil > Date() {
            let retryAfterMs = Int(completionBackoffUntil.timeIntervalSinceNow * 1000)
            updateCompletionStatus(
                label: "Backoff \(max(retryAfterMs / 1000, 1))s",
                isHealthy: false,
                detail: "Waiting before retrying after the previous completion failure."
            )
            TraceLogger.shared.warn("completion_suppressed_by_backoff", fields: [
                "retryAfterMs": retryAfterMs
            ])
            return
        }

        guard sidecar.isReady else {
            updateCompletionStatus(label: "Sidecar not ready", isHealthy: false, detail: nil)
            TraceLogger.shared.warn("completion_sidecar_not_ready")
            startSidecarAsync()
            return
        }

        guard let snapshot = reader.focusedSnapshot(settings: settings) else {
            updateCompletionStatus(label: "No editable focus", isHealthy: nil, detail: nil)
            TraceLogger.shared.debug("completion_focus_snapshot_unavailable")
            return
        }

        guard AutocompletePolicy.hasEnoughVisiblePrefix(snapshot.context) else {
            updateCompletionStatus(label: "Waiting for more text", isHealthy: nil, detail: nil)
            TraceLogger.shared.debug("completion_context_too_short", fields: [
                "contextLength": snapshot.context.count,
                "minPrefixCharacters": AutocompletePolicy.minPrefixCharacters,
                "appBundleId": snapshot.app.bundleId,
                "appName": snapshot.app.name
            ])
            return
        }

        let signature = AutocompletePolicy.requestSignature(for: snapshot)
        guard signature != lastRequestedSignature else {
            updateCompletionStatus(label: "Context unchanged", isHealthy: nil, detail: nil)
            TraceLogger.shared.debug("completion_duplicate_context_suppressed", fields: [
                "contextHash": snapshot.context.ghostCompleteSHA256,
                "appBundleId": snapshot.app.bundleId,
                "selectionLocation": snapshot.selection?.location ?? -1,
                "selectionLength": snapshot.selection?.length ?? -1
            ])
            return
        }

        let requestId = UUID().uuidString
        latestRequestId = requestId
        activeSnapshot = snapshot
        lastRequestedSignature = signature
        updateCompletionStatus(label: "Requesting", isHealthy: nil, detail: nil)
        TraceLogger.shared.info("completion_request_started", fields: [
            "requestId": requestId,
            "appBundleId": snapshot.app.bundleId,
            "appName": snapshot.app.name,
            "contextLength": snapshot.context.count,
            "contextHash": snapshot.context.ghostCompleteSHA256,
            "anchorSource": snapshot.anchorSource,
            "hasCaretRect": snapshot.caretRect != nil,
            "hasElementRect": snapshot.elementRect != nil,
            "caretX": snapshot.caretRect.map { Int($0.origin.x) } ?? -1,
            "caretY": snapshot.caretRect.map { Int($0.origin.y) } ?? -1,
            "caretHeight": snapshot.caretRect.map { Int($0.height) } ?? -1,
            "elementX": snapshot.elementRect.map { Int($0.origin.x) } ?? -1,
            "elementY": snapshot.elementRect.map { Int($0.origin.y) } ?? -1,
            "elementHeight": snapshot.elementRect.map { Int($0.height) } ?? -1,
            "selectionLocation": snapshot.selection?.location ?? -1,
            "selectionLength": snapshot.selection?.length ?? -1
        ])

        activeCompletionRequest = sidecar.complete(snapshot: snapshot, requestId: requestId) { [weak self] result in
            Task { @MainActor [weak self] in
                self?.handleCompletionResult(result, requestId: requestId, snapshot: snapshot)
            }
        }
    }

    private func handleCompletionResult(_ result: Result<CompleteResponse, Error>, requestId: String, snapshot: FocusSnapshot) {
        guard latestRequestId == requestId else {
            TraceLogger.shared.debug("completion_response_stale", fields: [
                "requestId": requestId,
                "reason": "latest_request_changed"
            ])
            return
        }
        activeCompletionRequest = nil

        switch result {
        case .success(let response):
            let text = response.completion
            let visibleText = text.trimmingCharacters(in: .whitespacesAndNewlines)
            if visibleText.count >= 2 {
                TraceLogger.shared.info("completion_response_shown", fields: [
                    "requestId": requestId,
                    "model": response.model,
                    "latencyMs": response.latencyMs,
                    "completionLength": text.count,
                    "completionHash": text.ghostCompleteSHA256
                ])
                updateCompletionStatus(
                    label: "Shown (\(visibleText.count) chars)",
                    isHealthy: true,
                    detail: "Model \(response.model) returned an overlay suggestion."
                )
                overlay.show(
                    text: text,
                    near: snapshot.caretRect,
                    anchorSource: snapshot.anchorSource,
                    fallbackElementRect: snapshot.elementRect
                )
            } else {
                TraceLogger.shared.info("completion_response_empty", fields: [
                    "requestId": requestId,
                    "model": response.model,
                    "latencyMs": response.latencyMs,
                    "completionLength": text.count,
                    "visibleLength": visibleText.count,
                    "completionHash": text.ghostCompleteSHA256
                ])
                updateCompletionStatus(
                    label: "Empty suggestion",
                    isHealthy: false,
                    detail: "Model \(response.model) returned \(text.count) characters, \(visibleText.count) visible."
                )
            }
            completionBackoffUntil = nil
        case .failure(let error):
            if isCancellation(error) {
                TraceLogger.shared.info("completion_request_cancelled", fields: ["requestId": requestId])
                updateCompletionStatus(label: "Cancelled", isHealthy: nil, detail: nil)
                return
            }
            completionBackoffUntil = Date().addingTimeInterval(30)
            let detail = error.localizedDescription
            updateCompletionStatus(
                label: friendlyFailureLabel(detail),
                isHealthy: false,
                detail: detail
            )
            TraceLogger.shared.error("completion_request_failed", fields: [
                "requestId": requestId,
                "error": error.localizedDescription,
                "backoffSeconds": 30
            ])
            NSLog("[GhostComplete] Completion failed: \(error.localizedDescription)")
        }
    }

    private func cancelPendingCompletion(reason: String) {
        debouncer.cancel()
        if let activeCompletionRequest {
            TraceLogger.shared.info("completion_request_cancelled", fields: ["reason": reason])
            activeCompletionRequest.cancel()
            self.activeCompletionRequest = nil
            latestRequestId = nil
        }
    }

    private func isCancellation(_ error: Error) -> Bool {
        if let sidecarError = error as? SidecarError,
           case .cancelled = sidecarError {
            return true
        }
        let nsError = error as NSError
        return nsError.domain == NSURLErrorDomain && nsError.code == NSURLErrorCancelled
    }

    private func updateCompletionStatus(label: String, isHealthy: Bool?, detail: String?) {
        let status = CompletionStatusSnapshot(label: label, isHealthy: isHealthy, detail: detail)
        TraceLogger.shared.debug("completion_status_updated", fields: [
            "label": label,
            "isHealthy": isHealthy.map(String.init(describing:)) ?? "unknown"
        ])
        onCompletionStatus?(status)
    }

    private func friendlyFailureLabel(_ message: String) -> String {
        let lower = message.lowercased()
        if lower.contains("rate-limit") || lower.contains("rate limit") || lower.contains("rate_limited") {
            return "Rate limited"
        }
        if lower.contains("restricted model") || lower.contains("access to this model") || lower.contains("model access") {
            return "Model blocked"
        }
        if lower.contains("timed out") || lower.contains("timeout") {
            return "Timed out"
        }
        return "Failed"
    }

    private func acceptSuggestion() {
        guard let snapshot = activeSnapshot else {
            TraceLogger.shared.warn("accept_without_snapshot")
            dismissSuggestion()
            return
        }
        let text = overlay.text
        guard !text.isEmpty else {
            TraceLogger.shared.warn("accept_without_text")
            dismissSuggestion()
            return
        }

        dismissSuggestion()
        TraceLogger.shared.info("suggestion_accepted", fields: [
            "appBundleId": snapshot.app.bundleId,
            "appName": snapshot.app.name,
            "suggestionLength": text.count,
            "suggestionHash": text.ghostCompleteSHA256
        ])
        insertion.insert(text, into: snapshot.app, settings: settings)
        sidecar.learnAccepted(snapshot: snapshot, requestId: latestRequestId ?? UUID().uuidString, suggestion: text)
    }

    private func dismissSuggestion() {
        if overlay.isVisible {
            TraceLogger.shared.debug("suggestion_dismissed")
        }
        debouncer.cancel()
        overlay.hide()
    }
}
