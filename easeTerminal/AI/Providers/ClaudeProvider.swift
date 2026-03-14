//
//  ClaudeProvider.swift
//  easeTerminal
//
//  Anthropic Claude cloud reasoning provider.
//  OPTIONAL - requires user's own API key.
//  Used in Hybrid mode for reasoning while local Ollama handles context packaging.
//

import Foundation

// MARK: - Claude API Types

private struct ClaudeRequest: Codable {
    let model: String
    let max_tokens: Int
    let system: String?
    let messages: [ClaudeMessage]
}

private struct ClaudeMessage: Codable {
    let role: String
    let content: String
}

private struct ClaudeResponse: Codable {
    let id: String
    let type: String
    let role: String
    let content: [ClaudeContent]
    let model: String
    let stop_reason: String?
    let usage: ClaudeUsage?
}

private struct ClaudeContent: Codable {
    let type: String
    let text: String?
}

private struct ClaudeUsage: Codable {
    let input_tokens: Int
    let output_tokens: Int
}

private struct ClaudeError: Codable {
    let type: String
    let error: ClaudeErrorDetail
}

private struct ClaudeErrorDetail: Codable {
    let type: String
    let message: String
}

// MARK: - Anthropic /v1/models response types

private struct ClaudeModelsResponse: Codable {
    let data: [ClaudeModelEntry]
}

private struct ClaudeModelEntry: Codable {
    let id: String
    let display_name: String?
    let type: String?
}

// MARK: - ClaudeProvider

/// Anthropic Claude cloud reasoning provider.
/// OPTIONAL - requires user-provided API key stored in Keychain.
@MainActor
public final class ClaudeProvider: CloudReasoningProvider {
    
    // MARK: - Static Properties
    
    public static let providerID = "anthropic"
    public static let displayName = "Claude (Anthropic)"
    public static let isCloudProvider = true
    
    private static let apiBaseURL = URL(string: "https://api.anthropic.com/v1")!
    private static let apiVersion = "2023-06-01"
    private static let modelCacheDuration: TimeInterval = 300 // 5 minutes
    
    // MARK: - Instance Properties
    
    public var selectedModel: AIModel? {
        didSet {
            if let model = selectedModel {
                UserDefaults.standard.set(model.id, forKey: "anthropic.selectedModel")
            } else {
                UserDefaults.standard.removeObject(forKey: "anthropic.selectedModel")
            }
        }
    }
    
    private var _status: ProviderStatus = .disconnected
    public var status: ProviderStatus {
        _status
    }
    
    public var isReady: Bool {
        hasAPIKey && selectedModel != nil && _status == .ready
    }
    
    public var hasAPIKey: Bool {
        KeychainHelper.shared.hasAPIKey(forProvider: Self.providerID)
    }
    
    /// Cached models fetched from the Anthropic API
    private var cachedModels: [AIModel] = []
    private var lastModelFetch: Date?
    
    private let session: URLSession
    
    // MARK: - Initialization
    
    public init() {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 60
        config.timeoutIntervalForResource = 300
        self.session = URLSession(configuration: config)
    }
    
    // MARK: - CloudReasoningProvider Protocol
    
    public func setAPIKey(_ key: String) throws {
        try KeychainHelper.shared.saveAPIKey(key, forProvider: Self.providerID)
    }
    
    public func clearAPIKey() throws {
        try KeychainHelper.shared.deleteAPIKey(forProvider: Self.providerID)
        _status = .disconnected
        cachedModels = []
        lastModelFetch = nil
        selectedModel = nil
    }
    
    /// Fetch available Claude models from the Anthropic /v1/models endpoint.
    /// Results are cached for 5 minutes. Requires a valid API key.
    public func fetchAvailableModels() async throws -> [AIModel] {
        // Return cache if still fresh
        if let lastFetch = lastModelFetch,
           Date.now.timeIntervalSince(lastFetch) < Self.modelCacheDuration,
           !cachedModels.isEmpty {
            return cachedModels
        }
        
        guard let apiKey = KeychainHelper.shared.getAPIKey(forProvider: Self.providerID) else {
            throw AIProviderError.notConfigured("API key not set")
        }
        
        let url = Self.apiBaseURL.appending(path: "models")
        var request = URLRequest(url: url)
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue(Self.apiVersion, forHTTPHeaderField: "anthropic-version")
        
        let (data, response) = try await session.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw AIProviderError.connectionFailed("Invalid response")
        }
        
