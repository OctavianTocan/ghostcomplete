import AppKit

@MainActor
final class SplashWindowController: NSWindowController {
    private let accessibilityValue = NSTextField(labelWithString: "Checking")
    private let inputMonitoringValue = NSTextField(labelWithString: "Checking")
    private let sidecarValue = NSTextField(labelWithString: "Starting")
    private let identityValue = NSTextField(labelWithString: "")
    private let logsURL: URL
    var onRetryChecks: (() -> Void)?

    init(settings: SettingsStore) {
        logsURL = settings.logsURL
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 560, height: 390),
            styleMask: [.titled, .closable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        panel.title = "GhostComplete"
        panel.titlebarAppearsTransparent = true
        panel.isMovableByWindowBackground = true
        panel.isFloatingPanel = true
        panel.level = .floating
        panel.collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary]

        super.init(window: panel)
        buildContent(settings: settings)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    func show() {
        guard let window else {
            return
        }
        window.center()
        window.orderFrontRegardless()
        NSApp.activate(ignoringOtherApps: true)
    }

    func update(permissionSnapshot: PermissionSnapshot?, sidecarReady: Bool?) {
        accessibilityValue.stringValue = accessibilityStatusText(permissionSnapshot?.accessibilityTrusted)
        accessibilityValue.textColor = statusColor(permissionSnapshot?.accessibilityTrusted)

        inputMonitoringValue.stringValue = inputMonitoringStatusText(permissionSnapshot)
        inputMonitoringValue.textColor = statusColor(permissionSnapshot?.inputMonitoringReady)

        sidecarValue.stringValue = sidecarStatusText(sidecarReady)
        sidecarValue.textColor = statusColor(sidecarReady)
        identityValue.stringValue = permissionSnapshot?.identity.displayText ?? AppIdentity.current().displayText

        if permissionSnapshot?.accessibilityTrusted == true,
           permissionSnapshot?.inputMonitoringReady == true,
           sidecarReady == true {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.4) { [weak self] in
                self?.window?.orderOut(nil)
            }
        }
    }

    private func buildContent(settings: SettingsStore) {
        guard let window else {
            return
        }

        let root = NSVisualEffectView()
        root.material = .hudWindow
        root.blendingMode = .behindWindow
        root.state = .active
        root.translatesAutoresizingMaskIntoConstraints = false
        window.contentView = root

        let title = NSTextField(labelWithString: "GhostComplete")
        title.font = .systemFont(ofSize: 24, weight: .semibold)
        title.alignment = .center

        let subtitle = NSTextField(labelWithString: "Local autocomplete is checking macOS trust and the AI sidecar.")
        subtitle.font = .systemFont(ofSize: 13)
        subtitle.textColor = .secondaryLabelColor
        subtitle.alignment = .center

        identityValue.stringValue = AppIdentity.current().displayText
        identityValue.font = .monospacedSystemFont(ofSize: 11, weight: .regular)
        identityValue.textColor = .secondaryLabelColor
        identityValue.lineBreakMode = .byTruncatingMiddle
        identityValue.maximumNumberOfLines = 4

        let statusStack = NSStackView(views: [
            statusRow("Accessibility", accessibilityValue),
            statusRow("Input Monitoring", inputMonitoringValue),
            statusRow("AI sidecar", sidecarValue)
        ])
        statusStack.orientation = .vertical
        statusStack.spacing = 8

        let accessibilityButton = NSButton(title: "Accessibility", target: self, action: #selector(openAccessibilitySettings))
        accessibilityButton.bezelStyle = .rounded

        let inputButton = NSButton(title: "Input Monitoring", target: self, action: #selector(openInputMonitoringSettings))
        inputButton.bezelStyle = .rounded

        let retryButton = NSButton(title: "Retry Checks", target: self, action: #selector(retryChecks))
        retryButton.bezelStyle = .rounded

        let logsButton = NSButton(title: "Open Logs", target: self, action: #selector(openLogs))
        logsButton.bezelStyle = .rounded

        let buttonStack = NSStackView(views: [accessibilityButton, inputButton, retryButton, logsButton])
        buttonStack.orientation = .horizontal
        buttonStack.spacing = 8
        buttonStack.distribution = .fillEqually

        let note = NSTextField(labelWithString: "System Settings can show an enabled row for an old build. If either check stays blocked, remove all GhostComplete rows from both permission lists, add the app path shown below, then click Retry Checks.")
        note.font = .systemFont(ofSize: 11)
        note.textColor = .secondaryLabelColor
        note.maximumNumberOfLines = 3
        note.lineBreakMode = .byWordWrapping

        let content = NSStackView(views: [title, subtitle, statusStack, buttonStack, note, identityValue])
        content.orientation = .vertical
        content.alignment = .leading
        content.spacing = 14
        content.translatesAutoresizingMaskIntoConstraints = false
        root.addSubview(content)

        for view in [title, subtitle, statusStack, buttonStack, note, identityValue] {
            view.translatesAutoresizingMaskIntoConstraints = false
            view.widthAnchor.constraint(equalTo: content.widthAnchor).isActive = true
        }

        NSLayoutConstraint.activate([
            content.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 28),
            content.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -28),
            content.topAnchor.constraint(equalTo: root.topAnchor, constant: 30),
            content.bottomAnchor.constraint(lessThanOrEqualTo: root.bottomAnchor, constant: -24)
        ])

        TraceLogger.shared.debug("splash_configured", fields: [
            "profilePath": settings.profileURL.path,
            "logsPath": settings.logsURL.path
        ])
    }

    private func statusRow(_ title: String, _ value: NSTextField) -> NSView {
        let titleLabel = NSTextField(labelWithString: title)
        titleLabel.font = .systemFont(ofSize: 13, weight: .medium)
        value.font = .systemFont(ofSize: 13, weight: .semibold)
        value.alignment = .right

        let row = NSStackView(views: [titleLabel, value])
        row.orientation = .horizontal
        row.alignment = .centerY
        row.distribution = .fill
        titleLabel.setContentHuggingPriority(.defaultLow, for: .horizontal)
        value.setContentHuggingPriority(.required, for: .horizontal)
        return row
    }

    private func accessibilityStatusText(_ value: Bool?) -> String {
        switch value {
        case .some(true):
            return "Trusted"
        case .some(false):
            return "Not trusted by macOS"
        case .none:
            return "Checking"
        }
    }

    private func inputMonitoringStatusText(_ snapshot: PermissionSnapshot?) -> String {
        guard let snapshot else {
            return "Checking"
        }
        switch snapshot.inputMonitoringReady {
        case .some(true):
            return "Event tap ready"
        case .some(false):
            if snapshot.inputMonitoringRetryExhausted {
                return "Event tap blocked"
            }
            return "Waiting for permission"
        case .none:
            return "Checking"
        }
    }

    private func sidecarStatusText(_ value: Bool?) -> String {
        switch value {
        case .some(true):
            return "Ready"
        case .some(false):
            return "Unavailable"
        case .none:
            return "Starting"
        }
    }

    private func statusColor(_ value: Bool?) -> NSColor {
        switch value {
        case .some(true):
            return .systemGreen
        case .some(false):
            return .systemOrange
        case .none:
            return .secondaryLabelColor
        }
    }

    @objc private func openAccessibilitySettings() {
        openSettings("x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")
    }

    @objc private func openInputMonitoringSettings() {
        openSettings("x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent")
    }

    @objc private func openLogs() {
        NSWorkspace.shared.open(logsURL)
    }

    @objc private func retryChecks() {
        TraceLogger.shared.info("splash_retry_checks")
        onRetryChecks?()
    }

    private func openSettings(_ rawURL: String) {
        guard let url = URL(string: rawURL) else {
            return
        }
        TraceLogger.shared.info("splash_open_settings", fields: ["url": rawURL])
        NSWorkspace.shared.open(url)
    }
}
