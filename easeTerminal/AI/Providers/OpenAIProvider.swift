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

// MARK: - OpenAIProvider

/// OpenAI cloud reasoning provider.
/// OPTIONAL - requires user-provided API key stored in Keychain.
public final class OpenAIProvider: CloudReasoningProvider, @unchecked Sendable {
    
    // MARK: - Static Properties
    
    public static let providerID = "openai"
    public static let displayName = "OpenAI"
    public static let isCloudProvider = true
    
    private static let apiBaseURL = URL(string: "https://api.openai.com/v1")!
    
    /// Available OpenAI models (March 2026)
    public static let availableModels: [AIModel] = [
        AIModel(
            id: "gpt-5.4",
            name: "GPT-5.4",
            provider: providerID,
            parameterCount: nil,
            quantization: nil
        ),
        AIModel(
            id: "gpt-5.4-pro",
            name: "GPT-5.4 Pro",
            provider: providerID,
            parameterCount: nil,
            quantization: nil
        ),
        AIModel(
            id: "gpt-5.3-codex",
            name: "GPT-5.3 Codex",
            provider: providerID,
            parameterCount: nil,
            quantization: nil
        ),
        AIModel(
            id: "gpt-5-mini-2025-08-07",
            name: "GPT-5 Mini",
            provider: providerID,
            parameterCount: nil,
            quantization: nil
        )
    ]
    
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
    
    private let session: URLSession
    
    // MARK: - Initialization
    
    public init() {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 60
        config.timeoutIntervalForResource = 300
        self.session = URLSession(configuration: config)
        
        // Load saved model selection
        if let savedModelId = UserDefaults.standard.string(forKey: "openai.selectedModel") {
            selectedModel = Self.availableModels.first { $0.id == savedModelId }
        }
    }
    
    // MARK: - CloudReasoningProvider Protocol
    
    public func setAPIKey(_ key: String) throws {
        try KeychainHelper.shared.saveAPIKey(key, forProvider: Self.providerID)
    }
    
    public func clearAPIKey() throws {
        try KeychainHelper.shared.deleteAPIKey(forProvider: Self.providerID)
        _status = .disconnected
    }
    
    // MARK: - ReasoningProvider Protocol
    
    public func testConnection() async throws -> Bool {
        guard hasAPIKey else {
            _status = .error("No API key")
            throw AIProviderError.notConfigured("API key not set")
        }
        
        guard selectedModel != nil else {
            _status = .error("No model selected")
            throw AIProviderError.notConfigured("No model selected")
        }
        
        _status = .connecting
        
        // Send a minimal request to verify the API key works
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
        
        let systemPrompt = """
        You are an expert terminal troubleshooting assistant. You help developers debug issues, fix errors, and understand command output.
        
        When providing solutions:
        1. Explain what went wrong clearly and concisely
        2. Provide specific commands to fix the issue
        3. Explain why the fix works
        4. Suggest preventive measures when relevant
        
        Format commands in code blocks. Be direct and actionable.
        """
        
        var messages: [ConversationMessage] = []
        messages.append(ConversationMessage(role: .system, content: systemPrompt))
        messages.append(contentsOf: conversationHistory)
        
        // Build user message with context
        var userContent = "Here's the terminal context:\n\n\(context)"
        if let query = userQuery {
            userContent += "\n\nUser question: \(query)"
        } else {
            userContent += "\n\nPlease analyze this and help me understand what's happening or fix any issues."
        }
        
        messages.append(ConversationMessage(role: .user, content: userContent))
        
        return try await complete(messages: messages, systemPrompt: nil, maxTokens: maxTokens)
    }
    
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
        
        let url = Self.apiBaseURL.appendingPathComponent("chat/completions")
        
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
