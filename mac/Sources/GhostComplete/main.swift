import AppKit
import Foundation

if CommandLine.arguments.contains("--store-api-key-and-exit") {
    let key = ProcessInfo.processInfo.environment[KeychainStore.gatewayAccount] ?? ""
    guard !key.isEmpty else {
        fputs("AI_GATEWAY_API_KEY is not set.\n", stderr)
        exit(2)
    }

    do {
        let settings = SettingsStore()
        try settings.ensureApplicationSupport()
        TraceLogger.shared.configure(fileURL: settings.appLogURL)
        try KeychainStore().setString(key, account: KeychainStore.gatewayAccount)
        let runtimeSettings = SidecarRuntimeSettings.fromEnvironment()
        if !runtimeSettings.isEmpty {
            try runtimeSettings.write(to: settings.sidecarSettingsURL)
            TraceLogger.shared.info("sidecar_runtime_settings_saved", fields: runtimeSettings.traceFields)
        }
        TraceLogger.shared.info("api_key_seeded_to_keychain", fields: [
            "service": KeychainStore.gatewayService,
            "account": KeychainStore.gatewayAccount
        ])
        TraceLogger.shared.flush()
        print("Stored AI_GATEWAY_API_KEY in the GhostComplete Keychain item.")
        exit(0)
    } catch {
        fputs("Could not store AI_GATEWAY_API_KEY in Keychain: \(error)\n", stderr)
        exit(1)
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.run()