        if httpResponse.statusCode == 401 {
            throw AIProviderError.authenticationFailed
        }
        
        guard httpResponse.statusCode == 200 else {
            throw AIProviderError.connectionFailed("HTTP \(httpResponse.statusCode)")
        }
        
        let modelsResponse = try JSONDecoder().decode(ClaudeModelsResponse.self, from: data)
        
        let models = modelsResponse.data
            .filter { $0.type == nil || $0.type == "model" }
            .map { entry in
                AIModel(
                    id: entry.id,
                    name: entry.display_name ?? entry.id,
                    provider: Self.providerID
                )
            }
        
        cachedModels = models
        lastModelFetch = Date.now
        
        // Restore saved selection from the freshly fetched list
        if let savedID = UserDefaults.standard.string(forKey: "anthropic.selectedModel"),
           selectedModel == nil {
            selectedModel = models.first { $0.id == savedID }
        }
        
        return models
    }
    
    // MARK: - ReasoningProvider Protocol
    
    public func testConnection() async throws -> Bool {
        guard hasAPIKey else {
            _status = .error("No API key")
            throw AIProviderError.notConfigured("API key not set")
        }
        
        _status = .connecting
        
        do {
            // Fetch models as the connection test — validates the key and populates the picker
            let models = try await fetchAvailableModels()
            
            // Auto-select first model if nothing is selected yet
            if selectedModel == nil {
                selectedModel = models.first
            }
            
            _status = .ready
            return true
        } catch {
            _status = .error(error.localizedDescription)
            throw error
        }
    }
    
    // reason() is provided by the ReasoningProvider protocol extension.
    
    public func complete(
        messages: [ConversationMessage],
        systemPrompt: String?,
        maxTokens: Int
    ) async throws -> AICompletionResult {
        guard let apiKey = KeychainHelper.shared.getAPIKey(forProvider: Self.providerID) else {
            throw AIProviderError.notConfigured("API key not set")
        }
        
        guard let model = selectedModel else {
            throw AIProviderError.notConfigured("No model selected")
        }
        
        let url = Self.apiBaseURL.appending(path: "messages")
        
        let claudeMessages = messages
            .filter { $0.role != .system }
            .map { ClaudeMessage(role: $0.role.rawValue, content: $0.content) }
        
        let requestBody = ClaudeRequest(
            model: model.id,
            max_tokens: maxTokens,
            system: systemPrompt,
            messages: claudeMessages
        )
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue(Self.apiVersion, forHTTPHeaderField: "anthropic-version")
        request.httpBody = try JSONEncoder().encode(requestBody)
        
        let (data, response) = try await session.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw AIProviderError.connectionFailed("Invalid response")
        }
        
        // Handle error responses
        if httpResponse.statusCode != 200 {
            if let errorResponse = try? JSONDecoder().decode(ClaudeError.self, from: data) {
                switch errorResponse.error.type {
                case "authentication_error":
                    throw AIProviderError.authenticationFailed
                case "rate_limit_error":
                    throw AIProviderError.rateLimited
                case "invalid_request_error" where errorResponse.error.message.contains("context"):
                    throw AIProviderError.contextTooLong
                default:
                    throw AIProviderError.invalidResponse(errorResponse.error.message)
                }
            }
            throw AIProviderError.invalidResponse("HTTP \(httpResponse.statusCode)")
        }
        
        let claudeResponse = try JSONDecoder().decode(ClaudeResponse.self, from: data)
        
        let content = claudeResponse.content
            .compactMap { $0.text }
            .joined()
        
        let tokensUsed = claudeResponse.usage.map { $0.input_tokens + $0.output_tokens }
        
        return AICompletionResult(
            content: content,
            model: claudeResponse.model,
            tokensUsed: tokensUsed,
            finishReason: claudeResponse.stop_reason,
            isFromCloud: true
        )
    }
}

// MARK: - Provider Registration

extension ClaudeProvider {
    /// Register this provider with the global registry
    public static func register() {
        ProviderRegistry.shared.registerCloudProvider(id: providerID) {
            ClaudeProvider()
        }
    }
}
