import Foundation

final class DiagnosticsStore {
    private struct ReadableLogEntry {
        let time: String
        let level: String
        let source: String
        let title: String
        let details: String

        var key: String {
            "\(level)|\(source)|\(title)|\(details)"
        }

        func line(repeatCount: Int) -> String {
            let paddedLevel = level.padding(toLength: 5, withPad: " ", startingAt: 0)
            let repeatSuffix = repeatCount > 1 ? " (x\(repeatCount))" : ""
            if details.isEmpty {
                return "\(time)  \(paddedLevel)  \(source): \(title)\(repeatSuffix)"
            }
            return "\(time)  \(paddedLevel)  \(source): \(title)\(repeatSuffix) - \(details)"
        }
    }

    private let settings: SettingsStore
    private let sidecarLogURL: URL

    init(settings: SettingsStore) {
        self.settings = settings
        sidecarLogURL = settings.logsURL.appendingPathComponent("sidecar.jsonl")
    }

    func appLogText(maxLines: Int = 220) -> String {
        readableLog(settings.appLogURL, source: "App", maxLines: maxLines)
    }

    func sidecarLogText(maxLines: Int = 220) -> String {
        readableLog(sidecarLogURL, source: "Sidecar", maxLines: maxLines)
    }

    func learningText() -> String {
        let acceptedSuggestions = sqliteLines(
            """
            SELECT suggestion
              FROM suggestion_events
             WHERE event = 'accepted'
               AND suggestion IS NOT NULL
               AND length(trim(suggestion)) > 0
             ORDER BY created_at DESC
             LIMIT 100;
            """
        )

        let curatedSnippets = sqliteLines(
            """
            SELECT text
              FROM curated_snippets
             WHERE length(trim(text)) > 0
             ORDER BY created_at DESC
             LIMIT 50;
            """
        )

        let recentEvents = sqliteLines(
            """
            SELECT created_at || ' | ' || event || ' | ' || app_name || ' | ' || coalesce(suggestion, '')
              FROM suggestion_events
             WHERE event IN ('accepted', 'rejected', 'curated')
             ORDER BY id DESC
             LIMIT 40;
            """
        )

        return [
            profileSummary(),
            profileVocabularySummary(),
            acceptedSummary(from: acceptedSuggestions),
            curatedSummary(from: curatedSnippets),
            eventSummary(from: recentEvents)
        ].joined(separator: "\n\n")
    }

    private func readableLog(_ url: URL, source: String, maxLines: Int) -> String {
        let lines = tailLines(url, maxLines: maxLines)
        guard !lines.isEmpty else {
            return "No log entries yet:\n\(url.path)"
        }

        let entries = lines.compactMap { readableLogEntry($0, source: source) }
        return collapsed(entries)
            .map { entry, repeatCount in
                entry.line(repeatCount: repeatCount)
            }
            .joined(separator: "\n")
    }

    private func tailLines(_ url: URL, maxLines: Int) -> [String] {
        guard FileManager.default.fileExists(atPath: url.path) else {
            return []
        }

        do {
            let handle = try FileHandle(forReadingFrom: url)
            defer {
                try? handle.close()
            }
            let size = try handle.seekToEnd()
            let maxBytes: UInt64 = 512 * 1024
            let offset = size > maxBytes ? size - maxBytes : 0
            try handle.seek(toOffset: offset)
            let data = try handle.readToEnd() ?? Data()
            let text = String(decoding: data, as: UTF8.self)
            return text
                .split(separator: "\n", omittingEmptySubsequences: false)
                .suffix(maxLines)
                .map(String.init)
        } catch {
            return ["Could not read log file: \(url.path) (\(error.localizedDescription))"]
        }
    }

    private func readableLogEntry(_ line: String, source: String) -> ReadableLogEntry? {
        guard let data = line.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else {
            return line.isEmpty
                ? nil
                : ReadableLogEntry(time: "", level: "TEXT", source: source, title: line, details: "")
        }

        let event = string(object["event"])
        guard !isNoisyDebugEvent(event: event, fields: object) else {
            return nil
        }

        let time = shortTime(string(object["ts"]))
        let level = string(object["level"]).uppercased()
        let title = readableTitle(for: event)
        let details = readableDetails(event: event, fields: object)
        return ReadableLogEntry(time: time, level: level, source: source, title: title, details: details)
    }

    private func collapsed(_ entries: [ReadableLogEntry]) -> [(ReadableLogEntry, Int)] {
        var collapsed: [(ReadableLogEntry, Int)] = []
        for entry in entries {
            if let last = collapsed.last, last.0.key == entry.key {
                collapsed[collapsed.count - 1] = (entry, last.1 + 1)
            } else {
                collapsed.append((entry, 1))
            }
        }
        return collapsed
    }

