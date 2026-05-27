import ApplicationServices
import AppKit
import Foundation

final class AccessibilityReader {
    private let maxContextCharacters = AutocompletePolicy.maxPrefixCharacters

    func focusedSnapshot(settings: SettingsStore) -> FocusSnapshot? {
        let system = AXUIElementCreateSystemWide()
        guard let appElement = elementAttribute(system, kAXFocusedApplicationAttribute) else {
            TraceLogger.shared.debug("focus_snapshot_unavailable", fields: ["reason": "focused_application_missing"])
            return nil
        }

        let app = appContext(for: appElement)
        let windowTitle = focusedWindowTitle(for: appElement)
        if let reason = SkipRules.shouldSkipApp(bundleId: app.bundleId, windowTitle: windowTitle, denylist: settings.denylistedBundleIds) {
            TraceLogger.shared.debug("focus_snapshot_unavailable", fields: [
                "reason": String(describing: reason),
                "appBundleId": app.bundleId,
                "appName": app.name
            ])
            return nil
        }

        guard let focusedElement = elementAttribute(appElement, kAXFocusedUIElementAttribute) else {
            TraceLogger.shared.debug("focus_snapshot_unavailable", fields: [
                "reason": "focused_element_missing",
                "appBundleId": app.bundleId,
                "appName": app.name
            ])
            return nil
        }

        let selectedValue = axValueAttribute(focusedElement, kAXSelectedTextRangeAttribute)
        let value = stringAttribute(focusedElement, kAXValueAttribute)
        let metadata = ElementMetadata(
            role: stringAttribute(focusedElement, kAXRoleAttribute),
            subrole: stringAttribute(focusedElement, kAXSubroleAttribute),
            title: stringAttribute(focusedElement, kAXTitleAttribute),
            help: stringAttribute(focusedElement, kAXHelpAttribute),
            description: stringAttribute(focusedElement, kAXDescriptionAttribute),
            isEnabled: boolAttribute(focusedElement, kAXEnabledAttribute),
            hasSelectedRange: selectedValue != nil,
            hasStringValue: value != nil
        )

        if let reason = SkipRules.shouldSkipElement(metadata) {
            TraceLogger.shared.debug("focus_snapshot_unavailable", fields: [
                "reason": String(describing: reason),
                "appBundleId": app.bundleId,
                "appName": app.name,
                "role": metadata.role ?? "",
                "subrole": metadata.subrole ?? "",
                "hasSelectedRange": metadata.hasSelectedRange,
                "hasStringValue": metadata.hasStringValue
            ])
            return nil
        }

        guard let text = value, !text.isEmpty else {
            TraceLogger.shared.debug("focus_snapshot_unavailable", fields: [
                "reason": "empty_value",
                "appBundleId": app.bundleId,
                "appName": app.name,
                "role": metadata.role ?? "",
                "subrole": metadata.subrole ?? ""
            ])
            return nil
        }

        let selection = selectedValue.flatMap(Self.selectionRange)
        let prefix = prefixBeforeCaret(in: text, selection: selection)
        let context = String(prefix.suffix(maxContextCharacters))
        if context.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            TraceLogger.shared.debug("focus_snapshot_unavailable", fields: [
                "reason": "blank_context",
                "appBundleId": app.bundleId,
                "appName": app.name,
                "role": metadata.role ?? "",
                "subrole": metadata.subrole ?? ""
            ])
            return nil
        }

        let caretRect = selectedValue.flatMap { caretBounds(for: focusedElement, selectedRange: $0) }
        let elementRect = elementBounds(for: focusedElement)
        let estimatedRect = caretRect == nil ? estimatedCaretRect(context: context, elementRect: elementRect) : nil
        let anchorRect = caretRect ?? estimatedRect
        let anchorSource: String
        if caretRect != nil {
            anchorSource = "caret"
        } else if estimatedRect != nil {
            anchorSource = "estimated"
        } else if elementRect != nil {
            anchorSource = "element"
        } else {
            anchorSource = "default"
        }

