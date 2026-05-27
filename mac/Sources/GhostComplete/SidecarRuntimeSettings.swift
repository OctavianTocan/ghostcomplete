import Foundation

struct SidecarRuntimeSettings: Codable, Equatable {
    var provider: String? = nil
    var model: String?
    var timeoutMs: Int?
    var maxOutputTokens: Int?
    var temperature: Double?

    var isEmpty: Bool {
        provider == nil && model == nil && timeoutMs == nil && maxOutputTokens == nil && temperature == nil
    }

    static func fromEnvironment(_ environment: [String: String] = ProcessInfo.processInfo.environment) -> SidecarRuntimeSettings {
        SidecarRuntimeSettings(
            provider: providerValue(environment["GHOSTCOMPLETE_PROVIDER"]),
            model: nonEmpty(environment["GHOSTCOMPLETE_MODEL"]),
            timeoutMs: intValue(environment["GHOSTCOMPLETE_TIMEOUT_MS"]),
            maxOutputTokens: intValue(environment["GHOSTCOMPLETE_MAX_OUTPUT_TOKENS"]),
            temperature: doubleValue(environment["GHOSTCOMPLETE_TEMPERATURE"])
        )
    }

    static func load(from url: URL) -> SidecarRuntimeSettings? {
        guard let data = try? Data(contentsOf: url) else {
            return nil
        }
        return try? JSONDecoder().decode(SidecarRuntimeSettings.self, from: data)
    }

    func write(to url: URL) throws {
        let data = try JSONEncoder.pretty.encode(self)
        try data.write(to: url, options: [.atomic])
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    }

    func apply(to environment: inout [String: String], overridingExisting: Bool = false) {
        set("GHOSTCOMPLETE_PROVIDER", value: provider, in: &environment, overridingExisting: overridingExisting)
        set("GHOSTCOMPLETE_MODEL", value: model, in: &environment, overridingExisting: overridingExisting)
        set("GHOSTCOMPLETE_TIMEOUT_MS", value: timeoutMs.map { String($0) }, in: &environment, overridingExisting: overridingExisting)
        set("GHOSTCOMPLETE_MAX_OUTPUT_TOKENS", value: maxOutputTokens.map { String($0) }, in: &environment, overridingExisting: overridingExisting)
        set("GHOSTCOMPLETE_TEMPERATURE", value: temperature.map { String($0) }, in: &environment, overridingExisting: overridingExisting)
    }

    var traceFields: [String: Any] {
        [
            "provider": provider ?? "",
            "model": model ?? "",
            "hasProvider": provider?.isEmpty == false,
            "hasModel": model?.isEmpty == false,
            "hasTimeoutMs": timeoutMs != nil,
            "hasMaxOutputTokens": maxOutputTokens != nil,
            "hasTemperature": temperature != nil
        ]
    }

    func fillingDefaultProvider(openRouterKey: String?, gatewayKey: String?) -> SidecarRuntimeSettings {
        guard provider == nil else {
            return self
        }
        var copy = self
        copy.provider = Self.defaultProvider(openRouterKey: openRouterKey, gatewayKey: gatewayKey)
        return copy
    }

    func fillingMissing(from fallback: SidecarRuntimeSettings) -> SidecarRuntimeSettings {
        var copy = self
        if copy.provider == nil {
            copy.provider = fallback.provider
        }
        if copy.model == nil {
            copy.model = fallback.model
        }
        if copy.timeoutMs == nil {
            copy.timeoutMs = fallback.timeoutMs
        }
        if copy.maxOutputTokens == nil {
            copy.maxOutputTokens = fallback.maxOutputTokens
        }
        if copy.temperature == nil {
            copy.temperature = fallback.temperature
        }
        return copy
    }

    static func defaultProvider(openRouterKey: String?, gatewayKey: String?) -> String? {
        if nonEmpty(openRouterKey) != nil {
            return "openrouter"
        }
        if nonEmpty(gatewayKey) != nil {
            return "gateway"
        }
        return nil
    }

    static func defaultModel(for provider: String?) -> String {
        switch provider?.lowercased() {
        case "openrouter":
            return "google/gemini-2.0-flash-lite-001"
        default:
            return "google/gemini-2.0-flash-lite"
        }
    }

    static func isKnownDefaultModel(_ model: String) -> Bool {
        [
            "google/gemini-2.0-flash-lite",
            "google/gemini-2.0-flash-lite-001"
        ].contains(model)
    }

    private static func nonEmpty(_ value: String?) -> String? {
        guard let value = value?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty else {
            return nil
        }
        return value
    }

    private static func providerValue(_ value: String?) -> String? {
        guard let value = nonEmpty(value)?.lowercased() else {
            return nil
        }
        switch value {
        case "openrouter", "open-router":
            return "openrouter"
        case "gateway", "vercel", "ai-gateway":
            return "gateway"
        default:
            return nil
        }
    }

    private static func intValue(_ value: String?) -> Int? {
        guard let value = nonEmpty(value), let parsed = Int(value), parsed > 0 else {
            return nil
        }
        return parsed
    }

    private static func doubleValue(_ value: String?) -> Double? {
        guard let value = nonEmpty(value), let parsed = Double(value), parsed.isFinite else {
            return nil
        }
        return parsed
    }

    private func set(_ key: String, value: String?, in environment: inout [String: String], overridingExisting: Bool) {
        guard let value else {
            return
        }
        if !overridingExisting, environment[key]?.isEmpty == false {
            return
        }
        environment[key] = value
    }
}

private extension JSONEncoder {
    static var pretty: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }
}
