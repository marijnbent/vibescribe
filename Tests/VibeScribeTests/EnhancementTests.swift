import XCTest
@testable import VibeScribeCore

@MainActor
final class EnhancementTests: XCTestCase {
    private let openRouterApiKeyKey = "VibeScribe.OpenRouterApiKey"
    private let openRouterModelKey = "VibeScribe.OpenRouterModel"
    private let enhancementPromptsKey = "VibeScribe.EnhancementPrompts"
    private let promptsKey = "VibeScribe.Prompts"
    private let shortcutsKey = "VibeScribe.Shortcuts"

    override func setUp() {
        super.setUp()
        UserDefaults.standard.removeObject(forKey: openRouterApiKeyKey)
        UserDefaults.standard.removeObject(forKey: openRouterModelKey)
        UserDefaults.standard.removeObject(forKey: enhancementPromptsKey)
        UserDefaults.standard.removeObject(forKey: promptsKey)
        UserDefaults.standard.removeObject(forKey: shortcutsKey)
    }

    override func tearDown() {
        UserDefaults.standard.removeObject(forKey: openRouterApiKeyKey)
        UserDefaults.standard.removeObject(forKey: openRouterModelKey)
        UserDefaults.standard.removeObject(forKey: enhancementPromptsKey)
        UserDefaults.standard.removeObject(forKey: promptsKey)
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

    // MARK: - Named Prompts

    func testPromptsDefaultToEmpty() {
        let state = AppState()
        XCTAssertTrue(state.prompts.isEmpty)
    }

    func testPromptsPersist() {
        let state = AppState()
        let prompt = PromptConfig(id: UUID(), name: "Fix grammar", content: "fix grammar")
        state.prompts.append(prompt)

        let restored = AppState()
        XCTAssertEqual(restored.prompts.count, 1)
        XCTAssertEqual(restored.prompts[0].name, "Fix grammar")
        XCTAssertEqual(restored.prompts[0].content, "fix grammar")
    }

    func testDeletePromptRemovesPrompt() {
        let state = AppState()
        let prompt = PromptConfig(id: UUID(), name: "Test", content: "test")
        state.prompts.append(prompt)
        state.deletePrompt(id: prompt.id)

        XCTAssertTrue(state.prompts.isEmpty)
    }

    func testDeletePromptClearsShortcutReferences() {
        let state = AppState()
        let prompt = PromptConfig(id: UUID(), name: "Test", content: "test")
        state.prompts.append(prompt)
        state.shortcuts[0].promptID = prompt.id

        state.deletePrompt(id: prompt.id)
        XCTAssertNil(state.shortcuts[0].promptID)
    }

    func testPromptContentForShortcutID() {
        let state = AppState()
        let prompt = PromptConfig(id: UUID(), name: "Test", content: "do the thing")
        state.prompts.append(prompt)
        state.shortcuts[0].promptID = prompt.id

        XCTAssertEqual(state.promptContent(forShortcutID: state.shortcuts[0].id), "do the thing")
    }

    func testPromptContentForShortcutIDReturnsNilWithNoPromptID() {
        let state = AppState()
        XCTAssertNil(state.promptContent(forShortcutID: state.shortcuts[0].id))
    }

    func testPromptContentForShortcutIDReturnsNilForDeletedPrompt() {
        let state = AppState()
        state.shortcuts[0].promptID = UUID() // points to nonexistent prompt
        XCTAssertNil(state.promptContent(forShortcutID: state.shortcuts[0].id))
    }

    // MARK: - Migration from old enhancementPrompts

    func testMigrationFromOldEnhancementPrompts() {
        // Seed old-format data
        let state1 = AppState()
        let shortcutID = state1.shortcuts[0].id

        let oldPrompts: [String: String] = [shortcutID.uuidString: "old prompt content"]
        let data = try! JSONEncoder().encode(oldPrompts)
        UserDefaults.standard.set(data, forKey: enhancementPromptsKey)
        // Remove new-format key so migration triggers
        UserDefaults.standard.removeObject(forKey: promptsKey)

        // Re-seed shortcuts so the shortcut ID matches
        let shortcutData = try! JSONEncoder().encode(state1.shortcuts)
        UserDefaults.standard.set(shortcutData, forKey: shortcutsKey)

        let state2 = AppState()
        XCTAssertEqual(state2.prompts.count, 1)
        XCTAssertEqual(state2.prompts[0].content, "old prompt content")
        XCTAssertEqual(state2.shortcuts[0].promptID, state2.prompts[0].id)
        // Old key should be cleaned up
        XCTAssertNil(UserDefaults.standard.data(forKey: enhancementPromptsKey))
    }

    // MARK: - Default Prompt

    func testDefaultPromptIsNotEmpty() {
        let prompt = PromptConfig.makeDefault()
        XCTAssertFalse(prompt.content.isEmpty)
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

    // MARK: - Missing Credentials with Enhancement Enabled

    func testEnhancementEnabledButMissingApiKeyLogsWarning() {
        let state = AppState()
        let prompt = PromptConfig(id: UUID(), name: "Fix", content: "fix it")
        state.prompts.append(prompt)
        state.shortcuts[0].promptID = prompt.id
        state.openRouterModel = "openai/gpt-4o-mini"

        XCTAssertNotNil(state.promptContent(forShortcutID: state.shortcuts[0].id))
        XCTAssertFalse(state.hasOpenRouterCredentials)
    }

    func testEnhancementEnabledButMissingModelLogsWarning() {
        let state = AppState()
        let prompt = PromptConfig(id: UUID(), name: "Fix", content: "fix it")
        state.prompts.append(prompt)
        state.shortcuts[0].promptID = prompt.id
        state.openRouterApiKey = "sk-test"

        XCTAssertNotNil(state.promptContent(forShortcutID: state.shortcuts[0].id))
        XCTAssertFalse(state.hasOpenRouterCredentials)
    }
}
