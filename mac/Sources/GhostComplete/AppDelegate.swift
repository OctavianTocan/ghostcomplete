import ApplicationServices
import AppKit
import Foundation

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let settings = SettingsStore()
    private let keychain = KeychainStore()
    private lazy var coordinator = CompletionCoordinator(settings: settings, keychain: keychain)
    private lazy var splash = SplashWindowController(settings: settings)

    private var statusItem: NSStatusItem?
    private var keyMonitor: KeyMonitor?
    private var inputMonitoringRetryTimer: Timer?
    private var inputMonitoringRetryCount = 0
    private var accessibilityTrusted: Bool?
    private var inputMonitoringReady: Bool?
    private var sidecarReady: Bool?

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
        splash.show()
        updateSplash()
        sidecarReady = coordinator.startSidecar()
        updateSplash()
        accessibilityTrusted = ensureAccessibility(prompt: true)
        updateSplash()
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
        menu.addItem(NSMenuItem(title: "Show Status", action: #selector(showStatus), keyEquivalent: "s"))
        menu.addItem(NSMenuItem(title: "Delete Learned Data", action: #selector(deleteLearnedData), keyEquivalent: ""))
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Restart Sidecar", action: #selector(restartSidecar), keyEquivalent: "r"))
        menu.addItem(NSMenuItem(title: "Quit", action: #selector(quit), keyEquivalent: "q"))
        item.menu = menu
        statusItem = item
        TraceLogger.shared.debug("menu_configured")
    }

    private func ensureAccessibility(prompt: Bool) -> Bool {
        let trusted: Bool
        if prompt {
            let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
            trusted = AXIsProcessTrustedWithOptions(options)
        } else {
            trusted = AXIsProcessTrusted()
        }
        TraceLogger.shared.info("accessibility_trust_checked", fields: [
            "trusted": trusted,
            "prompt": prompt,
            "bundleId": Bundle.main.bundleIdentifier ?? "unknown",
            "bundlePath": Bundle.main.bundlePath,
            "executablePath": Bundle.main.executablePath ?? "unknown"
        ])
        return trusted
    }

    private func installKeyMonitor() {
        if keyMonitor?.isRunning == true {
            inputMonitoringReady = true
            updateSplash()
            return
        }

        keyMonitor = KeyMonitor { [weak self] keyCode, flags in
            self?.coordinator.handleKey(keyCode, flags: flags) ?? .pass
        }

        if keyMonitor?.start() != true {
            inputMonitoringReady = false
            inputMonitoringRetryCount += 1
            TraceLogger.shared.error("input_monitoring_event_tap_failed", fields: [
                "retryCount": inputMonitoringRetryCount,
                "bundleId": Bundle.main.bundleIdentifier ?? "unknown",
                "bundlePath": Bundle.main.bundlePath,
                "executablePath": Bundle.main.executablePath ?? "unknown"
            ])
            updateSplash()
            scheduleInputMonitoringRetry()
        } else {
            inputMonitoringReady = true
            inputMonitoringRetryTimer?.invalidate()
            inputMonitoringRetryTimer = nil
            TraceLogger.shared.info("input_monitoring_event_tap_started")
            updateSplash()
        }
    }

    private func scheduleInputMonitoringRetry() {
        guard inputMonitoringRetryTimer == nil else {
            return
        }

        inputMonitoringRetryTimer = Timer.scheduledTimer(withTimeInterval: 2.5, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.accessibilityTrusted = self?.ensureAccessibility(prompt: false)
                self?.installKeyMonitor()
            }
        }
    }

    private func updateSplash() {
        splash.update(
            accessibilityTrusted: accessibilityTrusted,
            inputMonitoringReady: inputMonitoringReady,
            sidecarReady: sidecarReady
        )
    }

    @objc private func openProfile() {
        TraceLogger.shared.info("menu_open_profile", fields: ["path": settings.profileURL.path])
        NSWorkspace.shared.open(settings.profileURL)
    }

    @objc private func showStatus() {
        TraceLogger.shared.info("menu_show_status")
        splash.show()
        accessibilityTrusted = ensureAccessibility(prompt: false)
        updateSplash()
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
        sidecarReady = coordinator.restartSidecar()
        updateSplash()
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
