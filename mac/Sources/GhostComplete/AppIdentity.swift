import Foundation
import Security

struct AppIdentitySnapshot: Equatable {
    let bundleId: String
    let bundlePath: String
    let executablePath: String
    let designatedRequirement: String?

    var traceFields: [String: Any] {
        [
            "bundleId": bundleId,
            "bundlePath": bundlePath,
            "executablePath": executablePath,
            "designatedRequirement": designatedRequirement ?? "unavailable"
        ]
    }

    var displayText: String {
        var lines = [
            "Bundle ID: \(bundleId)",
            "App path: \(bundlePath)",
            "Executable: \(executablePath)"
        ]
        if let designatedRequirement {
            lines.append("Requirement: \(Self.truncate(designatedRequirement, limit: 180))")
        } else {
            lines.append("Requirement: unavailable")
        }
        return lines.joined(separator: "\n")
    }

    private static func truncate(_ value: String, limit: Int) -> String {
        guard value.count > limit else {
            return value
        }
        return "\(value.prefix(limit - 1))..."
    }
}

enum AppIdentity {
    static func current() -> AppIdentitySnapshot {
        AppIdentitySnapshot(
            bundleId: Bundle.main.bundleIdentifier ?? "unknown",
            bundlePath: Bundle.main.bundlePath,
            executablePath: Bundle.main.executablePath ?? "unknown",
            designatedRequirement: designatedRequirement(for: Bundle.main.bundlePath)
        )
    }

    private static func designatedRequirement(for bundlePath: String) -> String? {
        var staticCode: SecStaticCode?
        let codeStatus = SecStaticCodeCreateWithPath(
            URL(fileURLWithPath: bundlePath) as CFURL,
            SecCSFlags(),
            &staticCode
        )
        guard codeStatus == errSecSuccess, let staticCode else {
            return "SecStaticCodeCreateWithPath failed: \(codeStatus)"
        }

        var requirement: SecRequirement?
        let requirementStatus = SecCodeCopyDesignatedRequirement(
            staticCode,
            SecCSFlags(),
            &requirement
        )
        guard requirementStatus == errSecSuccess, let requirement else {
            return "SecCodeCopyDesignatedRequirement failed: \(requirementStatus)"
        }

        var requirementString: CFString?
        let stringStatus = SecRequirementCopyString(
            requirement,
            SecCSFlags(),
            &requirementString
        )
        guard stringStatus == errSecSuccess, let requirementString else {
            return "SecRequirementCopyString failed: \(stringStatus)"
        }

        return requirementString as String
    }
}
