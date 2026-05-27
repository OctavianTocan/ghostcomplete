import AppKit

@MainActor
final class SplashWindowController: NSWindowController {
    private let settings: SettingsStore
    private let diagnostics: DiagnosticsStore
    private let logsURL: URL

    private let accessibilityValue = NSTextField(labelWithString: "Checking")
    private let inputMonitoringValue = NSTextField(labelWithString: "Checking")
    private let sidecarValue = NSTextField(labelWithString: "Starting")
    private let completionValue = NSTextField(labelWithString: CompletionStatusSnapshot.waiting.label)
    private let identityValue = NSTextField(labelWithString: "")

    private let logSelector = NSSegmentedControl(labels: ["App", "Sidecar"], trackingMode: .selectOne, target: nil, action: nil)
    private let logTextView = NSTextView()
    private let learningTextView = NSTextView()

    private let debounceSlider = NSSlider(value: Double(AutocompletePreferences.default.debounceMs), minValue: 60, maxValue: 600, target: nil, action: nil)
    private let debounceValue = NSTextField(labelWithString: "")
    private let revealCheckbox = NSButton(checkboxWithTitle: "Reveal ghost text one character at a time", target: nil, action: nil)
    private let revealSlider = NSSlider(value: Double(AutocompletePreferences.default.revealStepMs), minValue: 5, maxValue: 120, target: nil, action: nil)
    private let revealValue = NSTextField(labelWithString: "")
    private let nudgeXSlider = NSSlider(value: Double(AutocompletePreferences.default.overlayNudgeX), minValue: -40, maxValue: 40, target: nil, action: nil)
    private let nudgeXValue = NSTextField(labelWithString: "")
    private let nudgeYSlider = NSSlider(value: Double(AutocompletePreferences.default.overlayNudgeY), minValue: -40, maxValue: 40, target: nil, action: nil)
    private let nudgeYValue = NSTextField(labelWithString: "")

    private var preferences: AutocompletePreferences
    private var autoDismissWhenHealthy = true
    private var pendingAutoDismiss: DispatchWorkItem?
    var onRetryChecks: (() -> Void)?

    init(settings: SettingsStore) {
        self.settings = settings
        diagnostics = DiagnosticsStore(settings: settings)
        logsURL = settings.logsURL
        preferences = settings.loadPreferences()

        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 760, height: 640),
            styleMask: [.titled, .closable, .resizable, .fullSizeContentView],
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
        buildContent()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    func show(autoDismiss: Bool = true) {
        guard let window else {
            return
        }
        autoDismissWhenHealthy = autoDismiss
        pendingAutoDismiss?.cancel()
        pendingAutoDismiss = nil
        if !autoDismiss {
            preferences = settings.loadPreferences()
            loadPreferencesIntoControls()
            refreshLogs()
            refreshLearning()
        }
        window.center()
        window.orderFrontRegardless()
        NSApp.activate(ignoringOtherApps: true)
    }

