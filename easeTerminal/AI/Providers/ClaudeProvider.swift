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

// MARK: - ClaudeProvider

/// Anthropic Claude cloud reasoning provider.
/// OPTIONAL - requires user-provided API key stored in Keychain.
public final class ClaudeProvider: CloudReasoningProvider, @unchecked Sendable {
    
    // MARK: - Static Properties
    
    public static let providerID = "anthropic"
    public static let displayName = "Claude (Anthropic)"
    public static let isCloudProvider = true
    
    private static let apiBaseURL = URL(string: "https://api.anthropic.com/v1")!
    private static let apiVersion = "2023-06-01"
    
    /// Available Claude models (March 2026)
    public static let availableModels: [AIModel] = [
        AIModel(
            id: "claude-opus-4-6",
            name: "Claude Opus 4.6",
            provider: providerID,
            parameterCount: nil,
            quantization: nil
        ),
        AIModel(
            id: "claude-sonnet-4-6",
            name: "Claude Sonnet 4.6",
            provider: providerID,
            parameterCount: nil,
            quantization: nil
        ),
        AIModel(
            id: "claude-haiku-4-5-20251001",
            name: "Claude Haiku 4.5",
            provider: providerID,
            parameterCount: nil,
            quantization: nil
        ),
        AIModel(
            id: "claude-sonnet-4-5-20250929",
            name: "Claude Sonnet 4.5",
            provider: providerID,
            parameterCount: nil,
            quantization: nil
        )
    ]
    
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
    
    private let session: URLSession
    
    // MARK: - Initialization
    
    public init() {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 60
        config.timeoutIntervalForResource = 300
        self.session = URLSession(configuration: config)
        
        // Load saved model selection
        if let savedModelId = UserDefaults.standard.string(forKey: "anthropic.selectedModel") {
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
        
        var messages = conversationHistory
        
        // Build user message with context
        var userContent = "Here's the terminal context:\n\n\(context)"
        if let query = userQuery {
            userContent += "\n\nUser question: \(query)"
        } else {
            userContent += "\n\nPlease analyze this and help me understand what's happening or fix any issues."
        }
        
        messages.append(ConversationMessage(role: .user, content: userContent))
        
        return try await complete(messages: messages, systemPrompt: systemPrompt, maxTokens: maxTokens)
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
        
        let url = Self.apiBaseURL.appendingPathComponent("messages")
        
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
