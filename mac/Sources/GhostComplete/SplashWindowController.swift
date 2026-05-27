import AppKit

@MainActor
final class SplashWindowController: NSWindowController {
    private let accessibilityValue = NSTextField(labelWithString: "Checking")
    private let inputMonitoringValue = NSTextField(labelWithString: "Checking")
    private let sidecarValue = NSTextField(labelWithString: "Starting")
    private let identityValue = NSTextField(labelWithString: "")
    private let logsURL: URL

    init(settings: SettingsStore) {
        logsURL = settings.logsURL
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 420, height: 260),
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

    func update(accessibilityTrusted: Bool?, inputMonitoringReady: Bool?, sidecarReady: Bool?) {
        accessibilityValue.stringValue = statusText(accessibilityTrusted)
        accessibilityValue.textColor = statusColor(accessibilityTrusted)

        inputMonitoringValue.stringValue = statusText(inputMonitoringReady)
        inputMonitoringValue.textColor = statusColor(inputMonitoringReady)

        sidecarValue.stringValue = statusText(sidecarReady)
        sidecarValue.textColor = statusColor(sidecarReady)

        if accessibilityTrusted == true, inputMonitoringReady == true, sidecarReady == true {
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

        let subtitle = NSTextField(labelWithString: "Local autocomplete is starting.")
        subtitle.font = .systemFont(ofSize: 13)
        subtitle.textColor = .secondaryLabelColor
        subtitle.alignment = .center

        identityValue.stringValue = "Bundle: \(Bundle.main.bundleIdentifier ?? "unknown")\nApp: \(Bundle.main.bundlePath)"
        identityValue.font = .monospacedSystemFont(ofSize: 11, weight: .regular)
        identityValue.textColor = .secondaryLabelColor
        identityValue.lineBreakMode = .byTruncatingMiddle
        identityValue.maximumNumberOfLines = 2

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

        let logsButton = NSButton(title: "Logs", target: self, action: #selector(openLogs))
        logsButton.bezelStyle = .rounded

        let buttonStack = NSStackView(views: [accessibilityButton, inputButton, logsButton])
        buttonStack.orientation = .horizontal
        buttonStack.spacing = 8
        buttonStack.distribution = .fillEqually

        let note = NSTextField(labelWithString: "If Input Monitoring stays blocked after enabling it, remove GhostComplete from the list and add /Applications/GhostComplete.app again.")
        note.font = .systemFont(ofSize: 11)
        note.textColor = .secondaryLabelColor
        note.maximumNumberOfLines = 2
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

    private func statusText(_ value: Bool?) -> String {
        switch value {
        case .some(true):
            return "Ready"
        case .some(false):
            return "Needs access"
        case .none:
            return "Checking"
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

    private func openSettings(_ rawURL: String) {
        guard let url = URL(string: rawURL) else {
            return
        }
        TraceLogger.shared.info("splash_open_settings", fields: ["url": rawURL])
        NSWorkspace.shared.open(url)
    }
}
