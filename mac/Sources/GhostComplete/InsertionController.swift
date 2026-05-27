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
        let strategy = InsertionStrategySelector.strategy(for: app.bundleId, fallbackBundleIds: settings.pasteboardFallbackBundleIds)
        TraceLogger.shared.info("insertion_started", fields: [
            "appBundleId": app.bundleId,
            "appName": app.name,
            "strategy": String(describing: strategy),
            "textLength": text.count,
            "textHash": text.ghostCompleteSHA256
        ])

        switch strategy {
        case .syntheticUnicode:
            typeUnicode(text)
        case .pasteboardFallback:
            paste(text)
        }
    }

    private func typeUnicode(_ text: String) {
        guard let source = CGEventSource(stateID: .hidSystemState) else {
            TraceLogger.shared.warn("insertion_synthetic_source_unavailable")
            paste(text)
            return
        }

        TraceLogger.shared.debug("insertion_synthetic_typing", fields: ["scalarCount": text.unicodeScalars.count])
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
        TraceLogger.shared.debug("insertion_pasteboard_prepared", fields: [
            "textLength": text.count,
            "hadPreviousString": previous != nil
        ])

        guard let source = CGEventSource(stateID: .hidSystemState) else {
            TraceLogger.shared.error("insertion_paste_source_unavailable")
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
            TraceLogger.shared.debug("pasteboard_restored", fields: ["hadPreviousString": previous != nil])
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
