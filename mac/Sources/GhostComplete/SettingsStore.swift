import Foundation

final class SettingsStore {
    let appSupportURL: URL
    let profileURL: URL
    let databaseURL: URL
    let logsURL: URL
    let appLogURL: URL
    let sidecarSettingsURL: URL

    var denylistedBundleIds: Set<String> = [
        "com.apple.keychainaccess",
        "com.apple.SecurityAgent",
        "com.1password.1password",
        "com.agilebits.onepassword7",
        "com.bitwarden.desktop",
        "org.keepassxc.keepassxc"
    ]

    var pasteboardFallbackBundleIds: Set<String> = [
        "com.tinyspeck.slackmacgap"
    ]

    init(fileManager: FileManager = .default) {
        let base = fileManager.homeDirectoryForCurrentUser
            .appendingPathComponent("Library", isDirectory: true)
            .appendingPathComponent("Application Support", isDirectory: true)
            .appendingPathComponent("GhostComplete", isDirectory: true)
        appSupportURL = base
        profileURL = base.appendingPathComponent("profile.json")
        databaseURL = base.appendingPathComponent("learning.sqlite")
        logsURL = base.appendingPathComponent("logs", isDirectory: true)
        appLogURL = logsURL.appendingPathComponent("app.jsonl")
        sidecarSettingsURL = base.appendingPathComponent("sidecar-settings.json")
    }

    func ensureApplicationSupport() throws {
        try FileManager.default.createDirectory(at: appSupportURL, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: logsURL, withIntermediateDirectories: true)
        if !FileManager.default.fileExists(atPath: profileURL.path) {
            try writeDefaultProfile()
        }
    }

    func writeDefaultProfile() throws {
        let data = try JSONEncoder.pretty.encode(Profile.empty)
        try data.write(to: profileURL, options: [.atomic])
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: profileURL.path)
    }

    func deleteLearnedData() throws {
        let suffixes = ["", "-wal", "-shm"]
        for suffix in suffixes {
            let url = URL(fileURLWithPath: databaseURL.path + suffix)
            if FileManager.default.fileExists(atPath: url.path) {
                try FileManager.default.removeItem(at: url)
            }
        }
        if FileManager.default.fileExists(atPath: profileURL.path) {
            try FileManager.default.removeItem(at: profileURL)
        }
        try writeDefaultProfile()
    }
}

private extension JSONEncoder {
    static var pretty: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }
}
