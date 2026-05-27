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
            return
        }

        guard let scriptURL = sidecarScriptURL() else {
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
        environment["GHOSTCOMPLETE_PORT"] = String(sidecarPort)
        if let apiKey, !apiKey.isEmpty {
            environment["AI_GATEWAY_API_KEY"] = apiKey
        }
        process.environment = environment

        do {
            try process.run()
            self.process = process
            self.port = sidecarPort
        } catch {
            throw SidecarError.launchFailed(error.localizedDescription)
        }
    }

    func stop() {
        process?.terminate()
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
        post(path: "/learn", body: request) { (_: Result<LearnResponse, Error>) in }
    }

    private func post<Request: Encodable, Response: Decodable & Sendable>(
        path: String,
        body: Request,
        completion: @escaping @Sendable (Result<Response, Error>) -> Void
    ) {
        guard let port else {
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
            completion(.failure(error))
            return
        }

        URLSession.shared.dataTask(with: urlRequest) { data, response, error in
            if let error {
                completion(.failure(error))
                return
            }
            guard let http = response as? HTTPURLResponse,
                  (200..<300).contains(http.statusCode),
                  let data
            else {
                completion(.failure(SidecarError.badResponse))
                return
            }
            do {
                completion(.success(try JSONDecoder().decode(Response.self, from: data)))
            } catch {
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
