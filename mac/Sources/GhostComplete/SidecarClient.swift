import Foundation

enum SidecarError: Error, LocalizedError {
    case missingScript
    case missingPort
    case badResponse
    case launchFailed(String)

    var errorDescription: String? {
        switch self {
        case .missingScript:
            return "Could not find the bundled sidecar script."
        case .missingPort:
            return "Sidecar is not ready yet."
        case .badResponse:
            return "Sidecar returned an invalid response."
        case .launchFailed(let message):
            return message
        }
    }
}

@MainActor
final class SidecarClient {
    private let settings: SettingsStore
    private var process: Process?
    private(set) var port: Int?

    let token = UUID().uuidString

    var isReady: Bool {
        port != nil && process?.isRunning == true
    }

    init(settings: SettingsStore) {
        self.settings = settings
    }

    func start(apiKey: String?) throws {
        if process?.isRunning == true {
            TraceLogger.shared.debug("sidecar_start_skipped_already_running", fields: ["port": port ?? -1])
            return
        }

        guard let scriptURL = sidecarScriptURL() else {
            TraceLogger.shared.error("sidecar_script_missing")
            throw SidecarError.missingScript
        }

        let process = Process()
        let command = sidecarCommand(for: scriptURL)
        process.executableURL = command.executableURL
        process.arguments = command.arguments

        var environment = ProcessInfo.processInfo.environment
        let sidecarPort = configuredPort()
        environment["GHOSTCOMPLETE_TOKEN"] = token
        environment["GHOSTCOMPLETE_APP_SUPPORT"] = settings.appSupportURL.path
        environment["GHOSTCOMPLETE_LOG_DIR"] = settings.logsURL.path
        environment["GHOSTCOMPLETE_PORT"] = String(sidecarPort)
        let runtimeSettings = SidecarRuntimeSettings.load(from: settings.sidecarSettingsURL)
        runtimeSettings?.apply(to: &environment)
        if let apiKey, !apiKey.isEmpty {
            environment["AI_GATEWAY_API_KEY"] = apiKey
        }
        process.environment = environment
        TraceLogger.shared.info("sidecar_launch_prepared", fields: [
            "scriptPath": scriptURL.path,
            "executablePath": command.executableURL.path,
            "argumentCount": command.arguments.count,
            "port": sidecarPort,
            "hasApiKey": apiKey?.isEmpty == false,
            "model": environment["GHOSTCOMPLETE_MODEL"] ?? "",
            "hasRuntimeSettings": runtimeSettings != nil,
            "logDir": settings.logsURL.path
        ])

        do {
            try process.run()
            self.process = process
            self.port = sidecarPort
            TraceLogger.shared.info("sidecar_process_started", fields: [
                "processId": Int(process.processIdentifier),
                "port": sidecarPort
            ])
        } catch {
            TraceLogger.shared.error("sidecar_process_start_failed", fields: ["error": error.localizedDescription])
            throw SidecarError.launchFailed(error.localizedDescription)
        }
    }

    func stop() {
        if let process {
            TraceLogger.shared.info("sidecar_process_terminate_requested", fields: [
                "processId": Int(process.processIdentifier),
                "isRunning": process.isRunning
            ])
            process.terminate()
        }
        process = nil
        port = nil
    }

    func complete(snapshot: FocusSnapshot, requestId: String, completion: @escaping @Sendable (Result<CompleteResponse, Error>) -> Void) {
        let request = CompleteRequest(
            requestId: requestId,
            context: snapshot.context,
            app: snapshot.app,
            selection: snapshot.selection
        )
        TraceLogger.shared.debug("sidecar_complete_post_prepared", fields: [
            "requestId": requestId,
            "contextLength": snapshot.context.count,
            "contextHash": snapshot.context.ghostCompleteSHA256,
            "appBundleId": snapshot.app.bundleId
        ])
        post(path: "/complete", body: request, completion: completion)
    }

    func learnAccepted(snapshot: FocusSnapshot, requestId: String, suggestion: String) {
        let request = LearnRequest(
            requestId: requestId,
            event: "accepted",
            contextHash: snapshot.context.ghostCompleteSHA256,
            suggestion: suggestion,
            app: snapshot.app
        )
        TraceLogger.shared.debug("sidecar_learn_post_prepared", fields: [
            "requestId": requestId,
            "suggestionLength": suggestion.count,
            "suggestionHash": suggestion.ghostCompleteSHA256,
            "appBundleId": snapshot.app.bundleId
        ])
        post(path: "/learn", body: request) { (_: Result<LearnResponse, Error>) in }
    }

