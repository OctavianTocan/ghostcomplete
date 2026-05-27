import Foundation

enum SkipReason: Equatable {
    case denylistedApp
    case privateWindow
    case unsupportedRole
    case disabledElement
    case secureField
    case emptyValue
}

struct ElementMetadata {
    let role: String?
    let subrole: String?
    let title: String?
    let help: String?
    let description: String?
    let isEnabled: Bool?
    let hasSelectedRange: Bool
    let hasStringValue: Bool
}

enum SkipRules {
    static let editableRoles: Set<String> = [
        "AXTextField",
        "AXTextArea",
        "AXComboBox"
    ]

    static func shouldSkipApp(bundleId: String, windowTitle: String?, denylist: Set<String>) -> SkipReason? {
        if denylist.contains(bundleId) {
            return .denylistedApp
        }

        let title = (windowTitle ?? "").lowercased()
        if title.contains("private browsing") || title.contains("incognito") {
            return .privateWindow
        }

        return nil
    }

    static func shouldSkipElement(_ metadata: ElementMetadata) -> SkipReason? {
        if metadata.isEnabled == false {
            return .disabledElement
        }

        let secureText = [
            metadata.role,
            metadata.subrole,
            metadata.title,
            metadata.help,
            metadata.description
        ]
        .compactMap { $0?.lowercased() }
        .joined(separator: " ")

        if secureText.contains("password") || secureText.contains("secure") || secureText.contains("protected") {
            return .secureField
        }

        guard metadata.hasStringValue else {
            return .emptyValue
        }

        let role = metadata.role ?? ""
        if editableRoles.contains(role) {
            return nil
        }

        if role == "AXWebArea" && metadata.hasSelectedRange {
            return nil
        }

        return .unsupportedRole
    }
}
