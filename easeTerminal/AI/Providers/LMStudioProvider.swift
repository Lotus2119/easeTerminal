//
//  LMStudioProvider.swift
//  easeTerminal
//
//  LM Studio local inference provider.
//  Uses the OpenAI-compatible API served by LM Studio at localhost:1234/v1.
//  No API key required — runs entirely on the user's machine.
//

import Foundation

// MARK: - LM Studio API Types (OpenAI-compatible)

private struct LMStudioModelsResponse: Codable {
    let data: [LMStudioModelEntry]
}

private struct LMStudioModelEntry: Codable {
    let id: String
}

private struct LMStudioRequest: Codable {
    let model: String
    let messages: [LMStudioMessage]
    let max_tokens: Int?
    let temperature: Double?
    let stream: Bool
}

private struct LMStudioMessage: Codable {
    let role: String
    let content: String
}

private struct LMStudioResponse: Codable {
    let model: String
    let choices: [LMStudioChoice]
    let usage: LMStudioUsage?
}

private struct LMStudioChoice: Codable {
    let message: LMStudioMessage
    let finish_reason: String?
}

private struct LMStudioUsage: Codable {
    let total_tokens: Int
}

// MARK: - LMStudioProvider

/// LM Studio local inference provider.
/// Conforms to LocalInferenceProvider using the OpenAI-compatible API.
/// Default base URL is http://localhost:1234/v1.
@MainActor
public final class LMStudioProvider: LocalInferenceProvider {

    // MARK: - Static Properties

    public static let providerID = "lmstudio"
    public static let displayName = "LM Studio (Local)"
    public static let isCloudProvider = false

    // MARK: - Instance Properties

    public var baseURL: URL

    public var selectedModel: AIModel? {
        didSet {
            if let model = selectedModel {
                UserDefaults.standard.set(model.id, forKey: "lmstudio.selectedModel")
            } else {
                UserDefaults.standard.removeObject(forKey: "lmstudio.selectedModel")
            }
        }
    }

    private var _status: ProviderStatus = .disconnected
    public var status: ProviderStatus { _status }

    public var isReady: Bool {
        if case .ready = _status { return true }
        return false
    }

    private var cachedModels: [AIModel] = []
    private var lastModelFetch: Date?
    private let modelCacheDuration: TimeInterval = 60

    private let session: URLSession

    // MARK: - Initialization

    public init(baseURL: URL = URL(string: "http://localhost:1234/v1")!) {
        self.baseURL = baseURL

        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 30
        config.timeoutIntervalForResource = 300
        self.session = URLSession(configuration: config)
    }

    // MARK: - LocalInferenceProvider Protocol

    public func isServerRunning() async -> Bool {
        let url = baseURL.appending(path: "models")
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

    /// Fetch available models from LM Studio's /v1/models endpoint.
    /// Models are dynamically loaded — never hardcoded.
    public func fetchAvailableModels() async throws -> [AIModel] {
        if let lastFetch = lastModelFetch,
           Date.now.timeIntervalSince(lastFetch) < modelCacheDuration,
           !cachedModels.isEmpty {
            return cachedModels
        }

        let url = baseURL.appending(path: "models")
        let (data, response) = try await session.data(from: url)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw AIProviderError.connectionFailed("Invalid response")
        }

        guard httpResponse.statusCode == 200 else {
            throw AIProviderError.connectionFailed("HTTP \(httpResponse.statusCode)")
        }

        let modelsResponse = try JSONDecoder().decode(LMStudioModelsResponse.self, from: data)

        if modelsResponse.data.isEmpty {
            _status = .noModels
            throw AIProviderError.ollamaNoModels
        }

        let models = modelsResponse.data.map { entry in
            AIModel(
                id: entry.id,
                name: formatModelName(entry.id),
                provider: Self.providerID
            )
        }

        cachedModels = models
        lastModelFetch = Date.now
        _status = .ready

        return models
    }

    // MARK: - ReasoningProvider Protocol

    public func testConnection() async throws -> Bool {
        _status = .connecting

        guard await isServerRunning() else {
            _status = .notDetected
            throw AIProviderError.ollamaNotRunning
        }

        do {
            let models = try await fetchAvailableModels()
            if models.isEmpty {
                _status = .noModels
                throw AIProviderError.ollamaNoModels
            }
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

    public func complete(
        messages: [ConversationMessage],
        systemPrompt: String?,
        maxTokens: Int
    ) async throws -> AICompletionResult {
        guard let model = selectedModel else {
            throw AIProviderError.notConfigured("No model selected")
        }

        let url = baseURL.appending(path: "chat/completions")

        var lmMessages: [LMStudioMessage] = []

        if let system = systemPrompt {
            lmMessages.append(LMStudioMessage(role: "system", content: system))
        }

        lmMessages += messages.map { LMStudioMessage(role: $0.role.rawValue, content: $0.content) }

        let requestBody = LMStudioRequest(
            model: model.id,
            messages: lmMessages,
            max_tokens: maxTokens,
            temperature: 0.7,
            stream: false
        )

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(requestBody)

        let (data, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw AIProviderError.connectionFailed("Invalid response")
        }

        if httpResponse.statusCode == 404 {
            throw AIProviderError.modelNotFound(model.id)
        }

        guard httpResponse.statusCode == 200 else {
            throw AIProviderError.connectionFailed("HTTP \(httpResponse.statusCode)")
        }

        let lmResponse = try JSONDecoder().decode(LMStudioResponse.self, from: data)

        guard let choice = lmResponse.choices.first else {
            throw AIProviderError.invalidResponse("No response content")
        }

        return AICompletionResult(
            content: choice.message.content,
            model: lmResponse.model,
            tokensUsed: lmResponse.usage?.total_tokens,
            finishReason: choice.finish_reason,
            isFromCloud: false
        )
    }

    // MARK: - Helpers

    /// Override system prompt to mention LM Studio context.
    public var reasoningSystemPrompt: String {
        """
        You are an expert terminal troubleshooting assistant running locally via LM Studio. You help developers debug issues, fix errors, and understand command output.
        
        When providing solutions:
        1. Explain what went wrong clearly and concisely
        2. Provide specific commands to fix the issue
        3. Explain why the fix works
        4. Suggest preventive measures when relevant
        
        Format commands in code blocks. Be direct and actionable.
        You have full context from the user's terminal - use it to give specific, relevant advice.
        """
    }

    private func formatModelName(_ id: String) -> String {
        id.replacing("-", with: " ")
          .replacing("_", with: " ")
          .split(separator: " ")
          .map { $0.capitalized }
          .joined(separator: " ")
    }

    private func loadSavedModelSelection(from models: [AIModel]) {
        if selectedModel != nil { return }
        if let savedID = UserDefaults.standard.string(forKey: "lmstudio.selectedModel"),
           let model = models.first(where: { $0.id == savedID }) {
            selectedModel = model
        } else {
            selectedModel = models.first
        }
    }
}

// MARK: - Provider Registration

extension LMStudioProvider {
    public static func register() {
        ProviderRegistry.shared.registerLocalProvider(id: providerID) {
            LMStudioProvider()
        }
    }
}