    private func post<Request: Encodable, Response: Decodable & Sendable>(
        path: String,
        body: Request,
        completion: @escaping @Sendable (Result<Response, Error>) -> Void
    ) {
        guard let port else {
            TraceLogger.shared.warn("sidecar_post_missing_port", fields: ["path": path])
            completion(.failure(SidecarError.missingPort))
            return
        }

        var urlRequest = URLRequest(url: URL(string: "http://127.0.0.1:\(port)\(path)")!)
        urlRequest.httpMethod = "POST"
        urlRequest.timeoutInterval = 5
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        urlRequest.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        do {
            urlRequest.httpBody = try JSONEncoder().encode(body)
        } catch {
            TraceLogger.shared.error("sidecar_post_encode_failed", fields: [
                "path": path,
                "error": error.localizedDescription
            ])
            completion(.failure(error))
            return
        }

        let startedAt = Date()
        TraceLogger.shared.debug("sidecar_post_started", fields: ["path": path, "port": port])
        URLSession.shared.dataTask(with: urlRequest) { data, response, error in
            if let error {
                Task { @MainActor in
                    TraceLogger.shared.error("sidecar_post_failed", fields: [
                        "path": path,
                        "error": error.localizedDescription,
                        "latencyMs": Int(Date().timeIntervalSince(startedAt) * 1000)
                    ])
                }
                completion(.failure(error))
                return
            }
            guard let http = response as? HTTPURLResponse,
                  (200..<300).contains(http.statusCode),
                  let data
            else {
                let status = (response as? HTTPURLResponse)?.statusCode ?? -1
                Task { @MainActor in
                    TraceLogger.shared.error("sidecar_post_bad_response", fields: [
                        "path": path,
                        "status": status,
                        "latencyMs": Int(Date().timeIntervalSince(startedAt) * 1000)
                    ])
                }
                completion(.failure(SidecarError.badResponse))
                return
            }
            do {
                let decoded = try JSONDecoder().decode(Response.self, from: data)
                Task { @MainActor in
                    TraceLogger.shared.debug("sidecar_post_succeeded", fields: [
                        "path": path,
                        "status": http.statusCode,
                        "bytes": data.count,
                        "latencyMs": Int(Date().timeIntervalSince(startedAt) * 1000)
                    ])
                }
                completion(.success(decoded))
            } catch {
                Task { @MainActor in
                    TraceLogger.shared.error("sidecar_post_decode_failed", fields: [
                        "path": path,
                        "status": http.statusCode,
                        "bytes": data.count,
                        "error": error.localizedDescription,
                        "latencyMs": Int(Date().timeIntervalSince(startedAt) * 1000)
                    ])
                }
                completion(.failure(error))
            }
        }.resume()
    }

    private func sidecarScriptURL() -> URL? {
        if let override = ProcessInfo.processInfo.environment["GHOSTCOMPLETE_SIDECAR_PATH"] {
            return URL(fileURLWithPath: override)
        }

        if let bundled = Bundle.main.url(forResource: "ghostcomplete-sidecar", withExtension: nil, subdirectory: "ai-service/dist") {
            return bundled
        }

        if let bundled = Bundle.main.url(forResource: "index", withExtension: "js", subdirectory: "ai-service/dist") {
            return bundled
        }

        let cwd = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        let candidates = [
            cwd.appendingPathComponent("ai-service/dist/ghostcomplete-sidecar"),
            cwd.appendingPathComponent("ai-service/dist/index.js"),
            cwd.deletingLastPathComponent().appendingPathComponent("ai-service/dist/ghostcomplete-sidecar"),
            cwd.deletingLastPathComponent().appendingPathComponent("ai-service/dist/index.js"),
            cwd.deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("ai-service/dist/ghostcomplete-sidecar"),
            cwd.deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("ai-service/dist/index.js")
        ]
        return candidates.first { FileManager.default.fileExists(atPath: $0.path) }
    }

    private func sidecarCommand(for url: URL) -> SidecarCommand {
        if FileManager.default.isExecutableFile(atPath: url.path), url.pathExtension != "js" {
            return SidecarCommand(executableURL: url, arguments: [])
        }

        let bunURL = bunExecutableURL()
        return SidecarCommand(
            executableURL: bunURL,
            arguments: bunURL.lastPathComponent == "env" ? ["bun", url.path] : [url.path]
        )
    }

    private func configuredPort() -> Int {
        if let raw = ProcessInfo.processInfo.environment["GHOSTCOMPLETE_PORT"],
           let port = Int(raw),
           port > 0 {
            return port
        }
        return 50573
    }

    private func bunExecutableURL() -> URL {
        if let override = ProcessInfo.processInfo.environment["GHOSTCOMPLETE_BUN_PATH"] {
            return URL(fileURLWithPath: override)
        }

        let home = FileManager.default.homeDirectoryForCurrentUser
        let candidates = [
            home.appendingPathComponent(".bun/bin/bun").path,
            "/opt/homebrew/bin/bun",
            "/usr/local/bin/bun"
        ]

        if let path = candidates.first(where: { FileManager.default.isExecutableFile(atPath: $0) }) {
            return URL(fileURLWithPath: path)
        }

        return URL(fileURLWithPath: "/usr/bin/env")
    }
}

private struct LearnResponse: Decodable, Sendable {
    let ok: Bool
}

private struct SidecarCommand {
    let executableURL: URL
    let arguments: [String]
}
