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
        } catch {
            NSLog("[GhostComplete] Could not create Application Support: \(error)")
        }

        configureMenu()
        coordinator.startSidecar()
        ensureAccessibility()
        installKeyMonitor()
    }

    func applicationWillTerminate(_ notification: Notification) {
        coordinator.stopSidecar()
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
    }

    private func ensureAccessibility() {
        let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
    }

    private func installKeyMonitor() {
        keyMonitor = KeyMonitor { [weak self] keyCode, flags in
            self?.coordinator.handleKey(keyCode, flags: flags) ?? .pass
        }

        if keyMonitor?.start() != true {
            showPermissionAlert(
                title: "Input Monitoring Required",
                message: "GhostComplete could not create its keyboard event tap. Enable Input Monitoring for GhostComplete in System Settings."
            )
        }
    }

    @objc private func openProfile() {
        NSWorkspace.shared.open(settings.profileURL)
    }

    @objc private func deleteLearnedData() {
        do {
            try settings.deleteLearnedData()
        } catch {
            showPermissionAlert(title: "Delete Failed", message: error.localizedDescription)
        }
    }

    @objc private func restartSidecar() {
        coordinator.restartSidecar()
    }

    @objc private func quit() {
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
