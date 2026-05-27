import AppKit

enum CoordinateConverter {
    static func cocoaRect(fromAccessibilityRect rect: CGRect, screens: [NSScreen] = NSScreen.screens) -> CGRect {
        let frame = virtualScreenFrame(screens: screens)
        let y = frame.maxY - rect.origin.y - rect.height
        return CGRect(x: rect.origin.x, y: y, width: rect.width, height: rect.height)
    }

    static func overlayOrigin(caretRect: CGRect?, fallbackElementRect: CGRect?, panelHeight: CGFloat = 24) -> CGPoint {
        if let caretRect {
            return CGPoint(x: caretRect.maxX + 1, y: caretRect.midY - panelHeight / 2)
        }
        if let fallbackElementRect {
            return CGPoint(x: fallbackElementRect.minX + 6, y: fallbackElementRect.midY - panelHeight / 2)
        }
        return CGPoint(x: 80, y: 80)
    }

    private static func virtualScreenFrame(screens: [NSScreen]) -> CGRect {
        let frames = screens.map(\.frame)
        guard var frame = frames.first else {
            return NSScreen.main?.frame ?? CGRect(x: 0, y: 0, width: 0, height: 0)
        }
        for next in frames.dropFirst() {
            frame = frame.union(next)
        }
        return frame
    }
}
