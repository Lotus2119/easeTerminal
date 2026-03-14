//
//  easeTerminalTests.swift
//  easeTerminalTests
//

import Testing
import Foundation
@testable import easeTerminal

// MARK: - Mock Keychain

/// In-memory keychain for testing - never touches the real macOS Keychain.
final class MockKeychain: KeychainStoring, @unchecked Sendable {
    private var store: [String: String] = [:]

    func saveAPIKey(_ key: String, forProvider account: String) throws {
        store[account] = key
    }

    func getAPIKey(forProvider account: String) -> String? {
        store[account]
    }

    func hasAPIKey(forProvider account: String) -> Bool {
        store[account] != nil
    }

    func deleteAPIKey(forProvider account: String) throws {
        store.removeValue(forKey: account)
    }

    func listStoredProviders() -> [String] {
        Array(store.keys).sorted()
    }
}

// MARK: - KeychainStoring Tests

@Suite("KeychainStoring")
struct KeychainStoringTests {

    @Test("Save and retrieve an API key")
    func saveAndRetrieve() throws {
        let keychain = MockKeychain()
        try keychain.saveAPIKey("sk-test-123", forProvider: "anthropic")
        #expect(keychain.getAPIKey(forProvider: "anthropic") == "sk-test-123")
    }

    @Test("hasAPIKey returns false when no key is stored")
    func hasAPIKeyFalse() {
        let keychain = MockKeychain()
        #expect(keychain.hasAPIKey(forProvider: "openai") == false)
    }

    @Test("hasAPIKey returns true after saving")
    func hasAPIKeyTrue() throws {
        let keychain = MockKeychain()
        try keychain.saveAPIKey("sk-openai", forProvider: "openai")
        #expect(keychain.hasAPIKey(forProvider: "openai") == true)
    }

    @Test("Delete removes a stored key")
    func deleteKey() throws {
        let keychain = MockKeychain()
        try keychain.saveAPIKey("sk-delete", forProvider: "anthropic")
        try keychain.deleteAPIKey(forProvider: "anthropic")
        #expect(keychain.hasAPIKey(forProvider: "anthropic") == false)
    }

    @Test("Overwrite replaces an existing key")
    func overwriteKey() throws {
        let keychain = MockKeychain()
        try keychain.saveAPIKey("old-key", forProvider: "anthropic")
        try keychain.saveAPIKey("new-key", forProvider: "anthropic")
        #expect(keychain.getAPIKey(forProvider: "anthropic") == "new-key")
    }

    @Test("listStoredProviders returns all saved accounts")
    func listProviders() throws {
        let keychain = MockKeychain()
        try keychain.saveAPIKey("k1", forProvider: "anthropic")
        try keychain.saveAPIKey("k2", forProvider: "openai")
        let providers = keychain.listStoredProviders()
        #expect(providers.contains("anthropic"))
        #expect(providers.contains("openai"))
        #expect(providers.count == 2)
    }
}

// MARK: - ContextSettings Tests

@Suite("ContextSettings")
struct ContextSettingsTests {

    /// Isolated UserDefaults to avoid polluting the real suite.
    private static func makeIsolatedDefaults() -> UserDefaults {
        let suiteName = "com.easeTerminal.tests.\(UUID().uuidString)"
        return UserDefaults(suiteName: suiteName)!
    }

    @Test("Default values match documented defaults")
    func defaultValues() {
        let settings = ContextSettings.default
        #expect(settings.maxTerminalLines == 200)
        #expect(settings.maxChatExchanges == 10)
        #expect(settings.maxFullTroubleshootEntries == 2)
        #expect(settings.maxTotalContextChars == 32000)
    }

    @Test("Equality holds for identical settings")
    func equality() {
        let a = ContextSettings.default
        let b = ContextSettings.default
        #expect(a == b)
    }

    @Test("Modified settings are not equal to default")
    func inequality() {
        var settings = ContextSettings.default
        settings.maxTerminalLines = 500
        #expect(settings != ContextSettings.default)
    }
}

// MARK: - ProviderStatus Tests

@Suite("ProviderStatus")
struct ProviderStatusTests {

    @Test("ready status is usable")
    func readyIsUsable() {
        #expect(ProviderStatus.ready.isUsable == true)
    }

    @Test("non-ready statuses are not usable")
    func nonReadyNotUsable() {
        let notUsable: [ProviderStatus] = [
            .notDetected, .noModels, .disconnected, .connecting, .error("oops")
        ]
        for status in notUsable {
            #expect(status.isUsable == false, "Expected \(status) to not be usable")
        }
    }

    @Test("displayText for error includes the message")
    func errorDisplayText() {
        let status = ProviderStatus.error("timeout")
        #expect(status.displayText.contains("timeout"))
    }

