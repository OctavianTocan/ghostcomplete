import ApplicationServices
import Foundation

struct AutocompletePreferences: Codable, Equatable, Sendable {
    var debounceMs: Int
    var revealAnimationEnabled: Bool
    var revealStepMs: Int
    var overlayNudgeX: Int
    var overlayNudgeY: Int
    var rawTextLoggingEnabled: Bool

    static let `default` = AutocompletePreferences(
        debounceMs: 120,
        revealAnimationEnabled: true,
        revealStepMs: 18,
        overlayNudgeX: 0,
        overlayNudgeY: 0,
        rawTextLoggingEnabled: false
    )

    init(
        debounceMs: Int,
        revealAnimationEnabled: Bool,
        revealStepMs: Int,
        overlayNudgeX: Int,
        overlayNudgeY: Int,
        rawTextLoggingEnabled: Bool = false
    ) {
        self.debounceMs = debounceMs
        self.revealAnimationEnabled = revealAnimationEnabled
        self.revealStepMs = revealStepMs
        self.overlayNudgeX = overlayNudgeX
        self.overlayNudgeY = overlayNudgeY
        self.rawTextLoggingEnabled = rawTextLoggingEnabled
    }

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
            overlayNudgeY: clamped(overlayNudgeY, min: -40, max: 40),
            rawTextLoggingEnabled: rawTextLoggingEnabled
        )
    }

    private enum CodingKeys: String, CodingKey {
        case debounceMs
        case revealAnimationEnabled
        case revealStepMs
        case overlayNudgeX
        case overlayNudgeY
        case rawTextLoggingEnabled
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        debounceMs = try container.decode(Int.self, forKey: .debounceMs)
        revealAnimationEnabled = try container.decode(Bool.self, forKey: .revealAnimationEnabled)
        revealStepMs = try container.decode(Int.self, forKey: .revealStepMs)
        overlayNudgeX = try container.decode(Int.self, forKey: .overlayNudgeX)
        overlayNudgeY = try container.decode(Int.self, forKey: .overlayNudgeY)
        rawTextLoggingEnabled = try container.decodeIfPresent(Bool.self, forKey: .rawTextLoggingEnabled) ?? false
    }
}

private func clamped(_ value: Int, min minimum: Int, max maximum: Int) -> Int {
    Swift.min(Swift.max(value, minimum), maximum)
}
