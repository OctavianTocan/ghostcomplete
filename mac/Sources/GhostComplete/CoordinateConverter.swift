import AppKit

enum CoordinateConverter {
    static func cocoaRect(fromAccessibilityRect rect: CGRect, screens: [NSScreen] = NSScreen.screens) -> CGRect {
        let screen = screenContainingAccessibilityPoint(rect.origin, screens: screens) ?? NSScreen.main
        let frame = screen?.frame ?? CGRect(x: 0, y: 0, width: 0, height: 0)
        let y = frame.maxY - rect.origin.y - rect.height
        return CGRect(x: rect.origin.x, y: y, width: rect.width, height: rect.height)
    }

    static func overlayOrigin(caretRect: CGRect?, fallbackElementRect: CGRect?) -> CGPoint {
        if let caretRect {
            return CGPoint(x: caretRect.maxX + 2, y: caretRect.minY - 2)
        }
        if let fallbackElementRect {
            return CGPoint(x: fallbackElementRect.minX + 4, y: fallbackElementRect.minY - 26)
        }
        return CGPoint(x: 80, y: 80)
    }

    private static func screenContainingAccessibilityPoint(_ point: CGPoint, screens: [NSScreen]) -> NSScreen? {
        screens.first { screen in
            screen.frame.minX <= point.x && point.x <= screen.frame.maxX
        }
    }
}
