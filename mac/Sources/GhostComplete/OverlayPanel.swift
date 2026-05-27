import AppKit

@MainActor
final class OverlayPanel {
    private let panel: NSPanel
    private let label: NSTextField

    var text: String {
        label.stringValue
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

    func show(text: String, near rect: CGRect?) {
        label.stringValue = text
        label.sizeToFit()
        let width = min(max(label.frame.width + 10, 80), 640)
        let origin = clampedOrigin(CoordinateConverter.overlayOrigin(caretRect: rect, fallbackElementRect: nil), width: width)
        panel.setContentSize(NSSize(width: width, height: 24))
        label.frame = NSRect(x: 0, y: 0, width: width, height: 24)
        panel.setFrameOrigin(origin)
        panel.orderFrontRegardless()
        TraceLogger.shared.info("overlay_shown", fields: [
            "textLength": text.count,
            "hasCaretRect": rect != nil,
            "originX": Int(origin.x),
            "originY": Int(origin.y),
            "width": Int(width),
            "level": Int(panel.level.rawValue)
        ])
    }

    func hide() {
        let wasVisible = panel.isVisible
        label.stringValue = ""
        panel.orderOut(nil)
        if wasVisible {
            TraceLogger.shared.debug("overlay_hidden")
        }
    }

    private func clampedOrigin(_ origin: CGPoint, width: CGFloat) -> CGPoint {
        guard let screen = NSScreen.screens.first(where: { $0.frame.contains(origin) }) ?? NSScreen.main else {
            return origin
        }
        let x = min(max(origin.x, screen.visibleFrame.minX + 8), screen.visibleFrame.maxX - width - 8)
        let y = min(max(origin.y, screen.visibleFrame.minY + 8), screen.visibleFrame.maxY - 28)
        return CGPoint(x: x, y: y)
    }
}
