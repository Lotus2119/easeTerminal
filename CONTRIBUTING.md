# Contributing to easeTerminal

Thank you for your interest in contributing to easeTerminal! This document explains the AI provider architecture and how to add new providers.

## Architecture Overview

easeTerminal uses a **local-first AI architecture**:

- **Local inference is the DEFAULT** - No API key or internet required
- **Cloud providers are OPTIONAL** power-ups that users can enable
- **All new features must work in local mode first** - Cloud is always additive

### Operating Modes

1. **Local Mode (Default)**
   - Single Ollama model handles both context packaging and reasoning
   - Default model: `qwen3-coder:30b` (MoE with 3.3B active params)
   - No configuration required beyond installing Ollama

2. **Hybrid Mode (Optional)**
   - Local Ollama handles context packaging (terminal data stays local)
   - Cloud provider handles reasoning
   - Requires user's own API key

### The Pipeline

```
Terminal Output → ContextPackager (always local) → ReasoningProvider (local OR cloud)
```

The `ContextPackager` always uses local Ollama to extract key information from terminal output. This ensures terminal data never leaves the user's machine unless they explicitly choose cloud reasoning.

The `ReasoningProvider` protocol is implemented by both `OllamaProvider` (local) and cloud providers (Claude, OpenAI). The pipeline doesn't care which implementation is active.

## Core Protocols

### ReasoningProvider

Both local and cloud providers conform to this protocol:

```swift
public protocol ReasoningProvider: AnyObject, Sendable {
    static var providerID: String { get }
    static var displayName: String { get }
    static var isCloudProvider: Bool { get }
    
    var status: ProviderStatus { get }
    var selectedModel: AIModel? { get set }
    var isReady: Bool { get }
    
    func testConnection() async throws -> Bool
    
    func reason(
        context: String,
        userQuery: String?,
        conversationHistory: [ConversationMessage],
        maxTokens: Int
    ) async throws -> AICompletionResult
    
    func complete(
        messages: [ConversationMessage],
        systemPrompt: String?,
        maxTokens: Int
    ) async throws -> AICompletionResult
}
```

### LocalInferenceProvider

For local inference providers (Ollama, LlamaCpp, LM Studio):

```swift
public protocol LocalInferenceProvider: ReasoningProvider {
    var baseURL: URL { get set }
    func fetchAvailableModels() async throws -> [AIModel]
    func isServerRunning() async -> Bool
}
```

**Key requirement:** Models must be fetched dynamically from the local API at runtime. Never hardcode model lists for local providers.

### CloudReasoningProvider

For cloud providers (Claude, OpenAI, Gemini):

```swift
public protocol CloudReasoningProvider: ReasoningProvider {
    var hasAPIKey: Bool { get }
    func setAPIKey(_ key: String) throws
    func clearAPIKey() throws
    static var availableModels: [AIModel] { get }
}
```

**Key requirements:**
- API keys stored in Keychain via `KeychainHelper`, never in UserDefaults or plist
- API keys never logged
- Clearly marked as optional in UI

## Adding a New Local Provider

Example: Adding LM Studio support

### 1. Create the Provider Class

Create `easeTerminal/AI/Providers/LMStudioProvider.swift`:

```swift
import Foundation

public final class LMStudioProvider: LocalInferenceProvider, @unchecked Sendable {
    
    public static let providerID = "lmstudio"
    public static let displayName = "LM Studio (Local)"
    public static let isCloudProvider = false
    
    public var baseURL: URL
    public var selectedModel: AIModel?
    
    private var _status: ProviderStatus = .disconnected
    public var status: ProviderStatus { _status }
    
    public var isReady: Bool {
        if case .ready = _status { return true }
        return false
    }
    
    public init(baseURL: URL = URL(string: "http://localhost:1234")!) {
        self.baseURL = baseURL
    }
    
    public func isServerRunning() async -> Bool {
        // Check if LM Studio server is responding
        let url = baseURL.appendingPathComponent("v1/models")
        var request = URLRequest(url: url)
        request.timeoutInterval = 5
        
        do {
            let (_, response) = try await URLSession.shared.data(for: request)
            return (response as? HTTPURLResponse)?.statusCode == 200
        } catch {
            return false
        }
    }
    
    public func fetchAvailableModels() async throws -> [AIModel] {
        // Fetch from LM Studio API - NEVER hardcode
        let url = baseURL.appendingPathComponent("v1/models")
        let (data, _) = try await URLSession.shared.data(from: url)
        
        // Parse OpenAI-compatible response
        struct ModelsResponse: Codable {
            let data: [ModelInfo]
            struct ModelInfo: Codable {
                let id: String
            }
        }
        
        let response = try JSONDecoder().decode(ModelsResponse.self, from: data)
        return response.data.map { info in
            AIModel(id: info.id, name: info.id, provider: Self.providerID)
        }
    }
    
    public func testConnection() async throws -> Bool {
        _status = .connecting
        guard await isServerRunning() else {
            _status = .notInstalled
            throw AIProviderError.connectionFailed("LM Studio not running")
        }
        let models = try await fetchAvailableModels()
        _status = models.isEmpty ? .noModels : .ready
        return !models.isEmpty
    }
    
    public func reason(
        context: String,
        userQuery: String?,
        conversationHistory: [ConversationMessage],
        maxTokens: Int
    ) async throws -> AICompletionResult {
        // Use OpenAI-compatible chat endpoint
        // ... implementation
    }
    
    public func complete(
        messages: [ConversationMessage],
        systemPrompt: String?,
        maxTokens: Int
    ) async throws -> AICompletionResult {
        // Use OpenAI-compatible chat endpoint
        // ... implementation
    }
}
```

