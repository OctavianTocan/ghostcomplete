import ApplicationServices
import Foundation

struct AutocompletePreferences: Codable, Equatable, Sendable {
    var debounceMs: Int
    var revealAnimationEnabled: Bool
    var revealStepMs: Int
    var overlayNudgeX: Int
    var overlayNudgeY: Int

    static let `default` = AutocompletePreferences(
        debounceMs: 120,
        revealAnimationEnabled: true,
        revealStepMs: 18,
        overlayNudgeX: 1,
        overlayNudgeY: 0
    )

    var debounceDelay: TimeInterval {
        TimeInterval(clamped(debounceMs, min: 60, max: 600)) / 1000
    }

    var revealStepDelay: TimeInterval {
        TimeInterval(clamped(revealStepMs, min: 5, max: 120)) / 1000
    }

    func delay(for keyCode: CGKeyCode) -> TimeInterval {
        let base = debounceDelay
        if AutocompletePolicy.isFastBoundaryKey(keyCode) {
            return max(0.06, base * 0.65)
        }
        return base
    }

    func sanitized() -> AutocompletePreferences {
        AutocompletePreferences(
            debounceMs: clamped(debounceMs, min: 60, max: 600),
            revealAnimationEnabled: revealAnimationEnabled,
            revealStepMs: clamped(revealStepMs, min: 5, max: 120),
            overlayNudgeX: clamped(overlayNudgeX, min: -40, max: 40),
            overlayNudgeY: clamped(overlayNudgeY, min: -40, max: 40)
        )
    }
}

private func clamped(_ value: Int, min minimum: Int, max maximum: Int) -> Int {
    Swift.min(Swift.max(value, minimum), maximum)
}
