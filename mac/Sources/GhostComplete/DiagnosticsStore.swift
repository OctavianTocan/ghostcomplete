import Foundation

final class DiagnosticsStore {
    private let settings: SettingsStore
    private let sidecarLogURL: URL

    init(settings: SettingsStore) {
        self.settings = settings
        sidecarLogURL = settings.logsURL.appendingPathComponent("sidecar.jsonl")
    }

    func appLogText(maxLines: Int = 220) -> String {
        tail(settings.appLogURL, maxLines: maxLines)
    }

    func sidecarLogText(maxLines: Int = 220) -> String {
        tail(sidecarLogURL, maxLines: maxLines)
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

        let recentEvents = sqliteLines(
            """
            SELECT created_at || ' | ' || event || ' | ' || app_name || ' | ' || coalesce(suggestion, '')
              FROM suggestion_events
             ORDER BY id DESC
             LIMIT 40;
            """
        )

        return [
            profileSummary(),
            learnedWordsSummary(from: acceptedSuggestions),
            acceptedSummary(from: acceptedSuggestions),
            eventSummary(from: recentEvents)
        ].joined(separator: "\n\n")
    }

    private func tail(_ url: URL, maxLines: Int) -> String {
        guard FileManager.default.fileExists(atPath: url.path) else {
            return "No log file yet:\n\(url.path)"
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
            let lines = text
                .split(separator: "\n", omittingEmptySubsequences: false)
                .suffix(maxLines)
                .map(String.init)
            return lines.isEmpty ? "Log file is empty:\n\(url.path)" : lines.joined(separator: "\n")
        } catch {
            return "Could not read log file:\n\(url.path)\n\n\(error.localizedDescription)"
        }
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

    private func learnedWordsSummary(from suggestions: [String]) -> String {
        let stopwords: Set<String> = [
            "the", "and", "for", "that", "this", "with", "you", "your", "are", "was",
            "were", "but", "not", "have", "has", "had", "from", "they", "them", "then",
            "than", "into", "out", "can", "will", "just", "like", "what", "when", "where"
        ]
        let words = suggestions
            .flatMap { suggestion in
                suggestion
                    .lowercased()
                    .components(separatedBy: CharacterSet.alphanumerics.inverted)
            }
            .filter { word in
                word.count > 2 && !stopwords.contains(word)
            }

        var counts: [String: Int] = [:]
        for word in words {
            counts[word, default: 0] += 1
        }

        let top = counts
            .sorted {
                if $0.value == $1.value {
                    return $0.key < $1.key
                }
                return $0.value > $1.value
            }
            .prefix(30)
            .map { "\($0.key) (\($0.value))" }

        return "Learned words\n" + (top.isEmpty ? "No accepted words yet." : top.joined(separator: ", "))
    }

    private func acceptedSummary(from suggestions: [String]) -> String {
        let recent = suggestions
            .prefix(30)
            .enumerated()
            .map { "\($0.offset + 1). \($0.element)" }
        return "Recent accepted suggestions\n" + (recent.isEmpty ? "No accepted suggestions yet." : recent.joined(separator: "\n"))
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
}