    private func isNoisyDebugEvent(event: String, fields: [String: Any]) -> Bool {
        guard string(fields["level"]) == "debug" else {
            return false
        }
        if event == "completion_focus_snapshot_unavailable" {
            return true
        }
        if event == "completion_status_updated", string(fields["label"]) == "No editable focus" {
            return true
        }
        return false
    }

    private func profileSummary() -> String {
        guard let data = try? Data(contentsOf: settings.profileURL),
              let profile = try? JSONDecoder().decode(Profile.self, from: data)
        else {
            return "Profile\nNo profile file found yet."
        }

        return """
        Profile
        Name: \(valueOrEmpty(profile.name))
        Role: \(valueOrEmpty(profile.role))
        Tone: \(valueOrEmpty(profile.tone))
        Languages: \(listOrEmpty(profile.languages))
        Projects: \(listOrEmpty(profile.projects))
        Vocabulary: \(listOrEmpty(profile.vocabulary))
        People/orgs: \(listOrEmpty(profile.peopleOrgs))
        Never say: \(listOrEmpty(profile.neverSay))
        """
    }

    private func profileVocabularySummary() -> String {
        guard let data = try? Data(contentsOf: settings.profileURL),
              let profile = try? JSONDecoder().decode(Profile.self, from: data)
        else {
            return "Learned vocabulary\nNo profile vocabulary yet."
        }
        return "Learned vocabulary\n" + listOrEmpty(profile.vocabulary)
    }

    private func acceptedSummary(from suggestions: [String]) -> String {
        let recent = suggestions
            .prefix(30)
            .enumerated()
            .map { "\($0.offset + 1). \($0.element)" }
        return "Recent accepted suggestions\n" + (recent.isEmpty ? "No accepted suggestions yet." : recent.joined(separator: "\n"))
    }

    private func curatedSummary(from snippets: [String]) -> String {
        let recent = snippets
            .prefix(30)
            .enumerated()
            .map { "\($0.offset + 1). \($0.element)" }
        return "Curated snippets\n" + (recent.isEmpty ? "No curated snippets yet." : recent.joined(separator: "\n"))
    }

    private func eventSummary(from events: [String]) -> String {
        "Recent learning events\n" + (events.isEmpty ? "No learning events yet." : events.joined(separator: "\n"))
    }

    private func sqliteLines(_ sql: String) -> [String] {
        guard FileManager.default.fileExists(atPath: settings.databaseURL.path) else {
            return []
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/sqlite3")
        process.arguments = [
            "-batch",
            "-noheader",
            "-separator",
            " | ",
            settings.databaseURL.path,
            sql
        ]

        let output = Pipe()
        process.standardOutput = output
        process.standardError = Pipe()

        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            return ["Could not run sqlite3: \(error.localizedDescription)"]
        }

        guard process.terminationStatus == 0 else {
            return ["Could not read learning database."]
        }

        let data = output.fileHandleForReading.readDataToEndOfFile()
        return String(decoding: data, as: UTF8.self)
            .split(separator: "\n")
            .map(String.init)
    }

    private func valueOrEmpty(_ value: String) -> String {
        value.isEmpty ? "(empty)" : value
    }

    private func listOrEmpty(_ values: [String]) -> String {
        values.isEmpty ? "(empty)" : values.joined(separator: ", ")
    }

    private func readableTitle(for event: String) -> String {
        switch event {
        case "app_launched": return "App launched"
        case "sidecar_start_requested": return "Sidecar start requested"
        case "sidecar_start_succeeded": return "Sidecar started"
        case "sidecar_boot": return "Sidecar booted"
        case "server_listening", "sidecar_ready": return "Sidecar ready"
        case "accessibility_trust_checked": return "Accessibility checked"
        case "input_monitoring_event_tap_started": return "Input Monitoring ready"
        case "permission_snapshot_updated": return "Permission state updated"
        case "completion_request_started", "completion_request_received": return "Completion requested"
        case "completion_request_succeeded": return "Completion succeeded"
        case "completion_response_shown": return "Ghost text shown"
        case "completion_request_failed", "request_failed", "sidecar_post_bad_response": return "Completion failed"
        case "completion_request_soft_empty": return "Completion returned empty"
        case "completion_request_cancelled", "sidecar_post_cancelled": return "Completion cancelled"
        case "completion_suppressed_by_backoff": return "Completion paused for backoff"
        case "completion_context_too_short": return "Waiting for more text"
        case "completion_duplicate_context_suppressed": return "Duplicate context skipped"
        case "focus_snapshot_unavailable": return "Focused field not readable"
        case "overlay_shown": return "Overlay positioned"
        case "suggestion_accepted": return "Suggestion accepted"
        case "learn_event_recorded": return "Learning event saved"
        case "preferences_saved": return "Settings saved"
        default: return event.replacingOccurrences(of: "_", with: " ").capitalized
        }
    }

