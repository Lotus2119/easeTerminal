//
//  AIProviderProtocols.swift
//  easeTerminal
//
//  Core protocols for the local-first AI architecture.
//
//  Design Philosophy:
//  - Fully local inference is the DEFAULT experience
//  - Cloud providers are OPTIONAL power-ups, never required
//  - A single local model (Qwen3-Coder 30B) handles both context packaging and reasoning
//  - The pipeline is mode-agnostic: it doesn't care if reasoning comes from local or cloud
//

import Foundation

// MARK: - Operating Mode

/// The two operating modes for the AI system.
/// Local mode is the default and requires no configuration.
/// Hybrid mode adds cloud reasoning while keeping local context packaging.
public enum AIOperatingMode: String, Codable, CaseIterable {
    /// Fully local inference using Ollama. Default mode.
    /// No API key or internet connection required.
    case local
    
    /// Local context packaging + cloud reasoning.
    /// Requires user-provided API key for their chosen cloud provider.
    case hybrid
    
    public var displayName: String {
        switch self {
        case .local: return "Fully Local"
        case .hybrid: return "Hybrid (Local + Cloud)"
        }
    }
    
    public var description: String {
        switch self {
        case .local:
            return "All AI processing runs locally via Ollama. No internet required."
        case .hybrid:
            return "Context packaging runs locally, reasoning uses your cloud API."
        }
    }
}

// MARK: - Model Representation

/// Represents an AI model that can be used for inference.
/// Models are fetched dynamically from Ollama at runtime, never hardcoded.
public struct AIModel: Identifiable, Hashable, Codable, Sendable {
    public let id: String           // e.g., "qwen3-coder:30b"
    public let name: String         // Display name, e.g., "Qwen3 Coder 30B"
    public let provider: String     // "ollama", "anthropic", "openai"
    public let size: String?        // e.g., "18GB" - from Ollama API
    public let parameterCount: String? // e.g., "30B"
    public let quantization: String?   // e.g., "Q4_K_M"
    
    public init(
        id: String,
        name: String,
        provider: String,
        size: String? = nil,
        parameterCount: String? = nil,
        quantization: String? = nil
    ) {
        self.id = id
        self.name = name
        self.provider = provider
        self.size = size
        self.parameterCount = parameterCount
        self.quantization = quantization
    }
    
    /// Check if this is the recommended default model
    public var isRecommendedDefault: Bool {
        id.lowercased().contains("qwen3-coder") && id.contains("30b")
    }
}

// MARK: - Completion Result

/// Result from any AI completion, whether local or cloud.
public struct AICompletionResult: Sendable {
    public let content: String
    public let model: String
    public let tokensUsed: Int?
    public let finishReason: String?
    public let isFromCloud: Bool
    
    public init(
        content: String,
        model: String,
        tokensUsed: Int? = nil,
        finishReason: String? = nil,
        isFromCloud: Bool = false
    ) {
        self.content = content
        self.model = model
        self.tokensUsed = tokensUsed
        self.finishReason = finishReason
        self.isFromCloud = isFromCloud
    }
}

// MARK: - Conversation Message

/// A message in a conversation, used for multi-turn interactions.
public struct ConversationMessage: Codable, Sendable {
    public enum Role: String, Codable, Sendable {
        case system
        case user
        case assistant
    }
    
    public let role: Role
    public let content: String
    
    public init(role: Role, content: String) {
        self.role = role
        self.content = content
    }
}

// MARK: - Provider Status

/// Connection status for any provider (local or cloud).
public enum ProviderStatus: Equatable, Sendable {
    case notInstalled       // Ollama not found
    case noModels           // Ollama running but no models pulled
    case disconnected       // Not connected / not configured
    case connecting         // Testing connection
    case ready              // Ready to use
    case error(String)      // Error with message
    
    public var isUsable: Bool {
        if case .ready = self { return true }
        return false
    }
    
    public var displayText: String {
        switch self {
        case .notInstalled: return "Not Installed"
        case .noModels: return "No Models"
        case .disconnected: return "Disconnected"
        case .connecting: return "Connecting..."
        case .ready: return "Ready"
        case .error(let msg): return "Error: \(msg)"
        }
    }
}

// MARK: - Errors

/// Errors that can occur during AI operations.
public enum AIProviderError: Error, LocalizedError {
    case ollamaNotRunning
    case ollamaNoModels
    case modelNotFound(String)
    case connectionFailed(String)
    case invalidResponse(String)
    case authenticationFailed
    case rateLimited
    case contextTooLong
    case notConfigured(String)
    case cancelled
    
