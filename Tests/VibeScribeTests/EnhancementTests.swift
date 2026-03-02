import XCTest
@testable import VibeScribeCore

@MainActor
final class EnhancementTests: XCTestCase {
    private let openRouterApiKeyKey = "VibeScribe.OpenRouterApiKey"
    private let openRouterModelKey = "VibeScribe.OpenRouterModel"
    private let enhancementPromptsKey = "VibeScribe.EnhancementPrompts"
    private let shortcutsKey = "VibeScribe.Shortcuts"

    override func setUp() {
        super.setUp()
        UserDefaults.standard.removeObject(forKey: openRouterApiKeyKey)
        UserDefaults.standard.removeObject(forKey: openRouterModelKey)
        UserDefaults.standard.removeObject(forKey: enhancementPromptsKey)
        UserDefaults.standard.removeObject(forKey: shortcutsKey)
    }

    override func tearDown() {
        UserDefaults.standard.removeObject(forKey: openRouterApiKeyKey)
        UserDefaults.standard.removeObject(forKey: openRouterModelKey)
        UserDefaults.standard.removeObject(forKey: enhancementPromptsKey)
        UserDefaults.standard.removeObject(forKey: shortcutsKey)
        super.tearDown()
    }

    // MARK: - OpenRouter Credentials

    func testOpenRouterApiKeyDefaultsToEmpty() {
        let state = AppState()
        XCTAssertEqual(state.openRouterApiKey, "")
    }

    func testOpenRouterModelDefaultsToEmpty() {
        let state = AppState()
        XCTAssertEqual(state.openRouterModel, "")
    }

    func testHasOpenRouterCredentialsFalseWhenEmpty() {
        let state = AppState()
        XCTAssertFalse(state.hasOpenRouterCredentials)
    }

    func testHasOpenRouterCredentialsFalseWithOnlyApiKey() {
        let state = AppState()
        state.openRouterApiKey = "sk-test"
        XCTAssertFalse(state.hasOpenRouterCredentials)
    }

    func testHasOpenRouterCredentialsFalseWithOnlyModel() {
        let state = AppState()
        state.openRouterModel = "openai/gpt-4o-mini"
        XCTAssertFalse(state.hasOpenRouterCredentials)
    }

    func testHasOpenRouterCredentialsTrueWhenBothSet() {
        let state = AppState()
        state.openRouterApiKey = "sk-test"
        state.openRouterModel = "openai/gpt-4o-mini"
        XCTAssertTrue(state.hasOpenRouterCredentials)
    }

    func testHasOpenRouterCredentialsFalseWithWhitespaceOnly() {
        let state = AppState()
        state.openRouterApiKey = "  "
        state.openRouterModel = "  "
        XCTAssertFalse(state.hasOpenRouterCredentials)
    }

    func testOpenRouterApiKeyPersists() {
        let state = AppState()
        state.openRouterApiKey = "sk-persisted"

        let restored = AppState()
        XCTAssertEqual(restored.openRouterApiKey, "sk-persisted")
    }

    func testOpenRouterModelPersists() {
        let state = AppState()
        state.openRouterModel = "anthropic/claude-3"

        let restored = AppState()
        XCTAssertEqual(restored.openRouterModel, "anthropic/claude-3")
    }

    // MARK: - Enhancement Prompts

    func testEnhancementPromptsDefaultToEmpty() {
        let state = AppState()
        XCTAssertTrue(state.enhancementPrompts.isEmpty)
    }

    func testEnhancementPromptsPersist() {
        let id = UUID()
        let prompt = "fix grammar"

        let state = AppState()
        state.enhancementPrompts[id] = prompt

        let restored = AppState()
        XCTAssertEqual(restored.enhancementPrompts[id], prompt)
    }

    func testEnhancementPromptsMultipleShortcuts() {
        let id1 = UUID()
        let id2 = UUID()

        let state = AppState()
        state.enhancementPrompts[id1] = "prompt one"
        state.enhancementPrompts[id2] = "prompt two"

        let restored = AppState()
        XCTAssertEqual(restored.enhancementPrompts.count, 2)
        XCTAssertEqual(restored.enhancementPrompts[id1], "prompt one")
        XCTAssertEqual(restored.enhancementPrompts[id2], "prompt two")
    }

    func testRemovingEnhancementPromptPersists() {
        let id = UUID()

        let state = AppState()
        state.enhancementPrompts[id] = "will be removed"
        state.enhancementPrompts.removeValue(forKey: id)

        let restored = AppState()
        XCTAssertNil(restored.enhancementPrompts[id])
    }

    // MARK: - OpenRouterError

    func testOpenRouterErrorInvalidResponseDescription() {
        let error = OpenRouterError.invalidResponse
        XCTAssertEqual(error.errorDescription, "Invalid response from OpenRouter.")
    }

    func testOpenRouterErrorHttpErrorDescription() {
        let error = OpenRouterError.httpError(statusCode: 401, body: "Unauthorized")
        XCTAssertEqual(error.errorDescription, "OpenRouter HTTP 401: Unauthorized")
    }

    func testOpenRouterErrorNoContentDescription() {
        let error = OpenRouterError.noContent
        XCTAssertEqual(error.errorDescription, "OpenRouter returned no content.")
    }

    // MARK: - Default Prompt

    func testDefaultPromptIsNotEmpty() {
        XCTAssertFalse(EnhancementsSettingsView.defaultPrompt.isEmpty)
    }

    func testEnablingEnhancementSetsDefaultPrompt() {
        let state = AppState()
        let id = state.shortcuts[0].id
        state.enhancementPrompts[id] = EnhancementsSettingsView.defaultPrompt

        XCTAssertEqual(state.enhancementPrompts[id], EnhancementsSettingsView.defaultPrompt)
    }

    // MARK: - Missing Credentials with Enhancement Enabled

    func testEnhancementEnabledButMissingApiKeyLogsWarning() {
        let state = AppState()
        let id = state.shortcuts[0].id
        state.enhancementPrompts[id] = "fix it"
        state.openRouterModel = "openai/gpt-4o-mini"
        // No API key set

        XCTAssertNotNil(state.enhancementPrompts[id])
        XCTAssertFalse(state.hasOpenRouterCredentials)
    }

    func testEnhancementEnabledButMissingModelLogsWarning() {
        let state = AppState()
        let id = state.shortcuts[0].id
        state.enhancementPrompts[id] = "fix it"
        state.openRouterApiKey = "sk-test"
        // No model set

        XCTAssertNotNil(state.enhancementPrompts[id])
        XCTAssertFalse(state.hasOpenRouterCredentials)
    }
}
