import XCTest
@testable import GhostComplete

final class SidecarRuntimeSettingsTests: XCTestCase {
    func testLoadsOnlyKnownEnvironmentSettings() {
        let settings = SidecarRuntimeSettings.fromEnvironment([
            "GHOSTCOMPLETE_PROVIDER": "openrouter",
            "GHOSTCOMPLETE_MODEL": "morph/morph-v3-fast",
            "GHOSTCOMPLETE_TIMEOUT_MS": "4500",
            "GHOSTCOMPLETE_MAX_OUTPUT_TOKENS": "32",
            "GHOSTCOMPLETE_TEMPERATURE": "0.15"
        ])

        XCTAssertEqual(settings.provider, "openrouter")
        XCTAssertEqual(settings.model, "morph/morph-v3-fast")
        XCTAssertEqual(settings.timeoutMs, 4500)
        XCTAssertEqual(settings.maxOutputTokens, 32)
        XCTAssertEqual(settings.temperature, 0.15)
    }

    func testAppliesSettingsWithoutOverridingExplicitEnvironment() {
        let settings = SidecarRuntimeSettings(
            provider: "openrouter",
            model: "morph/morph-v3-fast",
            timeoutMs: 4500,
            maxOutputTokens: 32,
            temperature: 0.15
        )
        var environment = [
            "GHOSTCOMPLETE_PROVIDER": "gateway",
            "GHOSTCOMPLETE_MODEL": "openai/gpt-4o-mini"
        ]

        settings.apply(to: &environment)

        XCTAssertEqual(environment["GHOSTCOMPLETE_PROVIDER"], "gateway")
        XCTAssertEqual(environment["GHOSTCOMPLETE_MODEL"], "openai/gpt-4o-mini")
        XCTAssertEqual(environment["GHOSTCOMPLETE_TIMEOUT_MS"], "4500")
        XCTAssertEqual(environment["GHOSTCOMPLETE_MAX_OUTPUT_TOKENS"], "32")
        XCTAssertEqual(environment["GHOSTCOMPLETE_TEMPERATURE"], "0.15")
    }

    func testInfersDefaultProviderFromAvailableKey() {
        XCTAssertEqual(
            SidecarRuntimeSettings.defaultProvider(openRouterKey: "sk-or", gatewayKey: "gateway"),
            "openrouter"
        )
        XCTAssertEqual(
            SidecarRuntimeSettings.defaultProvider(openRouterKey: nil, gatewayKey: "gateway"),
            "gateway"
        )
        XCTAssertNil(SidecarRuntimeSettings.defaultProvider(openRouterKey: "", gatewayKey: ""))
    }

    func testFillsMissingProviderWithoutOverridingExplicitProvider() {
        let inferred = SidecarRuntimeSettings(model: "google/gemini-2.0-flash-lite")
            .fillingDefaultProvider(openRouterKey: nil, gatewayKey: "gateway")
        XCTAssertEqual(inferred.provider, "gateway")

        let explicit = SidecarRuntimeSettings(provider: "openrouter", model: nil)
            .fillingDefaultProvider(openRouterKey: nil, gatewayKey: "gateway")
        XCTAssertEqual(explicit.provider, "openrouter")
    }
}
