import ApplicationServices
import AppKit
import Foundation

@MainActor
final class CompletionCoordinator {
    private let settings: SettingsStore
    private let keychain: KeychainStore
    private let reader: AccessibilityReader
    private let insertion: InsertionController
    private let sidecar: SidecarClient
    private let overlay: OverlayPanel
    private let debouncer: Debouncer

    private var latestRequestId: String?
    private var activeSnapshot: FocusSnapshot?

    init(
        settings: SettingsStore,
        keychain: KeychainStore,
        reader: AccessibilityReader = AccessibilityReader(),
        insertion: InsertionController = InsertionController(),
        overlay: OverlayPanel = OverlayPanel(),
        debouncer: Debouncer = Debouncer(delay: 0.35)
    ) {
        self.settings = settings
        self.keychain = keychain
        self.reader = reader
        self.insertion = insertion
        self.overlay = overlay
        self.debouncer = debouncer
        self.sidecar = SidecarClient(settings: settings)
    }

    func startSidecar() {
        let envKey = ProcessInfo.processInfo.environment["AI_GATEWAY_API_KEY"]
        let keychainKey = keychain.string(account: "AI_GATEWAY_API_KEY")
        let apiKey = keychainKey ?? envKey
        if keychainKey == nil, let envKey, !envKey.isEmpty {
            try? keychain.setString(envKey, account: "AI_GATEWAY_API_KEY")
        }

        do {
            try sidecar.start(apiKey: apiKey)
        } catch {
            NSLog("[GhostComplete] Sidecar launch failed: \(error.localizedDescription)")
        }
    }

    func stopSidecar() {
        sidecar.stop()
    }

    func restartSidecar() {
        sidecar.stop()
        startSidecar()
    }

    func handleKey(_ keyCode: CGKeyCode, flags: CGEventFlags) -> KeyDecision {
        if flags.contains(.maskCommand) || flags.contains(.maskControl) {
            return .pass
        }

        switch keyCode {
        case 48:
            if overlay.isVisible {
                acceptSuggestion()
                return .swallow
            }
        case 53:
            if overlay.isVisible {
                dismissSuggestion()
                return .swallow
            }
        case 36, 51, 117, 123, 124, 125, 126:
            dismissSuggestion()
            return .pass
        default:
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
        guard sidecar.isReady else {
            startSidecar()
            return
        }

        guard let snapshot = reader.focusedSnapshot(settings: settings),
              snapshot.context.trimmingCharacters(in: .whitespacesAndNewlines).count >= 8
        else {
            return
        }

        let requestId = UUID().uuidString
        latestRequestId = requestId
        activeSnapshot = snapshot

        sidecar.complete(snapshot: snapshot, requestId: requestId) { [weak self] result in
            Task { @MainActor [weak self] in
                self?.handleCompletionResult(result, requestId: requestId, snapshot: snapshot)
            }
        }
    }

    private func handleCompletionResult(_ result: Result<CompleteResponse, Error>, requestId: String, snapshot: FocusSnapshot) {
        guard latestRequestId == requestId else {
            return
        }

        switch result {
        case .success(let response):
            let text = response.completion
            if !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                overlay.show(text: text, near: snapshot.caretRect)
            }
        case .failure(let error):
            NSLog("[GhostComplete] Completion failed: \(error.localizedDescription)")
            sidecar.stop()
        }
    }

    private func acceptSuggestion() {
        guard let snapshot = activeSnapshot else {
            dismissSuggestion()
            return
        }
        let text = overlay.text
        guard !text.isEmpty else {
            dismissSuggestion()
            return
        }

        dismissSuggestion()
        insertion.insert(text, into: snapshot.app, settings: settings)
        sidecar.learnAccepted(snapshot: snapshot, requestId: latestRequestId ?? UUID().uuidString, suggestion: text)
    }

    private func dismissSuggestion() {
        debouncer.cancel()
        overlay.hide()
    }
}
