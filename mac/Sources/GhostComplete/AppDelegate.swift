import ApplicationServices
import AppKit
import Foundation

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let settings = SettingsStore()
    private let keychain = KeychainStore()
    private lazy var coordinator = CompletionCoordinator(settings: settings, keychain: keychain)

    private var statusItem: NSStatusItem?
    private var keyMonitor: KeyMonitor?

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
        coordinator.startSidecar()
        ensureAccessibility()
        installKeyMonitor()
    }

    func applicationWillTerminate(_ notification: Notification) {
        TraceLogger.shared.info("app_will_terminate")
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
        menu.addItem(NSMenuItem(title: "Delete Learned Data", action: #selector(deleteLearnedData), keyEquivalent: ""))
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Restart Sidecar", action: #selector(restartSidecar), keyEquivalent: "r"))
        menu.addItem(NSMenuItem(title: "Quit", action: #selector(quit), keyEquivalent: "q"))
        item.menu = menu
        statusItem = item
        TraceLogger.shared.debug("menu_configured")
    }

    private func ensureAccessibility() {
        let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
        let trusted = AXIsProcessTrustedWithOptions(options)
        TraceLogger.shared.info("accessibility_trust_checked", fields: ["trusted": trusted])
    }

    private func installKeyMonitor() {
        keyMonitor = KeyMonitor { [weak self] keyCode, flags in
            self?.coordinator.handleKey(keyCode, flags: flags) ?? .pass
        }

        if keyMonitor?.start() != true {
            TraceLogger.shared.error("input_monitoring_event_tap_failed")
            showPermissionAlert(
                title: "Input Monitoring Required",
                message: "GhostComplete could not create its keyboard event tap. Enable Input Monitoring for GhostComplete in System Settings."
            )
        } else {
            TraceLogger.shared.info("input_monitoring_event_tap_started")
        }
    }

    @objc private func openProfile() {
        TraceLogger.shared.info("menu_open_profile", fields: ["path": settings.profileURL.path])
        NSWorkspace.shared.open(settings.profileURL)
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
        coordinator.restartSidecar()
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
