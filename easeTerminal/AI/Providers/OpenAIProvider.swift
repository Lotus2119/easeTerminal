//
//  OpenAIProvider.swift
//  easeTerminal
//
//  OpenAI cloud reasoning provider.
//  OPTIONAL - requires user's own API key.
//  Used in Hybrid mode for reasoning while local Ollama handles context packaging.
//

import Foundation

// MARK: - OpenAI API Types

private struct OpenAIRequest: Codable {
    let model: String
    let messages: [OpenAIMessage]
    let max_tokens: Int?
    let temperature: Double?
}

private struct OpenAIMessage: Codable {
    let role: String
    let content: String
}

private struct OpenAIResponse: Codable {
    let id: String
    let object: String
    let model: String
    let choices: [OpenAIChoice]
    let usage: OpenAIUsage?
}

private struct OpenAIChoice: Codable {
    let index: Int
    let message: OpenAIMessage
    let finish_reason: String?
}

private struct OpenAIUsage: Codable {
    let prompt_tokens: Int
    let completion_tokens: Int
    let total_tokens: Int
}

private struct OpenAIError: Codable {
    let error: OpenAIErrorDetail
}

private struct OpenAIErrorDetail: Codable {
    let message: String
    let type: String
    let code: String?
}

// MARK: - OpenAI /v1/models response types

private struct OpenAIModelsResponse: Codable {
    let data: [OpenAIModelEntry]
}

private struct OpenAIModelEntry: Codable {
    let id: String
    let object: String?
    let owned_by: String?
}

// MARK: - OpenAIProvider

/// OpenAI cloud reasoning provider.
/// OPTIONAL - requires user-provided API key stored in Keychain.
@MainActor
public final class OpenAIProvider: CloudReasoningProvider {
    
    // MARK: - Static Properties
    
    public static let providerID = "openai"
    public static let displayName = "OpenAI"
    public static let isCloudProvider = true
    
    private static let apiBaseURL = URL(string: "https://api.openai.com/v1")!
    private static let modelCacheDuration: TimeInterval = 300 // 5 minutes
    
    // MARK: - Instance Properties
    
    public var selectedModel: AIModel? {
        didSet {
            if let model = selectedModel {
                UserDefaults.standard.set(model.id, forKey: "openai.selectedModel")
            } else {
                UserDefaults.standard.removeObject(forKey: "openai.selectedModel")
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
    
    /// Cached models fetched from the OpenAI API
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
    
    /// Fetch available GPT chat models from the OpenAI /v1/models endpoint.
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
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        
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
        
        let modelsResponse = try JSONDecoder().decode(OpenAIModelsResponse.self, from: data)
        
        // Filter to chat-capable GPT models and sort by ID descending (newest first)
        let chatModels = modelsResponse.data
            .filter { isChatModel($0.id) }
            .sorted { $0.id > $1.id }
            .map { entry in
                AIModel(
                    id: entry.id,
                    name: formatModelName(entry.id),
                    provider: Self.providerID
                )
            }
        
        cachedModels = chatModels
        lastModelFetch = Date.now
        
        // Restore saved selection from the freshly fetched list
        if let savedID = UserDefaults.standard.string(forKey: "openai.selectedModel"),
           selectedModel == nil {
            selectedModel = chatModels.first { $0.id == savedID }
        }
        
        return chatModels
    }
    
    /// Returns true for GPT models that support chat completions
    private func isChatModel(_ id: String) -> Bool {
        let lower = id.lowercased()
        // Include gpt-* chat models, exclude embeddings, whisper, tts, dall-e, davinci, babbage, ada
        guard lower.hasPrefix("gpt-") || lower.hasPrefix("o1") || lower.hasPrefix("o3") || lower.hasPrefix("o4") else {
            return false
        }
        let excluded = ["instruct", "vision-preview", "0301", "0314"]
        return !excluded.contains(where: { lower.contains($0) })
    }
    
    /// Convert a raw model ID like "gpt-4o-mini" into a readable display name
    private func formatModelName(_ id: String) -> String {
        id.replacing("-", with: " ")
          .split(separator: " ")
          .map { $0.capitalized }
          .joined(separator: " ")
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
        
        let url = Self.apiBaseURL.appending(path: "chat/completions")
        
        var openAIMessages: [OpenAIMessage] = []
        
        // Add system prompt if provided
        if let system = systemPrompt {
            openAIMessages.append(OpenAIMessage(role: "system", content: system))
        }
        
        // Add conversation messages
        openAIMessages += messages.map { OpenAIMessage(role: $0.role.rawValue, content: $0.content) }
        
        let requestBody = OpenAIRequest(
            model: model.id,
            messages: openAIMessages,
            max_tokens: maxTokens,
            temperature: 0.7
        )
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.httpBody = try JSONEncoder().encode(requestBody)
        
        let (data, response) = try await session.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw AIProviderError.connectionFailed("Invalid response")
        }
        
        // Handle error responses
        if httpResponse.statusCode != 200 {
            if let errorResponse = try? JSONDecoder().decode(OpenAIError.self, from: data) {
                switch errorResponse.error.type {
                case "invalid_api_key", "authentication_error":
                    throw AIProviderError.authenticationFailed
                case "rate_limit_exceeded":
                    throw AIProviderError.rateLimited
                case "context_length_exceeded":
                    throw AIProviderError.contextTooLong
                default:
                    throw AIProviderError.invalidResponse(errorResponse.error.message)
                }
            }
            throw AIProviderError.invalidResponse("HTTP \(httpResponse.statusCode)")
        }
        
        let openAIResponse = try JSONDecoder().decode(OpenAIResponse.self, from: data)
        
        guard let choice = openAIResponse.choices.first else {
            throw AIProviderError.invalidResponse("No response content")
        }
        
        return AICompletionResult(
            content: choice.message.content,
            model: openAIResponse.model,
            tokensUsed: openAIResponse.usage?.total_tokens,
            finishReason: choice.finish_reason,
            isFromCloud: true
        )
    }
}

// MARK: - Provider Registration

extension OpenAIProvider {
    /// Register this provider with the global registry
    public static func register() {
        ProviderRegistry.shared.registerCloudProvider(id: providerID) {
            OpenAIProvider()
        }
    }
}
