import AppKit
import Foundation

if CommandLine.arguments.contains("--store-api-key-and-exit") {
    let environment = ProcessInfo.processInfo.environment
    let gatewayKey = environment[KeychainStore.gatewayAccount] ?? ""
    let openRouterKey = environment[KeychainStore.openRouterAccount] ?? ""
    guard !gatewayKey.isEmpty || !openRouterKey.isEmpty else {
        fputs("AI_GATEWAY_API_KEY or OPENROUTER_API_KEY is not set.\n", stderr)
        exit(2)
    }

    do {
        let settings = SettingsStore()
        try settings.ensureApplicationSupport()
        TraceLogger.shared.configure(fileURL: settings.appLogURL)
        let keychain = KeychainStore()
        if !gatewayKey.isEmpty {
            try keychain.setString(gatewayKey, account: KeychainStore.gatewayAccount)
        }
        if !openRouterKey.isEmpty {
            try keychain.setString(openRouterKey, account: KeychainStore.openRouterAccount)
        }
        let environmentRuntimeSettings = SidecarRuntimeSettings
            .fromEnvironment()
            .fillingDefaultProvider(openRouterKey: openRouterKey, gatewayKey: gatewayKey)
        let existingRuntimeSettings = SidecarRuntimeSettings.load(from: settings.sidecarSettingsURL)
        let runtimeSettings = (existingRuntimeSettings ?? SidecarRuntimeSettings())
            .fillingMissing(from: environmentRuntimeSettings)
        if !runtimeSettings.isEmpty {
            try runtimeSettings.write(to: settings.sidecarSettingsURL)
            TraceLogger.shared.info("sidecar_runtime_settings_saved", fields: runtimeSettings.traceFields)
        }
        TraceLogger.shared.info("api_key_seeded_to_keychain", fields: [
            "service": KeychainStore.gatewayService,
            "hasGatewayKey": !gatewayKey.isEmpty,
            "hasOpenRouterKey": !openRouterKey.isEmpty
        ])
        TraceLogger.shared.flush()
        print("Stored GhostComplete API key(s) in the Keychain item.")
        exit(0)
    } catch {
        fputs("Could not store GhostComplete API key(s) in Keychain: \(error)\n", stderr)
        exit(1)
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.run()