    public var errorDescription: String? {
        switch self {
        case .ollamaNotRunning:
            return "Ollama is not running. Start it with 'ollama serve' or launch Ollama.app"
        case .ollamaNoModels:
            return "No models found. Run 'ollama pull qwen3-coder:30b' to get started"
        case .modelNotFound(let model):
            return "Model '\(model)' not found. Run 'ollama pull \(model)'"
        case .connectionFailed(let msg):
            return "Connection failed: \(msg)"
        case .invalidResponse(let msg):
            return "Invalid response: \(msg)"
        case .authenticationFailed:
            return "API key is invalid or expired"
        case .rateLimited:
            return "Rate limited. Please wait before trying again"
        case .contextTooLong:
            return "Context too long for this model"
        case .notConfigured(let msg):
            return "Not configured: \(msg)"
        case .cancelled:
            return "Request was cancelled"
        }
    }
}

// MARK: - ReasoningProvider Protocol

/// Protocol for any provider that can perform reasoning/troubleshooting.
/// Both local Ollama and cloud providers (Claude, OpenAI) conform to this.
/// The pipeline doesn't care which implementation is active.
/// All conforming types must be @MainActor to protect mutable state.
@MainActor
public protocol ReasoningProvider: AnyObject, Sendable {
    /// Unique identifier for this provider type
    static var providerID: String { get }
    
    /// Human-readable name for display
    static var displayName: String { get }
    
    /// Whether this is a cloud provider (requires API key)
    static var isCloudProvider: Bool { get }
    
    /// Current status of this provider
    var status: ProviderStatus { get }
    
    /// Currently selected model for reasoning
    var selectedModel: AIModel? { get set }
    
    /// Whether this provider is ready to use
    var isReady: Bool { get }
    
    /// Test the connection to this provider
    func testConnection() async throws -> Bool
    
    /// Perform reasoning/troubleshooting on packaged context
    func reason(
        context: String,
        userQuery: String?,
        conversationHistory: [ConversationMessage],
        maxTokens: Int
    ) async throws -> AICompletionResult
    
    /// General completion for chat interface
    func complete(
        messages: [ConversationMessage],
        systemPrompt: String?,
        maxTokens: Int
    ) async throws -> AICompletionResult
}

// MARK: - CloudReasoningProvider Protocol

/// Extension of ReasoningProvider for cloud providers that require API keys.
/// Cloud providers are OPTIONAL and clearly marked as such.
public protocol CloudReasoningProvider: ReasoningProvider {
    /// Whether an API key is stored for this provider
    var hasAPIKey: Bool { get }
    
    /// Store an API key securely in Keychain
    func setAPIKey(_ key: String) throws
    
    /// Remove the stored API key
    func clearAPIKey() throws
    
    /// Fetch available models dynamically from the provider's API.
    /// Requires a valid API key to be set before calling.
    func fetchAvailableModels() async throws -> [AIModel]
}

// MARK: - LocalInferenceProvider Protocol

/// Protocol for local inference providers (Ollama, LlamaCpp, LM Studio, etc.)
/// Local providers fetch their model list dynamically at runtime.
public protocol LocalInferenceProvider: ReasoningProvider {
    /// Base URL for the local API
    var baseURL: URL { get set }
    
    /// Fetch available models from the local server
    func fetchAvailableModels() async throws -> [AIModel]
    
    /// Check if the local server is running
    func isServerRunning() async -> Bool
}

// MARK: - Provider Registry

/// Registry for discovering and instantiating providers.
/// New providers register themselves here to appear in settings automatically.
/// Isolated to @MainActor so all dictionary access is serialised.
@MainActor
public final class ProviderRegistry: Sendable {
    public static let shared = ProviderRegistry()
    
    private var localProviderFactories: [String: @MainActor () -> any LocalInferenceProvider] = [:]
    private var cloudProviderFactories: [String: @MainActor () -> any CloudReasoningProvider] = [:]
    
    private init() {}
    
    // MARK: - Registration
    
    /// Register a local inference provider (e.g., Ollama, LM Studio)
    public func registerLocalProvider(id: String, factory: @escaping @MainActor () -> any LocalInferenceProvider) {
        localProviderFactories[id] = factory
    }
    
    /// Register a cloud reasoning provider (e.g., Claude, OpenAI)
    public func registerCloudProvider(id: String, factory: @escaping @MainActor () -> any CloudReasoningProvider) {
        cloudProviderFactories[id] = factory
    }
    
    // MARK: - Discovery
    
    /// Get all registered local provider IDs
    public var availableLocalProviders: [String] {
        Array(localProviderFactories.keys).sorted()
    }
    
    /// Get all registered cloud provider IDs
    public var availableCloudProviders: [String] {
        Array(cloudProviderFactories.keys).sorted()
    }
    
    // MARK: - Instantiation
    
    /// Create a new instance of a local provider
    public func createLocalProvider(id: String) -> (any LocalInferenceProvider)? {
        localProviderFactories[id]?()
    }
    
    /// Create a new instance of a cloud provider
    public func createCloudProvider(id: String) -> (any CloudReasoningProvider)? {
        cloudProviderFactories[id]?()
    }
}
