import ApplicationServices
import AppKit
import Foundation

final class AccessibilityReader {
    private let maxContextCharacters = AutocompletePolicy.maxPrefixCharacters

    func focusedSnapshot(settings: SettingsStore) -> FocusSnapshot? {
        let system = AXUIElementCreateSystemWide()
        guard let appElement = elementAttribute(system, kAXFocusedApplicationAttribute) else {
            return nil
        }

        let app = appContext(for: appElement)
        let windowTitle = focusedWindowTitle(for: appElement)
        if SkipRules.shouldSkipApp(bundleId: app.bundleId, windowTitle: windowTitle, denylist: settings.denylistedBundleIds) != nil {
            return nil
        }

        guard let focusedElement = elementAttribute(appElement, kAXFocusedUIElementAttribute) else {
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

        if SkipRules.shouldSkipElement(metadata) != nil {
            return nil
        }

        guard let text = value, !text.isEmpty else {
            return nil
        }

        let selection = selectedValue.flatMap(Self.selectionRange)
        let prefix = prefixBeforeCaret(in: text, selection: selection)
        let context = String(prefix.suffix(maxContextCharacters))
        if context.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return nil
        }

        let caretRect = selectedValue.flatMap { caretBounds(for: focusedElement, selectedRange: $0) }
        let fallbackRect = elementBounds(for: focusedElement)
        let overlayRect = caretRect ?? fallbackRect

        return FocusSnapshot(
            context: context,
            caretRect: overlayRect,
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
        var value: CFTypeRef?
        let error = AXUIElementCopyParameterizedAttributeValue(
            element,
            "AXBoundsForRange" as CFString,
            selectedRange,
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
        guard AXValueGetValue(axValue, .cgRect, &rect) else {
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
