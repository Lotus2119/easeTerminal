//
//  OllamaProvider.swift
//  easeTerminal
//
//  Ollama local inference provider.
//  This is the DEFAULT provider - no API key or internet required.
//
//  Qwen3-Coder 30B is the recommended model:
//  - MoE architecture with only 3.3B active parameters per inference
//  - Purpose-built for coding agents and terminal context
//  - Fits in 24GB unified memory on Apple Silicon
//  - Handles both context packaging AND reasoning
//

import Foundation

// MARK: - Ollama API Types

private struct OllamaTagsResponse: Codable {
    let models: [OllamaModelInfo]
}

private struct OllamaModelInfo: Codable {
    let name: String
    let size: Int64
    let parameter_size: String?
    let quantization_level: String?
    let modified_at: String
    
    var formattedSize: String {
        let gb = Double(size) / 1_000_000_000
        if gb >= 1 {
            return String(format: "%.1fGB", gb)
        } else {
            let mb = Double(size) / 1_000_000
            return String(format: "%.0fMB", mb)
        }
    }
}

private struct OllamaChatRequest: Codable {
    let model: String
    let messages: [OllamaChatMessage]
    let stream: Bool
    let options: OllamaOptions?
    
    struct OllamaOptions: Codable {
        let num_predict: Int?
    }
}

private struct OllamaChatMessage: Codable {
    let role: String
    let content: String
}

private struct OllamaChatResponse: Codable {
    let model: String
    let message: OllamaChatMessage
    let done: Bool
    let total_duration: Int64?
    let eval_count: Int?
}

private struct OllamaGenerateRequest: Codable {
    let model: String
    let prompt: String
    let system: String?
    let stream: Bool
    let options: OllamaOptions?
    
    struct OllamaOptions: Codable {
        let num_predict: Int?
    }
}

private struct OllamaGenerateResponse: Codable {
    let model: String
    let response: String
    let done: Bool
    let total_duration: Int64?
    let eval_count: Int?
}

// MARK: - OllamaProvider

/// Ollama local inference provider.
/// Conforms to LocalInferenceProvider (which extends ReasoningProvider).
/// This is the primary provider for the local-first architecture.
public final class OllamaProvider: LocalInferenceProvider, @unchecked Sendable {
    
    // MARK: - Static Properties
    
    public static let providerID = "ollama"
    public static let displayName = "Ollama (Local)"
    public static let isCloudProvider = false
    
    /// The recommended default model
    public static let recommendedModel = "qwen3-coder:30b"
    
    // MARK: - Instance Properties
    
    public var baseURL: URL
    
    public var selectedModel: AIModel? {
        didSet {
            if let model = selectedModel {
                UserDefaults.standard.set(model.id, forKey: "ollama.selectedReasoningModel")
            } else {
                UserDefaults.standard.removeObject(forKey: "ollama.selectedReasoningModel")
            }
        }
    }
    
    private var _status: ProviderStatus = .disconnected
    public var status: ProviderStatus {
        _status
    }
    
    public var isReady: Bool {
        if case .ready = _status { return true }
        return false
    }
    
    /// Cache of available models
    private var cachedModels: [AIModel] = []
    private var lastModelFetch: Date?
    private let modelCacheDuration: TimeInterval = 60 // Refresh every minute
    
    private let session: URLSession
    
    // MARK: - Initialization
    
    public init(baseURL: URL = URL(string: "http://localhost:11434")!) {
        self.baseURL = baseURL
        
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 30
        config.timeoutIntervalForResource = 300
        self.session = URLSession(configuration: config)
    }
    
    // MARK: - LocalInferenceProvider Protocol
    
    /// Check if Ollama server is running
    public func isServerRunning() async -> Bool {
        let url = baseURL.appendingPathComponent("api/tags")
        var request = URLRequest(url: url)
        request.timeoutInterval = 5
        
        do {
            let (_, response) = try await session.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse else { return false }
            return httpResponse.statusCode == 200
        } catch {
            return false
        }
    }
    
    /// Fetch available models from Ollama API
    /// Models are NEVER hardcoded - always fetched dynamically
    public func fetchAvailableModels() async throws -> [AIModel] {
        // Check cache first
        if let lastFetch = lastModelFetch,
           Date().timeIntervalSince(lastFetch) < modelCacheDuration,
           !cachedModels.isEmpty {
            return cachedModels
        }
        
        let url = baseURL.appendingPathComponent("api/tags")
        let (data, response) = try await session.data(from: url)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw AIProviderError.connectionFailed("Invalid response")
        }
        
        if httpResponse.statusCode != 200 {
            if httpResponse.statusCode == 0 {
                _status = .notInstalled
                throw AIProviderError.ollamaNotRunning
            }
            throw AIProviderError.connectionFailed("HTTP \(httpResponse.statusCode)")
        }
        
        let tagsResponse = try JSONDecoder().decode(OllamaTagsResponse.self, from: data)
        
