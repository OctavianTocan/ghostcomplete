import AppKit
import Foundation

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let settings = SettingsStore()
    private lazy var coordinator = CompletionCoordinator(settings: settings)
    private lazy var splash = SplashWindowController(settings: settings)
    private lazy var permissions = PermissionCoordinator { [weak self] keyCode, flags in
        self?.coordinator.handleKey(keyCode, flags: flags) ?? .pass
    }

    private var statusItem: NSStatusItem?
    private var permissionSnapshot: PermissionSnapshot?
    private var sidecarReady: Bool?
    private var completionStatus = CompletionStatusSnapshot.waiting

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        do {
            try settings.ensureApplicationSupport()
            TraceLogger.shared.configure(fileURL: settings.appLogURL)
            TraceLogger.shared.info("app_launched", fields: [
                "bundleId": Bundle.main.bundleIdentifier ?? "unknown",
                "version": Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "unknown"
            ])
        } catch {
            NSLog("[GhostComplete] Could not create Application Support: \(error)")
        }

        configureMenu()
        coordinator.onCompletionStatus = { [weak self] status in
            self?.completionStatus = status
            self?.updateSplash()
        }
        permissions.onUpdate = { [weak self] snapshot in
            self?.permissionSnapshot = snapshot
            self?.updateSplash()
        }
        splash.onRetryChecks = { [weak self] in
            self?.permissions.retryNow()
        }
        splash.show(autoDismiss: true)
        updateSplash()
        coordinator.startSidecarAsync { [weak self] ready in
            self?.sidecarReady = ready
            self?.updateSplash()
        }
        permissions.start(promptForAccessibility: true)
    }

    func applicationWillTerminate(_ notification: Notification) {
        TraceLogger.shared.info("app_will_terminate")
        permissions.stop()
        coordinator.stopSidecar()
        TraceLogger.shared.flush()
    }

    private func configureMenu() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.button?.title = "GC"
        let menu = NSMenu()
        menu.addItem(NSMenuItem(title: "GhostComplete", action: nil, keyEquivalent: ""))
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Open Profile", action: #selector(openProfile), keyEquivalent: "p"))
        menu.addItem(NSMenuItem(title: "Show Status", action: #selector(showStatus), keyEquivalent: "s"))
        menu.addItem(NSMenuItem(title: "Delete Learned Data", action: #selector(deleteLearnedData), keyEquivalent: ""))
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Restart Sidecar", action: #selector(restartSidecar), keyEquivalent: "r"))
        menu.addItem(NSMenuItem(title: "Quit", action: #selector(quit), keyEquivalent: "q"))
        item.menu = menu
        statusItem = item
        TraceLogger.shared.debug("menu_configured")
    }

    private func updateSplash() {
        splash.update(
            permissionSnapshot: permissionSnapshot,
            sidecarReady: sidecarReady,
            completionStatus: completionStatus
        )
    }

    @objc private func openProfile() {
        TraceLogger.shared.info("menu_open_profile", fields: ["path": settings.profileURL.path])
        NSWorkspace.shared.open(settings.profileURL)
    }

    @objc private func showStatus() {
        TraceLogger.shared.info("menu_show_status")
        splash.show(autoDismiss: false)
        permissions.refresh(promptForAccessibility: false, source: "menu_show_status")
    }

    @objc private func deleteLearnedData() {
        do {
            try settings.deleteLearnedData()
            TraceLogger.shared.warn("learned_data_deleted")
        } catch {
            TraceLogger.shared.error("learned_data_delete_failed", fields: ["error": error.localizedDescription])
            showPermissionAlert(title: "Delete Failed", message: error.localizedDescription)
        }
    }

    @objc private func restartSidecar() {
        TraceLogger.shared.info("menu_restart_sidecar")
        sidecarReady = false
        updateSplash()
        coordinator.restartSidecarAsync { [weak self] ready in
            self?.sidecarReady = ready
            self?.updateSplash()
        }
    }

    @objc private func quit() {
        TraceLogger.shared.info("menu_quit")
        NSApp.terminate(nil)
    }

    private func showPermissionAlert(title: String, message: String) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.alertStyle = .warning
        alert.runModal()
    }
}