        return FocusSnapshot(
            context: context,
            caretRect: anchorRect,
            elementRect: elementRect,
            anchorSource: anchorSource,
            app: app,
            selection: selection
        )
    }

    private func appContext(for element: AXUIElement) -> AppContext {
        var pid: pid_t = 0
        AXUIElementGetPid(element, &pid)
        let runningApp = NSRunningApplication(processIdentifier: pid)
        return AppContext(
            bundleId: runningApp?.bundleIdentifier ?? "unknown",
            name: runningApp?.localizedName ?? "Unknown"
        )
    }

    private func focusedWindowTitle(for appElement: AXUIElement) -> String? {
        guard let window = elementAttribute(appElement, kAXFocusedWindowAttribute) else {
            return nil
        }
        return stringAttribute(window, kAXTitleAttribute)
    }

    private func prefixBeforeCaret(in text: String, selection: SelectionRange?) -> String {
        let utf16Offset = min(max(selection?.location ?? text.utf16.count, 0), text.utf16.count)
        let index = String.Index(utf16Offset: utf16Offset, in: text)
        return String(text[..<index])
    }

    private func caretBounds(for element: AXUIElement, selectedRange: AXValue) -> CGRect? {
        guard let range = Self.selectionRange(from: selectedRange) else {
            return bounds(for: element, rangeValue: selectedRange)
        }

        if range.length == 0, range.location > 0 {
            let previousCharacterRange = CFRange(location: range.location - 1, length: 1)
            if let previousRect = bounds(for: element, range: previousCharacterRange) {
                return CGRect(
                    x: previousRect.maxX,
                    y: previousRect.minY,
                    width: 2,
                    height: previousRect.height
                )
            }
        }

        if range.length > 0,
           let selectedRect = bounds(
            for: element,
            range: CFRange(location: range.location, length: range.length)
           ) {
            return CGRect(
                x: selectedRect.maxX,
                y: selectedRect.minY,
                width: 2,
                height: selectedRect.height
            )
        }

        return bounds(for: element, rangeValue: selectedRange)
    }

    private func bounds(for element: AXUIElement, range: CFRange) -> CGRect? {
        var mutableRange = range
        guard let value = AXValueCreate(.cfRange, &mutableRange) else {
            return nil
        }
        return bounds(for: element, rangeValue: value)
    }

    private func bounds(for element: AXUIElement, rangeValue: AXValue) -> CGRect? {
        var value: CFTypeRef?
        let error = AXUIElementCopyParameterizedAttributeValue(
            element,
            "AXBoundsForRange" as CFString,
            rangeValue,
            &value
        )
        guard error == .success,
              let value,
              CFGetTypeID(value) == AXValueGetTypeID()
        else {
            return nil
        }
        let axValue = value as! AXValue

        var rect = CGRect.zero
        guard AXValueGetValue(axValue, .cgRect, &rect),
              rect.width.isFinite,
              rect.height.isFinite,
              rect.height > 0
        else {
            return nil
        }
        return CoordinateConverter.cocoaRect(fromAccessibilityRect: rect)
    }

    private func elementBounds(for element: AXUIElement) -> CGRect? {
        guard
            let positionValue = axValueAttribute(element, kAXPositionAttribute),
            let sizeValue = axValueAttribute(element, kAXSizeAttribute)
        else {
            return nil
        }

        var point = CGPoint.zero
        var size = CGSize.zero
        guard AXValueGetValue(positionValue, .cgPoint, &point),
              AXValueGetValue(sizeValue, .cgSize, &size)
        else {
            return nil
        }

        return CoordinateConverter.cocoaRect(
            fromAccessibilityRect: CGRect(origin: point, size: size)
        )
    }

    private func estimatedCaretRect(context: String, elementRect: CGRect?) -> CGRect? {
        guard let elementRect,
              elementRect.width.isFinite,
              elementRect.height.isFinite,
              elementRect.width > 20,
              elementRect.height > 12
        else {
            return nil
        }

        let font = NSFont.systemFont(ofSize: 14)
        let lineHeight = max(font.boundingRectForFont.height, 17)
        let horizontalPadding: CGFloat = 8
        let verticalPadding: CGFloat = 6
        let usableWidth = max(elementRect.width - horizontalPadding * 2, 40)
        let currentLine = context.components(separatedBy: .newlines).last ?? context
        let measuredWidth = (currentLine as NSString).size(withAttributes: [.font: font]).width
        let wrappedLineIndex = max(0, Int(floor(measuredWidth / usableWidth)))
        let lineWidth = measuredWidth - CGFloat(wrappedLineIndex) * usableWidth
        let x = min(elementRect.minX + horizontalPadding + lineWidth, elementRect.maxX - horizontalPadding)
        let y = max(
            elementRect.minY + 2,
            elementRect.maxY - verticalPadding - CGFloat(wrappedLineIndex + 1) * lineHeight
        )

        return CGRect(x: x, y: y, width: 2, height: lineHeight)
    }

    private static func selectionRange(from value: AXValue) -> SelectionRange? {
        var range = CFRange(location: 0, length: 0)
        guard AXValueGetValue(value, .cfRange, &range) else {
            return nil
        }
        return SelectionRange(location: range.location, length: range.length)
    }

    private func stringAttribute(_ element: AXUIElement, _ attribute: String) -> String? {
        attributeValue(element, attribute) as? String
    }

    private func boolAttribute(_ element: AXUIElement, _ attribute: String) -> Bool? {
        attributeValue(element, attribute) as? Bool
    }

    private func elementAttribute(_ element: AXUIElement, _ attribute: String) -> AXUIElement? {
        guard let value = attributeValue(element, attribute),
              CFGetTypeID(value) == AXUIElementGetTypeID()
        else {
            return nil
        }
        return (value as! AXUIElement)
    }

    private func axValueAttribute(_ element: AXUIElement, _ attribute: String) -> AXValue? {
        guard let value = attributeValue(element, attribute),
              CFGetTypeID(value) == AXValueGetTypeID()
        else {
            return nil
        }
        return (value as! AXValue)
    }

    private func attributeValue(_ element: AXUIElement, _ attribute: String) -> CFTypeRef? {
        var value: CFTypeRef?
        let error = AXUIElementCopyAttributeValue(element, attribute as CFString, &value)
        guard error == .success else {
            return nil
        }
        return value
    }
}