### 2. Register the Provider

Add registration in `ProviderManager.swift`:

```swift
private func registerBuiltInProviders() {
    OllamaProvider.register()
    LMStudioProvider.register() // Add this
    ClaudeProvider.register()
    OpenAIProvider.register()
}
```

Add the registration extension to your provider:

```swift
extension LMStudioProvider {
    public static func register() {
        ProviderRegistry.shared.registerLocalProvider(id: providerID) {
            LMStudioProvider()
        }
    }
}
```

### 3. Update Settings UI (if needed)

The settings UI automatically discovers registered providers via `ProviderRegistry`, so minimal changes are needed. You may want to add provider-specific configuration options.

## Adding a New Cloud Provider

Example: Adding Google Gemini

### 1. Create the Provider Class

Create `easeTerminal/AI/Providers/GeminiProvider.swift`:

```swift
import Foundation

public final class GeminiProvider: CloudReasoningProvider, @unchecked Sendable {
    
    public static let providerID = "google"
    public static let displayName = "Gemini (Google)"
    public static let isCloudProvider = true
    
    /// Available Gemini models (cloud providers can hardcode this)
    public static let availableModels: [AIModel] = [
        AIModel(id: "gemini-2.0-pro", name: "Gemini 2.0 Pro", provider: providerID),
        AIModel(id: "gemini-2.0-flash", name: "Gemini 2.0 Flash", provider: providerID),
    ]
    
    public var selectedModel: AIModel?
    
    private var _status: ProviderStatus = .disconnected
    public var status: ProviderStatus { _status }
    
    public var isReady: Bool {
        hasAPIKey && selectedModel != nil && _status == .ready
    }
    
    public var hasAPIKey: Bool {
        KeychainHelper.shared.hasAPIKey(forProvider: Self.providerID)
    }
    
    public func setAPIKey(_ key: String) throws {
        try KeychainHelper.shared.saveAPIKey(key, forProvider: Self.providerID)
    }
    
    public func clearAPIKey() throws {
        try KeychainHelper.shared.deleteAPIKey(forProvider: Self.providerID)
        _status = .disconnected
    }
    
    public func testConnection() async throws -> Bool {
        guard hasAPIKey else {
            _status = .error("No API key")
            throw AIProviderError.notConfigured("API key not set")
        }
        
        _status = .connecting
        
        // Test with a minimal request
        do {
            _ = try await complete(
                messages: [ConversationMessage(role: .user, content: "Hi")],
                systemPrompt: nil,
                maxTokens: 10
            )
            _status = .ready
            return true
        } catch {
            _status = .error(error.localizedDescription)
            throw error
        }
    }
    
    public func reason(
        context: String,
        userQuery: String?,
        conversationHistory: [ConversationMessage],
        maxTokens: Int
    ) async throws -> AICompletionResult {
        // Build troubleshooting prompt and call complete()
        // ... implementation
    }
    
    public func complete(
        messages: [ConversationMessage],
        systemPrompt: String?,
        maxTokens: Int
    ) async throws -> AICompletionResult {
        // Call Gemini API
        // Return AICompletionResult with isFromCloud: true
    }
}
```

### 2. Register the Provider

```swift
extension GeminiProvider {
    public static func register() {
        ProviderRegistry.shared.registerCloudProvider(id: providerID) {
            GeminiProvider()
        }
    }
}
```

### 3. Important Security Requirements

- **ALWAYS** use `KeychainHelper` for API key storage
- **NEVER** store keys in UserDefaults, plist, or any other unencrypted storage
- **NEVER** log API keys (even in debug builds)
- **ALWAYS** set `isFromCloud: true` in `AICompletionResult`

## Testing Your Provider

Use the AI Debug Panel (`AIDebugView`) to test your provider:

1. Enable developer settings
2. Open the debug panel
3. Test connection, model fetching, and inference
4. Verify mode switching and fallback behavior

### Required Test Cases

- [ ] Connection test succeeds/fails gracefully
- [ ] Model list is fetched dynamically (local providers)
- [ ] API key storage works via Keychain (cloud providers)
- [ ] Reasoning produces valid output
- [ ] Error handling is graceful
- [ ] Mode switching works correctly
- [ ] Fallback to local works when cloud fails

## Pull Request Template

When submitting a new provider, include:

```markdown
## New Provider: [Provider Name]

### Type
- [ ] Local Provider
- [ ] Cloud Provider

### Checklist
- [ ] Implements required protocol (`LocalInferenceProvider` or `CloudReasoningProvider`)
- [ ] Registered with `ProviderRegistry`
- [ ] Works in local mode (if local provider)
- [ ] API keys stored in Keychain (if cloud provider)
- [ ] No hardcoded API keys or secrets
- [ ] Error handling is graceful
- [ ] Tested with AI Debug Panel
- [ ] Documentation updated

### Testing
Describe how you tested the provider:

### Notes
Any additional context or special configuration needed:
```

## Code Style

- Use Swift's native async/await for API calls
- Follow existing naming conventions
- Add documentation comments for public APIs
- Keep providers self-contained (no cross-dependencies)

## Questions?

Open an issue or discussion on GitHub if you have questions about the architecture or need help implementing a provider.