    func update(
        permissionSnapshot: PermissionSnapshot?,
        sidecarReady: Bool?,
        completionStatus: CompletionStatusSnapshot
    ) {
        accessibilityValue.stringValue = accessibilityStatusText(permissionSnapshot?.accessibilityTrusted)
        accessibilityValue.textColor = statusColor(permissionSnapshot?.accessibilityTrusted)

        inputMonitoringValue.stringValue = inputMonitoringStatusText(permissionSnapshot)
        inputMonitoringValue.textColor = statusColor(permissionSnapshot?.inputMonitoringReady)

        sidecarValue.stringValue = sidecarStatusText(sidecarReady)
        sidecarValue.textColor = statusColor(sidecarReady)
        completionValue.stringValue = completionStatus.label
        completionValue.toolTip = completionStatus.detail
        completionValue.textColor = statusColor(completionStatus.isHealthy)
        identityValue.stringValue = permissionSnapshot?.identity.displayText ?? AppIdentity.current().displayText

        if permissionSnapshot?.accessibilityTrusted == true,
           permissionSnapshot?.inputMonitoringReady == true,
           sidecarReady == true,
           autoDismissWhenHealthy {
            pendingAutoDismiss?.cancel()
            let workItem = DispatchWorkItem { [weak self] in
                self?.window?.orderOut(nil)
                self?.pendingAutoDismiss = nil
            }
            pendingAutoDismiss = workItem
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.4, execute: workItem)
        } else {
            pendingAutoDismiss?.cancel()
            pendingAutoDismiss = nil
        }
    }

    private func buildContent() {
        guard let window else {
            return
        }

        let root = NSVisualEffectView()
        root.material = .hudWindow
        root.blendingMode = .behindWindow
        root.state = .active
        root.translatesAutoresizingMaskIntoConstraints = false
        window.contentView = root

        let tabView = NSTabView()
        tabView.translatesAutoresizingMaskIntoConstraints = false
        tabView.addTabViewItem(tabItem("Status", view: makeStatusTab()))
        tabView.addTabViewItem(tabItem("Logs", view: makeLogsTab()))
        tabView.addTabViewItem(tabItem("Settings", view: makeSettingsTab()))
        tabView.addTabViewItem(tabItem("Learning", view: makeLearningTab()))
        root.addSubview(tabView)

        NSLayoutConstraint.activate([
            tabView.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 18),
            tabView.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -18),
            tabView.topAnchor.constraint(equalTo: root.topAnchor, constant: 20),
            tabView.bottomAnchor.constraint(equalTo: root.bottomAnchor, constant: -18)
        ])

        loadPreferencesIntoControls()
        refreshLogs()
        refreshLearning()

        TraceLogger.shared.debug("splash_configured", fields: [
            "profilePath": settings.profileURL.path,
            "logsPath": settings.logsURL.path,
            "preferencesPath": settings.preferencesURL.path
        ])
    }

    private func makeStatusTab() -> NSView {
        let title = NSTextField(labelWithString: "GhostComplete")
        title.font = .systemFont(ofSize: 24, weight: .semibold)
        title.alignment = .center

        let subtitle = NSTextField(labelWithString: "Local autocomplete status, trust checks, and sidecar health.")
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
            statusRow("AI sidecar", sidecarValue),
            statusRow("Last completion", completionValue)
        ])
        statusStack.orientation = .vertical
        statusStack.spacing = 8

        let accessibilityButton = NSButton(title: "Accessibility", target: self, action: #selector(openAccessibilitySettings))
        accessibilityButton.bezelStyle = .rounded

        let inputButton = NSButton(title: "Input Monitoring", target: self, action: #selector(openInputMonitoringSettings))
        inputButton.bezelStyle = .rounded

        let retryButton = NSButton(title: "Retry Checks", target: self, action: #selector(retryChecks))
        retryButton.bezelStyle = .rounded

        let logsButton = NSButton(title: "Open Logs Folder", target: self, action: #selector(openLogsFolder))
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
        content.alignment = .width
        content.spacing = 14

        for view in [title, subtitle, statusStack, buttonStack, note, identityValue] {
            view.translatesAutoresizingMaskIntoConstraints = false
            view.widthAnchor.constraint(equalTo: content.widthAnchor).isActive = true
        }

        return padded(content)
    }

    private func makeLogsTab() -> NSView {
        logSelector.selectedSegment = 0
        logSelector.target = self
        logSelector.action = #selector(logSelectionChanged)

        let refreshButton = NSButton(title: "Refresh", target: self, action: #selector(refreshLogsAction))
        refreshButton.bezelStyle = .rounded

        let openButton = NSButton(title: "Open Logs Folder", target: self, action: #selector(openLogsFolder))
        openButton.bezelStyle = .rounded

        let topRow = NSStackView(views: [logSelector, refreshButton, openButton])
        topRow.orientation = .horizontal
        topRow.spacing = 10
        topRow.alignment = .centerY

        configureTextView(logTextView)
        let scrollView = scrollView(for: logTextView)

        let content = NSStackView(views: [topRow, scrollView])
        content.orientation = .vertical
        content.alignment = .width
        content.spacing = 12
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.heightAnchor.constraint(greaterThanOrEqualToConstant: 460).isActive = true

        return padded(content)
    }

    private func makeSettingsTab() -> NSView {
        for slider in [debounceSlider, revealSlider, nudgeXSlider, nudgeYSlider] {
            slider.target = self
            slider.action = #selector(savePreferences)
            slider.isContinuous = false
        }
        revealCheckbox.target = self
        revealCheckbox.action = #selector(savePreferences)

        let content = NSStackView(views: [
            sectionTitle("Autocomplete timing"),
            sliderRow("Idle debounce", slider: debounceSlider, value: debounceValue),
            helperText("Lower values feel more responsive; higher values reduce request churn while typing."),
            sectionTitle("Ghost text animation"),
            checkboxRow(revealCheckbox),
            sliderRow("Reveal step", slider: revealSlider, value: revealValue),
            helperText("This animates the local overlay reveal. The sidecar still uses streamed text and records AI SDK stream metadata in sidecar logs."),
            sectionTitle("Overlay placement"),
            sliderRow("Horizontal nudge", slider: nudgeXSlider, value: nudgeXValue),
            sliderRow("Vertical nudge", slider: nudgeYSlider, value: nudgeYValue)
        ])
        content.orientation = .vertical
        content.alignment = .width
        content.spacing = 12

        return padded(content)
    }

    private func makeLearningTab() -> NSView {
        let refreshButton = NSButton(title: "Refresh", target: self, action: #selector(refreshLearningAction))
        refreshButton.bezelStyle = .rounded

        let profileButton = NSButton(title: "Open Profile", target: self, action: #selector(openProfile))
        profileButton.bezelStyle = .rounded

        let topRow = NSStackView(views: [refreshButton, profileButton])
        topRow.orientation = .horizontal
        topRow.spacing = 10
        topRow.alignment = .centerY

        configureTextView(learningTextView)
        let scrollView = scrollView(for: learningTextView)

        let content = NSStackView(views: [topRow, scrollView])
        content.orientation = .vertical
        content.alignment = .width
        content.spacing = 12
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.heightAnchor.constraint(greaterThanOrEqualToConstant: 460).isActive = true

        return padded(content)
    }

    private func tabItem(_ label: String, view: NSView) -> NSTabViewItem {
        let item = NSTabViewItem(identifier: label)
        item.label = label
        item.view = view
        return item
    }

    private func padded(_ content: NSView) -> NSView {
        let container = NSView()
        content.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(content)
        NSLayoutConstraint.activate([
            content.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 18),
            content.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -18),
            content.topAnchor.constraint(equalTo: container.topAnchor, constant: 18),
            content.bottomAnchor.constraint(lessThanOrEqualTo: container.bottomAnchor, constant: -18)
        ])
        return container
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

    private func sectionTitle(_ title: String) -> NSTextField {
        let label = NSTextField(labelWithString: title)
        label.font = .systemFont(ofSize: 15, weight: .semibold)
        return label
    }

    private func helperText(_ text: String) -> NSTextField {
        let label = NSTextField(labelWithString: text)
        label.font = .systemFont(ofSize: 12)
        label.textColor = .secondaryLabelColor
        label.maximumNumberOfLines = 2
        label.lineBreakMode = .byWordWrapping
        return label
    }

    private func checkboxRow(_ checkbox: NSButton) -> NSView {
        checkbox.font = .systemFont(ofSize: 13)
        return checkbox
    }

    private func sliderRow(_ title: String, slider: NSSlider, value: NSTextField) -> NSView {
        let titleLabel = NSTextField(labelWithString: title)
        titleLabel.font = .systemFont(ofSize: 13, weight: .medium)
        titleLabel.widthAnchor.constraint(equalToConstant: 150).isActive = true
        value.font = .monospacedSystemFont(ofSize: 12, weight: .regular)
        value.alignment = .right
        value.widthAnchor.constraint(equalToConstant: 72).isActive = true

        let row = NSStackView(views: [titleLabel, slider, value])
        row.orientation = .horizontal
        row.spacing = 12
        row.alignment = .centerY
        slider.setContentHuggingPriority(.defaultLow, for: .horizontal)
        return row
    }

    private func configureTextView(_ textView: NSTextView) {
        textView.isEditable = false
        textView.isSelectable = true
        textView.drawsBackground = false
        textView.font = .monospacedSystemFont(ofSize: 11, weight: .regular)
        textView.textColor = .labelColor
        textView.textContainerInset = NSSize(width: 8, height: 8)
        textView.isHorizontallyResizable = true
        textView.isVerticallyResizable = true
        textView.autoresizingMask = [.width]
        textView.textContainer?.widthTracksTextView = false
        textView.textContainer?.containerSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
    }

    private func scrollView(for textView: NSTextView) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.borderType = .bezelBorder
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = true
        scrollView.autohidesScrollers = false
        scrollView.documentView = textView
        return scrollView
    }

    private func loadPreferencesIntoControls() {
        debounceSlider.doubleValue = Double(preferences.debounceMs)
        revealCheckbox.state = preferences.revealAnimationEnabled ? .on : .off
        revealSlider.doubleValue = Double(preferences.revealStepMs)
        nudgeXSlider.doubleValue = Double(preferences.overlayNudgeX)
        nudgeYSlider.doubleValue = Double(preferences.overlayNudgeY)
        updatePreferenceLabels()
    }

    private func updatePreferenceLabels() {
        debounceValue.stringValue = "\(Int(debounceSlider.doubleValue.rounded())) ms"
        revealValue.stringValue = "\(Int(revealSlider.doubleValue.rounded())) ms"
        nudgeXValue.stringValue = "\(Int(nudgeXSlider.doubleValue.rounded())) px"
        nudgeYValue.stringValue = "\(Int(nudgeYSlider.doubleValue.rounded())) px"
    }

    private func currentControlPreferences() -> AutocompletePreferences {
        AutocompletePreferences(
            debounceMs: Int(debounceSlider.doubleValue.rounded()),
            revealAnimationEnabled: revealCheckbox.state == .on,
            revealStepMs: Int(revealSlider.doubleValue.rounded()),
            overlayNudgeX: Int(nudgeXSlider.doubleValue.rounded()),
            overlayNudgeY: Int(nudgeYSlider.doubleValue.rounded())
        ).sanitized()
    }

    private func refreshLogs() {
        if logSelector.selectedSegment == 1 {
            logTextView.string = diagnostics.sidecarLogText()
        } else {
            logTextView.string = diagnostics.appLogText()
        }
    }

    private func refreshLearning() {
        learningTextView.string = diagnostics.learningText()
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

    @objc private func openLogsFolder() {
        NSWorkspace.shared.open(logsURL)
    }

    @objc private func openProfile() {
        NSWorkspace.shared.open(settings.profileURL)
    }

    @objc private func retryChecks() {
        TraceLogger.shared.info("splash_retry_checks")
        onRetryChecks?()
    }

    @objc private func logSelectionChanged() {
        refreshLogs()
    }

    @objc private func refreshLogsAction() {
        refreshLogs()
    }

    @objc private func refreshLearningAction() {
        refreshLearning()
    }

    @objc private func savePreferences() {
        preferences = currentControlPreferences()
        updatePreferenceLabels()
        do {
            try settings.savePreferences(preferences)
            TraceLogger.shared.info("preferences_saved", fields: [
                "debounceMs": preferences.debounceMs,
                "revealAnimationEnabled": preferences.revealAnimationEnabled,
                "revealStepMs": preferences.revealStepMs,
                "overlayNudgeX": preferences.overlayNudgeX,
                "overlayNudgeY": preferences.overlayNudgeY
            ])
        } catch {
            TraceLogger.shared.error("preferences_save_failed", fields: ["error": error.localizedDescription])
        }
    }

    private func openSettings(_ rawURL: String) {
        guard let url = URL(string: rawURL) else {
            return
        }
        TraceLogger.shared.info("splash_open_settings", fields: ["url": rawURL])
        NSWorkspace.shared.open(url)
    }
}
