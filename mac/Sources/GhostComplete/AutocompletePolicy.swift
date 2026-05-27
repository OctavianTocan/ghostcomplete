import ApplicationServices
import Foundation

enum AutocompletePolicy {
    static let debounceDelay: TimeInterval = 0.3
    static let minPrefixCharacters = 3
    static let maxPrefixCharacters = 4000

    private static let printableKeyCodes = Set<CGKeyCode>([
        0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 11,
        12, 13, 14, 15, 16, 17,
        18, 19, 20, 21, 22, 23, 24, 25, 26, 27, 28, 29,
        30, 31, 32, 33, 34, 35, 37, 38, 39, 40, 41, 42,
        43, 44, 45, 46, 47, 49, 50,
        65, 67, 69, 75, 78, 81, 82, 83, 84, 85, 86, 87, 88, 89, 91, 92
    ])

    private static let nonTextKeyCodes = Set<CGKeyCode>([
        36, 48, 51, 53, 54, 55, 56, 57, 58, 59, 60, 61, 62, 63,
        96, 97, 98, 99, 100, 101, 103, 105, 106, 107, 109, 111,
        115, 116, 117, 119, 121, 123, 124, 125, 126
    ])

    private static let fastBoundaryKeyCodes = Set<CGKeyCode>([
        24, 27, 30, 33, 39, 41, 42, 43, 47, 49, 65, 67, 75, 78, 85
    ])

    static func shouldScheduleCompletion(keyCode: CGKeyCode, flags: CGEventFlags) -> Bool {
        if flags.contains(.maskCommand) || flags.contains(.maskControl) {
            return false
        }
        if nonTextKeyCodes.contains(keyCode) {
            return false
        }
        return printableKeyCodes.contains(keyCode)
    }

    static func isFastBoundaryKey(_ keyCode: CGKeyCode) -> Bool {
        fastBoundaryKeyCodes.contains(keyCode)
    }

    static func hasEnoughVisiblePrefix(_ context: String) -> Bool {
        context.trimmingTrailingWhitespaceAndNewlines.count >= minPrefixCharacters
    }

    static func requestSignature(for snapshot: FocusSnapshot) -> CompletionRequestSignature {
        CompletionRequestSignature(
            appBundleId: snapshot.app.bundleId,
            contextHash: snapshot.context.ghostCompleteSHA256,
            selectionLocation: snapshot.selection?.location,
            selectionLength: snapshot.selection?.length
        )
    }
}

struct CompletionRequestSignature: Equatable, Sendable {
    let appBundleId: String
    let contextHash: String
    let selectionLocation: Int?
    let selectionLength: Int?
}

private extension String {
    var trimmingTrailingWhitespaceAndNewlines: String {
        var copy = self
        while let last = copy.unicodeScalars.last,
              CharacterSet.whitespacesAndNewlines.contains(last) {
            copy.removeLast()
        }
        return copy
    }
}
