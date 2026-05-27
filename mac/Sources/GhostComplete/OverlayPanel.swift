import AppKit

@MainActor
final class OverlayPanel {
    private let panel: NSPanel
    private let label: NSTextField
    private var fullText = ""
    private var revealWorkItems: [DispatchWorkItem] = []

    var text: String {
        fullText
    }

    var isVisible: Bool {
        panel.isVisible
    }

    init() {
        let rect = NSRect(x: 0, y: 0, width: 520, height: 24)
        panel = NSPanel(
            contentRect: rect,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.level = .statusBar
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.ignoresMouseEvents = true
        panel.hasShadow = false
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]

        label = NSTextField(frame: rect)
        label.isBezeled = false
        label.drawsBackground = false
        label.isEditable = false
        label.isSelectable = false
        label.textColor = NSColor.labelColor.withAlphaComponent(0.46)
        label.font = NSFont.systemFont(ofSize: 14)
        panel.contentView?.addSubview(label)
    }

    func show(
        text: String,
        near caretRect: CGRect?,
        anchorSource: String,
        fallbackElementRect: CGRect?,
        preferences: AutocompletePreferences
    ) {
        cancelReveal()
        fullText = text
        let font = NSFont.systemFont(ofSize: fontSize(for: caretRect))
        label.stringValue = preferences.revealAnimationEnabled ? "" : text
        label.font = font
        let height = panelHeight(for: caretRect)
        let measuredWidth = (text as NSString).size(withAttributes: [.font: font]).width
        let width = min(max(measuredWidth + 10, 80), 640)
        var unclampedOrigin = CoordinateConverter.overlayOrigin(
            caretRect: caretRect,
            fallbackElementRect: fallbackElementRect,
            panelHeight: height
        )
        unclampedOrigin.x += CGFloat(preferences.overlayNudgeX)
        unclampedOrigin.y += CGFloat(preferences.overlayNudgeY)
        let origin = clampedOrigin(unclampedOrigin, size: CGSize(width: width, height: height))
        panel.setContentSize(NSSize(width: width, height: height))
        label.frame = NSRect(x: 0, y: 0, width: width, height: height)
        panel.setFrameOrigin(origin)
        panel.orderFrontRegardless()
        TraceLogger.shared.info("overlay_shown", fields: [
            "textLength": text.count,
            "anchorSource": anchorSource,
            "hasCaretRect": caretRect != nil,
            "hasElementRect": fallbackElementRect != nil,
            "unclampedOriginX": Int(unclampedOrigin.x),
            "unclampedOriginY": Int(unclampedOrigin.y),
            "originX": Int(origin.x),
            "originY": Int(origin.y),
            "width": Int(width),
            "height": Int(height),
            "level": Int(panel.level.rawValue)
        ])

        if preferences.revealAnimationEnabled {
            reveal(text: text, stepDelay: preferences.revealStepDelay)
        }
    }

    func hide() {
        let wasVisible = panel.isVisible
        cancelReveal()
        fullText = ""
        label.stringValue = ""
        panel.orderOut(nil)
        if wasVisible {
            TraceLogger.shared.debug("overlay_hidden")
        }
    }

    private func reveal(text: String, stepDelay: TimeInterval) {
        guard !text.isEmpty else {
            return
        }
        let characters = Array(text)
        for index in characters.indices {
            let item = DispatchWorkItem { [weak self] in
                guard let self, self.fullText == text else {
                    return
                }
                self.label.stringValue = String(characters[...index])
            }
            revealWorkItems.append(item)
            DispatchQueue.main.asyncAfter(deadline: .now() + stepDelay * Double(index), execute: item)
        }
    }

    private func cancelReveal() {
        for item in revealWorkItems {
            item.cancel()
        }
        revealWorkItems.removeAll()
    }

    private func fontSize(for caretRect: CGRect?) -> CGFloat {
        guard let caretRect, caretRect.height.isFinite, caretRect.height > 0 else {
            return 14
        }
        return min(max(caretRect.height * 0.78, 12), 18)
    }

    private func panelHeight(for caretRect: CGRect?) -> CGFloat {
        guard let caretRect, caretRect.height.isFinite, caretRect.height > 0 else {
            return 24
        }
        return min(max(caretRect.height + 6, 22), 30)
    }

    private func clampedOrigin(_ origin: CGPoint, size: CGSize) -> CGPoint {
        guard let screen = NSScreen.screens.first(where: { $0.frame.contains(origin) }) ?? NSScreen.main else {
            return origin
        }
        let x = min(max(origin.x, screen.visibleFrame.minX + 8), screen.visibleFrame.maxX - size.width - 8)
        let y = min(max(origin.y, screen.visibleFrame.minY + 8), screen.visibleFrame.maxY - size.height - 4)
        return CGPoint(x: x, y: y)
    }
}