    @Test("Equatable: same cases are equal")
    func equatableSame() {
        #expect(ProviderStatus.ready == .ready)
        #expect(ProviderStatus.connecting == .connecting)
        #expect(ProviderStatus.error("x") == .error("x"))
    }

    @Test("Equatable: different cases are not equal")
    func equatableDifferent() {
        #expect(ProviderStatus.ready != .connecting)
        #expect(ProviderStatus.error("a") != .error("b"))
    }
}

// MARK: - AIModel Tests

@Suite("AIModel")
struct AIModelTests {

    @Test("isRecommendedDefault is true for qwen3-coder:30b")
    func recommendedDefaultMatch() {
        let model = AIModel(id: "qwen3-coder:30b", name: "Qwen3 Coder 30B", provider: "ollama")
        #expect(model.isRecommendedDefault == true)
    }

    @Test("isRecommendedDefault is false for other models")
    func recommendedDefaultNoMatch() {
        let model = AIModel(id: "llama3:8b", name: "Llama 3 8B", provider: "ollama")
        #expect(model.isRecommendedDefault == false)
    }

    @Test("isRecommendedDefault matches case-insensitively")
    func recommendedDefaultCaseInsensitive() {
        let model = AIModel(id: "Qwen3-Coder:30b", name: "Qwen3 Coder 30B", provider: "ollama")
        #expect(model.isRecommendedDefault == true)
    }

    @Test("AIModel conforms to Identifiable using id")
    func identifiable() {
        let model = AIModel(id: "gpt-4o", name: "GPT-4o", provider: "openai")
        #expect(model.id == "gpt-4o")
    }
}

// MARK: - ContextPackager Truncation Tests

@Suite("ContextPackager truncation")
struct ContextPackagerTruncationTests {

    /// Directly tests the truncation logic by calling passthrough, which delegates to the same
    /// private truncateContext method via the public passthrough function.
    @Test("Short context is returned unchanged")
    func shortContextPassthrough() async {
        let input = "hello world"
        let result = await ContextPackager.shared.passthrough(input, maxLength: 100)
        #expect(result == input)
    }

    @Test("Long context is truncated to maxLength characters plus prefix")
    func longContextTruncated() async {
        let input = String(repeating: "x", count: 500)
        let result = await ContextPackager.shared.passthrough(input, maxLength: 100)
        // The result should end with the last 100 'x' chars
        #expect(result.hasSuffix(String(repeating: "x", count: 100)))
        // And contain the truncation marker
        #expect(result.contains("[truncated]"))
    }

    @Test("Truncated result preserves the tail (most recent output)")
    func truncationPreservesTail() async {
        // Build a string where we can identify the tail
        let head = String(repeating: "a", count: 400)
        let tail = String(repeating: "z", count: 100)
        let input = head + tail
        let result = await ContextPackager.shared.passthrough(input, maxLength: 100)
        #expect(result.hasSuffix(tail))
    }

    @Test("Context exactly at maxLength is returned unchanged")
    func exactLengthPassthrough() async {
        let input = String(repeating: "y", count: 100)
        let result = await ContextPackager.shared.passthrough(input, maxLength: 100)
        #expect(result == input)
    }
}

// MARK: - UnifiedContext Tests

@Suite("UnifiedContext")
struct UnifiedContextTests {

    @Test("totalCharCount sums all three sections")
    func totalCharCount() {
        let ctx = UnifiedContext(
            terminalBuffer: "abc",
            troubleshootHistory: "de",
            chatHistory: "f",
            settings: .default
        )
        #expect(ctx.totalCharCount == 6)
    }

    @Test("isOverLimit is false when under the limit")
    func notOverLimit() {
        let ctx = UnifiedContext(
            terminalBuffer: "small",
            troubleshootHistory: "",
            chatHistory: "",
            settings: .default
        )
        #expect(ctx.isOverLimit == false)
    }

    @Test("isOverLimit is true when over the limit")
    func overLimit() {
        var settings = ContextSettings.default
        settings.maxTotalContextChars = 5
        let ctx = UnifiedContext(
            terminalBuffer: "123456",
            troubleshootHistory: "",
            chatHistory: "",
            settings: settings
        )
        #expect(ctx.isOverLimit == true)
    }

    @Test("buildContextMessage includes terminal buffer section")
    func contextMessageContainsTerminal() {
        let ctx = UnifiedContext(
            terminalBuffer: "git clone failed",
            troubleshootHistory: "",
            chatHistory: "",
            settings: .default
        )
        let msg = ctx.buildContextMessage()
        #expect(msg.contains("git clone failed"))
        #expect(msg.contains("Current Terminal Output"))
    }