    private func readableDetails(event: String, fields: [String: Any]) -> String {
        switch event {
        case "app_launched":
            return join(["bundle \(string(fields["bundleId"]))", "version \(string(fields["version"]))"])
        case "sidecar_boot", "server_listening", "sidecar_ready", "sidecar_launch_prepared":
            return join(["provider \(string(fields["provider"]))", "model \(string(fields["model"]))", "port \(intString(fields["port"]))"])
        case "accessibility_trust_checked":
            return bool(fields["trusted"]) ? "trusted" : "not trusted"
        case "permission_snapshot_updated":
            return join([
                bool(fields["accessibilityTrusted"]) ? "Accessibility trusted" : "Accessibility blocked",
                bool(fields["inputMonitoringReady"]) ? "Input Monitoring ready" : "Input Monitoring blocked"
            ])
        case "completion_request_started", "completion_request_received":
            return join([
                "app \(string(fields["appName"]))",
                "\(intString(fields["contextLength"])) chars",
                "anchor \(string(fields["anchorSource"]))"
            ])
        case "completion_request_succeeded":
            return join([
                "model \(string(fields["model"]))",
                "\(intString(fields["latencyMs"])) ms",
                "\(intString(fields["completionLength"])) chars",
                "\(intString(fields["streamChunkCount"])) chunks",
                tokens(fields["usage"])
            ])
        case "completion_response_shown":
            return join([
                "\(intString(fields["latencyMs"])) ms",
                "\(intString(fields["completionLength"])) chars"
            ])
        case "request_failed", "completion_request_failed", "sidecar_post_bad_response":
            return join([string(fields["code"]), string(fields["sidecarError"]), string(fields["message"]), string(fields["error"])])
        case "completion_request_soft_empty":
            return join([string(fields["code"]), "\(intString(fields["latencyMs"])) ms"])
        case "completion_suppressed_by_backoff":
            return "\(intString(fields["retryAfterMs"])) ms remaining"
        case "completion_context_too_short":
            return "app \(string(fields["appName"])) - \(intString(fields["contextLength"])) visible chars"
        case "focus_snapshot_unavailable":
            return join(["app \(string(fields["appName"]))", "reason \(string(fields["reason"]))", "role \(string(fields["role"]))"])
        case "overlay_shown":
            return "x \(intString(fields["originX"])), y \(intString(fields["originY"])), \(intString(fields["width"]))x\(intString(fields["height"]))"
        case "suggestion_accepted":
            return join(["app \(string(fields["appName"]))", "\(intString(fields["suggestionLength"])) chars"])
        case "learn_event_recorded":
            return join([string(fields["eventType"]), "\(intString(fields["latencyMs"])) ms"])
        default:
            return compactFallback(fields)
        }
    }

    private func compactFallback(_ fields: [String: Any]) -> String {
        let preferred = ["appName", "model", "provider", "path", "status", "latencyMs", "reason", "label"]
        return join(preferred.map { key in
            guard let value = fields[key] else {
                return ""
            }
            return "\(key): \(value)"
        })
    }

    private func tokens(_ value: Any?) -> String {
        guard let usage = value as? [String: Any] else {
            return ""
        }
        return "tokens \(intString(usage["totalTokens"]))"
    }

    private func string(_ value: Any?) -> String {
        switch value {
        case let value as String:
            return value
        case let value as NSNumber:
            return value.stringValue
        default:
            return ""
        }
    }

    private func intString(_ value: Any?) -> String {
        string(value).isEmpty ? "0" : string(value)
    }

    private func bool(_ value: Any?) -> Bool {
        if let value = value as? Bool {
            return value
        }
        if let value = value as? NSNumber {
            return value.boolValue
        }
        return false
    }

    private func shortTime(_ value: String) -> String {
        guard value.count >= 19 else {
            return value
        }
        return String(value.dropFirst(11).prefix(8))
    }

    private func join(_ parts: [String]) -> String {
        parts
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty && !$0.hasSuffix(" ") }
            .joined(separator: ", ")
    }
}
