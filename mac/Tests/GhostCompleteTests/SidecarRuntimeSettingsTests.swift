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

    func testCanApplySettingsOverExplicitEnvironmentForUISaves() {
        let settings = SidecarRuntimeSettings(
            provider: "openrouter",
            model: "morph/morph-v3-fast"
        )
        var environment = [
            "GHOSTCOMPLETE_PROVIDER": "gateway",
            "GHOSTCOMPLETE_MODEL": "google/gemini-2.0-flash-lite"
        ]

        settings.apply(to: &environment, overridingExisting: true)

        XCTAssertEqual(environment["GHOSTCOMPLETE_PROVIDER"], "openrouter")
        XCTAssertEqual(environment["GHOSTCOMPLETE_MODEL"], "morph/morph-v3-fast")
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

    func testUsesProviderSpecificDefaultModels() {
        XCTAssertEqual(SidecarRuntimeSettings.defaultModel(for: "openrouter"), "google/gemini-2.0-flash-lite-001")
        XCTAssertEqual(SidecarRuntimeSettings.defaultModel(for: "gateway"), "google/gemini-2.0-flash-lite")
        XCTAssertTrue(SidecarRuntimeSettings.isKnownDefaultModel("google/gemini-2.0-flash-lite"))
        XCTAssertTrue(SidecarRuntimeSettings.isKnownDefaultModel("google/gemini-2.0-flash-lite-001"))
        XCTAssertFalse(SidecarRuntimeSettings.isKnownDefaultModel("custom/model"))
    }

    func testFillsMissingProviderWithoutOverridingExplicitProvider() {
        let inferred = SidecarRuntimeSettings(model: "google/gemini-2.0-flash-lite")
            .fillingDefaultProvider(openRouterKey: nil, gatewayKey: "gateway")
        XCTAssertEqual(inferred.provider, "gateway")

        let explicit = SidecarRuntimeSettings(provider: "openrouter", model: nil)
            .fillingDefaultProvider(openRouterKey: nil, gatewayKey: "gateway")
        XCTAssertEqual(explicit.provider, "openrouter")
    }

    func testFillsMissingRuntimeSettingsWithoutOverwritingSavedValues() {
        let saved = SidecarRuntimeSettings(provider: "openrouter", model: "google/gemini-2.0-flash-lite-001")
        let environment = SidecarRuntimeSettings(
            provider: "gateway",
            model: "google/gemini-2.0-flash-lite",
            timeoutMs: 4500,
            maxOutputTokens: 32,
            temperature: 0.15
        )

        let merged = saved.fillingMissing(from: environment)

        XCTAssertEqual(merged.provider, "openrouter")
        XCTAssertEqual(merged.model, "google/gemini-2.0-flash-lite-001")
        XCTAssertEqual(merged.timeoutMs, 4500)
        XCTAssertEqual(merged.maxOutputTokens, 32)
        XCTAssertEqual(merged.temperature, 0.15)
    }
}
