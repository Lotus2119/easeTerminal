//
//  OpenAICompatibleEngine.swift
//  easeTerminal
//
//  Shared HTTP engine for any provider that speaks the OpenAI chat/completions API.
//  Not a provider itself — owned by provider instances that delegate to it.
//

import Foundation

// MARK: - Configuration

/// How to attach the API key to outgoing requests.
enum OpenAIAuthStyle: Sendable {
    /// Standard `Authorization: Bearer <key>` header.
    case bearer
    /// Custom header name, e.g. `x-api-key`.
    case custom(header: String)
}

/// All per-provider differences captured in a single value type.
/// Add a new static preset for each provider.
struct OpenAICompatibleConfig: Sendable {
    let providerID: String
    let displayName: String
    let isCloud: Bool

    /// Default base URL (e.g. `https://api.openai.com/v1`).
    let defaultBaseURL: URL

    /// How to authenticate requests. `nil` means no auth (local providers).
    let authStyle: OpenAIAuthStyle?

    /// Optional filter applied to the `/models` response.
    /// Return `true` to keep the model.
    let modelFilter: (@Sendable (OpenAICompatibleModelEntry) -> Bool)?

    /// Optional transform from raw model ID to display name.
    /// If `nil`, a default formatter is used (hyphens/underscores → spaces, capitalized).
    let modelNameFormatter: (@Sendable (String) -> String)?

    /// How long to cache the model list (seconds).
    let modelCacheDuration: TimeInterval

    /// URLSession request timeout (seconds).
    let requestTimeout: TimeInterval

    /// Whether to include `"stream": false` in chat completion requests.
    /// LM Studio requires this; OpenAI ignores it.
    let includeStreamFalse: Bool
}

// MARK: - Config Presets

extension OpenAICompatibleConfig {

    static let openAI = OpenAICompatibleConfig(
        providerID: "openai",
        displayName: "OpenAI",
        isCloud: true,
        defaultBaseURL: URL(string: "https://api.openai.com/v1")!,
        authStyle: .bearer,
        modelFilter: { entry in
            let id = entry.id.lowercased()
            guard id.hasPrefix("gpt-") || id.hasPrefix("o1") || id.hasPrefix("o3") || id.hasPrefix("o4") else {
                return false
            }
            let excluded = ["instruct", "vision-preview", "0301", "0314"]
            return !excluded.contains(where: { id.contains($0) })
        },
        modelNameFormatter: nil,
        modelCacheDuration: 300,
        requestTimeout: 60,
        includeStreamFalse: false
    )

    static let lmStudio = OpenAICompatibleConfig(
        providerID: "lmstudio",
        displayName: "LM Studio (Local)",
        isCloud: false,
        defaultBaseURL: URL(string: "http://localhost:1234/v1")!,
        authStyle: nil,
        modelFilter: nil,
        modelNameFormatter: nil,
        modelCacheDuration: 60,
        requestTimeout: 30,
        includeStreamFalse: true
    )

    static let customOpenAI = OpenAICompatibleConfig(
        providerID: "custom-openai",
        displayName: "Custom (OpenAI Compatible)",
        isCloud: true,
        defaultBaseURL: URL(string: "https://api.example.com/v1")!,
        authStyle: .bearer,
        modelFilter: nil,
        modelNameFormatter: nil,
        modelCacheDuration: 300,
        requestTimeout: 60,
        includeStreamFalse: false
    )
}

// MARK: - Engine

/// Shared HTTP logic for any OpenAI-compatible API.
/// Owned by provider instances; not a provider itself.
final class OpenAICompatibleEngine: @unchecked Sendable {

    let config: OpenAICompatibleConfig
    var baseURL: URL

    private let session: URLSession
    private var cachedModels: [AIModel] = []
    private var lastModelFetch: Date?

    init(config: OpenAICompatibleConfig) {
        self.config = config
        self.baseURL = config.defaultBaseURL

        let sessionConfig = URLSessionConfiguration.default
        sessionConfig.timeoutIntervalForRequest = config.requestTimeout
        sessionConfig.timeoutIntervalForResource = 300
        self.session = URLSession(configuration: sessionConfig)
    }

    // MARK: - Server Health

