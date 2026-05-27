import AppKit
import CoreGraphics

enum InsertionStrategy: Equatable {
    case syntheticUnicode
    case pasteboardFallback
}

enum InsertionStrategySelector {
    static func strategy(for bundleId: String, fallbackBundleIds: Set<String>) -> InsertionStrategy {
        fallbackBundleIds.contains(bundleId) ? .pasteboardFallback : .syntheticUnicode
    }
}

@MainActor
final class InsertionController {
    private let typeDelay: useconds_t = 5_000

    func insert(_ text: String, into app: AppContext, settings: SettingsStore) {
        switch InsertionStrategySelector.strategy(for: app.bundleId, fallbackBundleIds: settings.pasteboardFallbackBundleIds) {
        case .syntheticUnicode:
            typeUnicode(text)
        case .pasteboardFallback:
            paste(text)
        }
    }

    private func typeUnicode(_ text: String) {
        guard let source = CGEventSource(stateID: .hidSystemState) else {
            paste(text)
            return
        }

        for scalar in text.unicodeScalars {
            var value = UniChar(scalar.value)
            let down = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: true)
            down?.keyboardSetUnicodeString(stringLength: 1, unicodeString: &value)
            down?.post(tap: .cghidEventTap)

            let up = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: false)
            up?.keyboardSetUnicodeString(stringLength: 1, unicodeString: &value)
            up?.post(tap: .cghidEventTap)
            usleep(typeDelay)
        }
    }

    private func paste(_ text: String) {
        let pasteboard = NSPasteboard.general
        let previous = pasteboard.string(forType: .string)
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)

        guard let source = CGEventSource(stateID: .hidSystemState) else {
            Self.restorePasteboard(previous)
            return
        }

        let keyV: CGKeyCode = 9
        let down = CGEvent(keyboardEventSource: source, virtualKey: keyV, keyDown: true)
        down?.flags = .maskCommand
        down?.post(tap: .cghidEventTap)

        let up = CGEvent(keyboardEventSource: source, virtualKey: keyV, keyDown: false)
        up?.flags = .maskCommand
        up?.post(tap: .cghidEventTap)

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { [previous] in
            Self.restorePasteboard(previous)
        }
    }

    private static func restorePasteboard(_ previous: String?) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        if let previous {
            pasteboard.setString(previous, forType: .string)
        }
    }
}