        if tagsResponse.models.isEmpty {
            _status = .noModels
            throw AIProviderError.ollamaNoModels
        }
        
        let models = tagsResponse.models.map { info in
            AIModel(
                id: info.name,
                name: formatModelName(info.name),
                provider: Self.providerID,
                size: info.formattedSize,
                parameterCount: info.parameter_size,
                quantization: info.quantization_level
            )
        }
        
        cachedModels = models
        lastModelFetch = Date()
        _status = .ready
        
        return models
    }
    
    /// Format model name for display
    private func formatModelName(_ id: String) -> String {
        // Convert "qwen3-coder:30b" to "Qwen3 Coder 30B"
        var name = id
            .replacingOccurrences(of: ":", with: " ")
            .replacingOccurrences(of: "-", with: " ")
            .replacingOccurrences(of: "_", with: " ")
        
        // Capitalize words
        name = name.split(separator: " ").map { word in
            let str = String(word)
            // Keep version numbers lowercase
            if str.allSatisfy({ $0.isNumber || $0 == "." || $0 == "b" || $0 == "B" }) {
                return str.uppercased()
            }
            return str.capitalized
        }.joined(separator: " ")
        
        return name
    }
    
    // MARK: - ReasoningProvider Protocol
    
    public func testConnection() async throws -> Bool {
        _status = .connecting
        
        // First check if server is running
        guard await isServerRunning() else {
            _status = .notInstalled
            throw AIProviderError.ollamaNotRunning
        }
        
        // Then fetch models to verify
        do {
            let models = try await fetchAvailableModels()
            if models.isEmpty {
                _status = .noModels
                throw AIProviderError.ollamaNoModels
            }
            
            // Load saved model selection if we have models
            loadSavedModelSelection(from: models)
            
            _status = .ready
            return true
        } catch {
            if case .ollamaNoModels = error as? AIProviderError {
                _status = .noModels
            } else {
                _status = .error(error.localizedDescription)
            }
            throw error
        }
    }
    
    /// Load the saved model selection from UserDefaults
    private func loadSavedModelSelection(from models: [AIModel]) {
        if selectedModel != nil { return } // Already set
        
        if let savedID = UserDefaults.standard.string(forKey: "ollama.selectedReasoningModel"),
           let model = models.first(where: { $0.id == savedID }) {
            selectedModel = model
        } else if let defaultModel = models.first(where: { $0.isRecommendedDefault }) {
            // Auto-select qwen3-coder:30b if available
            selectedModel = defaultModel
        }
    }
    
    public func reason(
        context: String,
        userQuery: String?,
        conversationHistory: [ConversationMessage],
        maxTokens: Int
    ) async throws -> AICompletionResult {
        
        let systemPrompt = """
        You are an expert terminal troubleshooting assistant running locally via Ollama. You help developers debug issues, fix errors, and understand command output.
        
        When providing solutions:
        1. Explain what went wrong clearly and concisely
        2. Provide specific commands to fix the issue
        3. Explain why the fix works
        4. Suggest preventive measures when relevant
        
        Format commands in code blocks. Be direct and actionable.
        You have full context from the user's terminal - use it to give specific, relevant advice.
        """
        
        var messages = conversationHistory
        messages.insert(ConversationMessage(role: .system, content: systemPrompt), at: 0)
        
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
        guard let model = selectedModel else {
            throw AIProviderError.notConfigured("No model selected")
        }
        
        let url = baseURL.appendingPathComponent("api/chat")
        
        var ollamaMessages: [OllamaChatMessage] = []
        
        // Add system prompt if provided
        if let system = systemPrompt {
            ollamaMessages.append(OllamaChatMessage(role: "system", content: system))
        }
        
        // Add conversation messages
        for msg in messages {
            ollamaMessages.append(OllamaChatMessage(role: msg.role.rawValue, content: msg.content))
        }
        
        let requestBody = OllamaChatRequest(
            model: model.id,
            messages: ollamaMessages,
            stream: false,
            options: .init(num_predict: maxTokens)
        )
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(requestBody)
        
        let (data, response) = try await session.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw AIProviderError.connectionFailed("Invalid response")
        }
        
        if httpResponse.statusCode != 200 {
            if httpResponse.statusCode == 404 {
                throw AIProviderError.modelNotFound(model.id)
            }
            throw AIProviderError.connectionFailed("HTTP \(httpResponse.statusCode)")
        }
        
        let ollamaResponse = try JSONDecoder().decode(OllamaChatResponse.self, from: data)
        
        return AICompletionResult(
            content: ollamaResponse.message.content,
            model: ollamaResponse.model,
            tokensUsed: ollamaResponse.eval_count,
            finishReason: ollamaResponse.done ? "stop" : nil,
            isFromCloud: false
        )
    }
}

// MARK: - Provider Registration

extension OllamaProvider {
    /// Register this provider with the global registry
    public static func register() {
        ProviderRegistry.shared.registerLocalProvider(id: providerID) {
            OllamaProvider()
        }
    }
}
