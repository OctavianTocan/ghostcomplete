import Foundation

final class TraceLogger: @unchecked Sendable {
    static let shared = TraceLogger()

    private enum TraceValue: Encodable, Sendable {
        case string(String)
        case int(Int)
        case double(Double)
        case bool(Bool)
        case stringArray([String])
        case null

        func encode(to encoder: Encoder) throws {
            var container = encoder.singleValueContainer()
            switch self {
            case .string(let value):
                try container.encode(value)
            case .int(let value):
                try container.encode(value)
            case .double(let value):
                try container.encode(value)
            case .bool(let value):
                try container.encode(value)
            case .stringArray(let value):
                try container.encode(value)
            case .null:
                try container.encodeNil()
            }
        }
    }

    private var fileURL: URL?
    private let queue = DispatchQueue(label: "dev.octavian.GhostComplete.trace")
    private let encoder: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()
    private let jsonEncoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return encoder
    }()

    func configure(fileURL: URL) {
        queue.sync {
            self.fileURL = fileURL
            try? FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            writeLocked(level: "info", event: "logger_configured", fields: ["path": .string(fileURL.path)])
        }
    }

    func debug(_ event: String, fields: [String: Any] = [:]) {
        write(level: "debug", event: event, fields: fields)
    }

    func info(_ event: String, fields: [String: Any] = [:]) {
        write(level: "info", event: event, fields: fields)
    }

    func warn(_ event: String, fields: [String: Any] = [:]) {
        write(level: "warn", event: event, fields: fields)
    }

    func error(_ event: String, fields: [String: Any] = [:]) {
        write(level: "error", event: event, fields: fields)
    }

    func flush() {
        queue.sync {}
    }

    private func write(level: String, event: String, fields: [String: Any]) {
        let fields = sanitize(fields)
        queue.async {
            self.writeLocked(level: level, event: event, fields: fields)
        }
    }

    private func writeLocked(level: String, event: String, fields: [String: TraceValue]) {
        guard let fileURL else {
            return
        }

        var payload = fields
        payload["ts"] = .string(encoder.string(from: Date()))
        payload["level"] = .string(level)
        payload["component"] = .string("mac-app")
        payload["event"] = .string(event)
        payload["pid"] = .int(Int(ProcessInfo.processInfo.processIdentifier))

        guard let data = try? jsonEncoder.encode(payload) else {
            return
        }

        append(data + Data("\n".utf8), to: fileURL)
    }

    private func sanitize(_ fields: [String: Any]) -> [String: TraceValue] {
        var result: [String: TraceValue] = [:]
        for (key, value) in fields {
            switch value {
            case let string as String:
                result[key] = .string(string)
            case let int as Int:
                result[key] = .int(int)
            case let int32 as Int32:
                result[key] = .int(Int(int32))
            case let double as Double:
                result[key] = .double(double)
            case let bool as Bool:
                result[key] = .bool(bool)
            case let array as [String]:
                result[key] = .stringArray(array)
            case Optional<Any>.none:
                result[key] = .null
            default:
                result[key] = .string(String(describing: value))
            }
        }
        return result
    }

    private func append(_ data: Data, to url: URL) {
        if !FileManager.default.fileExists(atPath: url.path) {
            FileManager.default.createFile(atPath: url.path, contents: nil)
            try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
        }

        guard let handle = try? FileHandle(forWritingTo: url) else {
            return
        }
        defer {
            try? handle.close()
        }
        do {
            try handle.seekToEnd()
            try handle.write(contentsOf: data)
        } catch {
            NSLog("[GhostComplete] Failed to write trace log: \(error.localizedDescription)")
        }
    }
}