    /// Quick health check — hits the `/models` endpoint with a short timeout.
    func isServerRunning() async -> Bool {
        let url = baseURL.appending(path: "models")
        var request = URLRequest(url: url)
        request.timeoutInterval = 5

        do {
            let (_, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse else { return false }
            return http.statusCode == 200
        } catch {
            return false
        }
    }

    // MARK: - Fetch Models

    /// Fetch available models from the `/models` endpoint.
    /// Results are cached for `config.modelCacheDuration`.
    func fetchModels(apiKey: String?) async throws -> [AIModel] {
        // Return cache if still fresh
        if let lastFetch = lastModelFetch,
           Date.now.timeIntervalSince(lastFetch) < config.modelCacheDuration,
           !cachedModels.isEmpty {
            return cachedModels
        }

        let url = baseURL.appending(path: "models")
        var request = URLRequest(url: url)
        applyAuth(to: &request, apiKey: apiKey)

        let (data, response) = try await session.data(for: request)

        guard let http = response as? HTTPURLResponse else {
            throw AIProviderError.connectionFailed("Invalid response")
        }

        if http.statusCode == 401 {
            throw AIProviderError.authenticationFailed
        }

        guard http.statusCode == 200 else {
            throw AIProviderError.connectionFailed("HTTP \(http.statusCode)")
        }

        let modelsResponse = try JSONDecoder().decode(OpenAICompatibleModelsResponse.self, from: data)

        var entries = modelsResponse.data

        // Apply provider-specific filter if provided
        if let filter = config.modelFilter {
            entries = entries.filter(filter)
        }

        // Sort by ID descending (newest first for most providers)
        entries.sort { $0.id > $1.id }

        let formatter = config.modelNameFormatter ?? Self.defaultModelNameFormatter
        let models = entries.map { entry in
            AIModel(
                id: entry.id,
                name: formatter(entry.id),
                provider: config.providerID
            )
        }

        cachedModels = models
        lastModelFetch = Date.now

        return models
    }

    /// Clear the model cache so the next `fetchModels` call hits the server.
    func invalidateModelCache() {
        cachedModels = []
        lastModelFetch = nil
    }

    // MARK: - Chat Completion

    /// Send a chat completion request and return the result.
    func complete(
        model: AIModel,
        messages: [ConversationMessage],
        systemPrompt: String?,
        maxTokens: Int,
        apiKey: String?
    ) async throws -> AICompletionResult {

        let url = baseURL.appending(path: "chat/completions")

        // Build message array
        var apiMessages: [OpenAICompatibleMessage] = []

        if let system = systemPrompt {
            apiMessages.append(OpenAICompatibleMessage(role: "system", content: system))
        }

        apiMessages += messages.map {
            OpenAICompatibleMessage(role: $0.role.rawValue, content: $0.content)
        }

        let requestBody = OpenAICompatibleRequest(
            model: model.id,
            messages: apiMessages,
            max_tokens: maxTokens,
            temperature: 0.7,
            stream: config.includeStreamFalse ? false : nil
        )

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        applyAuth(to: &request, apiKey: apiKey)
        request.httpBody = try JSONEncoder().encode(requestBody)

        let (data, response) = try await session.data(for: request)

        guard let http = response as? HTTPURLResponse else {
            throw AIProviderError.connectionFailed("Invalid response")
        }

        // Handle error responses
        if http.statusCode != 200 {
            if let errorResponse = try? JSONDecoder().decode(OpenAICompatibleErrorResponse.self, from: data) {
                let errorType = errorResponse.error.type?.lowercased() ?? ""
                if errorType.contains("auth") || errorType.contains("invalid_api_key") || http.statusCode == 401 {
                    throw AIProviderError.authenticationFailed
                }
                if errorType.contains("rate_limit") || http.statusCode == 429 {
                    throw AIProviderError.rateLimited
                }
                if errorType.contains("context_length") {
                    throw AIProviderError.contextTooLong
                }
                throw AIProviderError.invalidResponse(errorResponse.error.message)
            }
            throw AIProviderError.invalidResponse("HTTP \(http.statusCode)")
        }

        let completionResponse = try JSONDecoder().decode(OpenAICompatibleResponse.self, from: data)

        guard let choice = completionResponse.choices.first else {
            throw AIProviderError.invalidResponse("No response content")
        }

        return AICompletionResult(
            content: choice.message.content,
            model: completionResponse.model,
            tokensUsed: completionResponse.usage?.total_tokens,
            finishReason: choice.finish_reason,
            isFromCloud: config.isCloud
        )
    }

    // MARK: - Private Helpers

    /// Apply authentication to a request based on the config's auth style.
    private func applyAuth(to request: inout URLRequest, apiKey: String?) {
        guard let apiKey = apiKey, let style = config.authStyle else { return }

        switch style {
        case .bearer:
            request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        case .custom(let header):
            request.setValue(apiKey, forHTTPHeaderField: header)
        }
    }

    /// Default model name formatter: replaces hyphens/underscores with spaces, capitalizes each word.
    private static let defaultModelNameFormatter: @Sendable (String) -> String = { id in
        id.replacing("-", with: " ")
          .replacing("_", with: " ")
          .split(separator: " ")
          .map { $0.capitalized }
          .joined(separator: " ")
    }
}