    @Test("buildContextMessage is empty when all sections are empty")
    func contextMessageEmptyWhenNoSections() {
        let ctx = UnifiedContext(
            terminalBuffer: "",
            troubleshootHistory: "",
            chatHistory: "",
            settings: .default
        )
        #expect(ctx.buildContextMessage().isEmpty)
    }
}

// MARK: - Command Extraction Tests (via AIPanelState)

/// AIPanelState.extractCommands is private; we test it indirectly through the public
/// troubleshootResponse flow. For direct regex coverage we replicate the same pattern here.
@Suite("Command extraction regex")
struct CommandExtractionTests {

    /// Mirrors the extraction logic from AIPanelState so it can be unit-tested without
    /// instantiating the full UI state machine.
    private func extractCommands(from response: String) -> [String] {
        var commands: [String] = []

        let codeBlockPattern = #"```(?:bash|sh|zsh|shell)?\n?([\s\S]*?)```"#
        if let regex = try? NSRegularExpression(pattern: codeBlockPattern) {
            let range = NSRange(response.startIndex..., in: response)
            for match in regex.matches(in: response, range: range) {
                if let codeRange = Range(match.range(at: 1), in: response) {
                    let code = String(response[codeRange]).trimmingCharacters(in: .whitespacesAndNewlines)
                    let lines = code.components(separatedBy: .newlines)
                        .map { $0.trimmingCharacters(in: .whitespaces) }
                        .filter { !$0.isEmpty && !$0.hasPrefix("#") }
                    commands.append(contentsOf: lines)
                }
            }
        }

        let inlinePattern = #"`([^`]+)`"#
        let commandPrefixes = ["cd ", "ls", "mkdir", "rm ", "cp ", "mv ", "cat ", "echo ",
                               "npm ", "yarn ", "pnpm ", "npx ", "node ", "python", "pip ",
                               "git ", "brew ", "cargo ", "rustc", "go ", "make", "cmake",
                               "docker ", "kubectl ", "terraform ", "aws ", "gcloud ",
                               "sudo ", "chmod ", "chown ", "curl ", "wget "]
        if let regex = try? NSRegularExpression(pattern: inlinePattern) {
            let range = NSRange(response.startIndex..., in: response)
            for match in regex.matches(in: response, range: range) {
                if let codeRange = Range(match.range(at: 1), in: response) {
                    let code = String(response[codeRange]).trimmingCharacters(in: .whitespaces)
                    if commandPrefixes.contains(where: { code.lowercased().hasPrefix($0) }),
                       !commands.contains(code) {
                        commands.append(code)
                    }
                }
            }
        }

        return commands
    }

    @Test("Extracts command from bash code block")
    func bashCodeBlock() {
        let response = """
        Run this:
        ```bash
        git clone https://github.com/example/repo
        ```
        """
        let commands = extractCommands(from: response)
        #expect(commands.contains("git clone https://github.com/example/repo"))
    }

    @Test("Extracts multiple commands from a single code block")
    func multipleCommandsInBlock() {
        let response = """
        Try these:
        ```sh
        npm install
        npm run build
        ```
        """
        let commands = extractCommands(from: response)
        #expect(commands.contains("npm install"))
        #expect(commands.contains("npm run build"))
    }

    @Test("Skips comment lines inside code blocks")
    func skipsComments() {
        let response = """
        ```bash
        # This is a comment
        git status
        ```
        """
        let commands = extractCommands(from: response)
        #expect(!commands.contains("# This is a comment"))
        #expect(commands.contains("git status"))
    }

    @Test("Extracts inline command that starts with a known prefix")
    func inlineCommand() {
        let response = "Run `brew install ripgrep` to install."
        let commands = extractCommands(from: response)
        #expect(commands.contains("brew install ripgrep"))
    }

    @Test("Does not extract inline code that is not a command")
    func inlineNonCommand() {
        let response = "The error is in `myFunction()`."
        let commands = extractCommands(from: response)
        #expect(commands.isEmpty)
    }

    @Test("Does not duplicate commands already found in code blocks")
    func noDuplicatesFromInline() {
        let response = """
        Run `git status` or:
        ```bash
        git status
        ```
        """
        let commands = extractCommands(from: response)
        #expect(commands.filter { $0 == "git status" }.count == 1)
    }

    @Test("Handles response with no code blocks gracefully")
    func noCodeBlocks() {
        let response = "There are no issues with your code."
        let commands = extractCommands(from: response)
        #expect(commands.isEmpty)
    }

    @Test("Extracts from unlabeled code block")
    func unlabeledCodeBlock() {
        let response = """
        ```
        docker build -t myapp .
        ```
        """
        let commands = extractCommands(from: response)
        #expect(commands.contains("docker build -t myapp ."))
    }
}
