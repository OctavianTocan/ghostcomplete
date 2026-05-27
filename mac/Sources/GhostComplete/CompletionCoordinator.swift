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

    init(
        settings: SettingsStore,
        reader: AccessibilityReader = AccessibilityReader(),
        insertion: InsertionController = InsertionController(),
        overlay: OverlayPanel = OverlayPanel(),
        debouncer: Debouncer = Debouncer(delay: 0.35)
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
            let keychainKey = backgroundKeychain.string(account: "AI_GATEWAY_API_KEY")
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
        sidecar.stop()
    }

    func restartSidecarAsync(onStatus: (@MainActor (Bool) -> Void)? = nil) {
        TraceLogger.shared.info("sidecar_restart_requested")
        sidecar.stop()
        startSidecarAsync(onStatus: onStatus)
    }

    func handleKey(_ keyCode: CGKeyCode, flags: CGEventFlags) -> KeyDecision {
        TraceLogger.shared.debug("key_down", fields: [
            "keyCode": Int(keyCode),
            "hasCommand": flags.contains(.maskCommand),
            "hasControl": flags.contains(.maskControl),
            "overlayVisible": overlay.isVisible
        ])

        if flags.contains(.maskCommand) || flags.contains(.maskControl) {
            return .pass
        }

        switch keyCode {
        case 48:
            if overlay.isVisible {
                TraceLogger.shared.info("key_accept_suggestion")
                acceptSuggestion()
                return .swallow
            }
        case 53:
            if overlay.isVisible {
                TraceLogger.shared.info("key_dismiss_suggestion")
                dismissSuggestion()
                return .swallow
            }
        case 36, 51, 117, 123, 124, 125, 126:
            TraceLogger.shared.debug("key_navigation_or_edit", fields: ["keyCode": Int(keyCode)])
            dismissSuggestion()
            return .pass
        default:
            dismissSuggestion()
            scheduleCompletion()
        }

        return .pass
    }

    private func scheduleCompletion() {
        TraceLogger.shared.debug("completion_debounce_scheduled")
        debouncer.schedule { [weak self] in
            self?.requestCompletion()
        }
    }

    private func requestCompletion() {
        guard sidecar.isReady else {
            TraceLogger.shared.warn("completion_sidecar_not_ready")
            startSidecarAsync()
            return
        }

        guard let snapshot = reader.focusedSnapshot(settings: settings) else {
            TraceLogger.shared.debug("completion_focus_snapshot_unavailable")
            return
        }

        guard snapshot.context.trimmingCharacters(in: .whitespacesAndNewlines).count >= 8 else {
            TraceLogger.shared.debug("completion_context_too_short", fields: [
                "contextLength": snapshot.context.count,
                "appBundleId": snapshot.app.bundleId,
                "appName": snapshot.app.name
            ])
            return
        }

        let requestId = UUID().uuidString
        latestRequestId = requestId
        activeSnapshot = snapshot
        TraceLogger.shared.info("completion_request_started", fields: [
            "requestId": requestId,
            "appBundleId": snapshot.app.bundleId,
            "appName": snapshot.app.name,
            "contextLength": snapshot.context.count,
            "contextHash": snapshot.context.ghostCompleteSHA256,
            "hasCaretRect": snapshot.caretRect != nil,
            "selectionLocation": snapshot.selection?.location ?? -1,
            "selectionLength": snapshot.selection?.length ?? -1
        ])

        sidecar.complete(snapshot: snapshot, requestId: requestId) { [weak self] result in
            Task { @MainActor [weak self] in
                self?.handleCompletionResult(result, requestId: requestId, snapshot: snapshot)
            }
        }
    }

    private func handleCompletionResult(_ result: Result<CompleteResponse, Error>, requestId: String, snapshot: FocusSnapshot) {
        guard latestRequestId == requestId else {
            TraceLogger.shared.debug("completion_response_stale", fields: ["requestId": requestId])
            return
        }

        switch result {
        case .success(let response):
            let text = response.completion
            if !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                TraceLogger.shared.info("completion_response_shown", fields: [
                    "requestId": requestId,
                    "model": response.model,
                    "latencyMs": response.latencyMs,
                    "completionLength": text.count,
                    "completionHash": text.ghostCompleteSHA256
                ])
                overlay.show(text: text, near: snapshot.caretRect)
            } else {
                TraceLogger.shared.info("completion_response_empty", fields: [
                    "requestId": requestId,
                    "model": response.model,
                    "latencyMs": response.latencyMs
                ])
            }
        case .failure(let error):
            TraceLogger.shared.error("completion_request_failed", fields: [
                "requestId": requestId,
                "error": error.localizedDescription
            ])
            NSLog("[GhostComplete] Completion failed: \(error.localizedDescription)")
            sidecar.stop()
        }
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
        TraceLogger.shared.debug("suggestion_dismissed", fields: ["overlayVisible": overlay.isVisible])
        debouncer.cancel()
        overlay.hide()
    }
}
