//
//  OpenAICompatibleCloudBase.swift
//  easeTerminal
//
//  Base class for cloud providers that use the OpenAI-compatible API format.
//  Subclasses only need to override `providerID`, `displayName`, and provide a config.
//  Everything else — API key management, model fetching, completions — is inherited.
//

import Foundation

/// Base class for cloud providers backed by an OpenAI-compatible API.
/// Subclass this, override `providerID` and `displayName`, call `super.init(config:)`.
@MainActor
public class OpenAICompatibleCloudBase: CloudReasoningProvider {

    // MARK: - Subclass Overrides

    /// Unique identifier. Subclasses MUST override.
    open class var providerID: String { fatalError("Subclass must override providerID") }

    /// Human-readable name. Subclasses MUST override.
    open class var displayName: String { fatalError("Subclass must override displayName") }

    public static let isCloudProvider = true

    // MARK: - Engine

    let engine: OpenAICompatibleEngine

    // MARK: - State

    public var selectedModel: AIModel? {
        didSet {
            let key = "\(type(of: self).providerID).selectedModel"
            if let model = selectedModel {
                UserDefaults.standard.set(model.id, forKey: key)
            } else {
                UserDefaults.standard.removeObject(forKey: key)
            }
        }
    }

    private var _status: ProviderStatus = .disconnected
    public var status: ProviderStatus { _status }

    public var isReady: Bool {
        hasAPIKey && selectedModel != nil && _status == .ready
    }

    public var hasAPIKey: Bool {
        KeychainHelper.shared.hasAPIKey(forProvider: type(of: self).providerID)
    }

    // MARK: - Init

    init(config: OpenAICompatibleConfig) {
        self.engine = OpenAICompatibleEngine(config: config)
    }

    // MARK: - CloudReasoningProvider

    public func setAPIKey(_ key: String) throws {
        try KeychainHelper.shared.saveAPIKey(key, forProvider: type(of: self).providerID)
    }

    public func clearAPIKey() throws {
        try KeychainHelper.shared.deleteAPIKey(forProvider: type(of: self).providerID)
        _status = .disconnected
        engine.invalidateModelCache()
        selectedModel = nil
    }

    public func fetchAvailableModels() async throws -> [AIModel] {
        let pid = type(of: self).providerID
        guard let apiKey = KeychainHelper.shared.getAPIKey(forProvider: pid) else {
            throw AIProviderError.notConfigured("API key not set")
        }

        let models = try await engine.fetchModels(apiKey: apiKey)

        // Restore saved selection if nothing is selected yet
        let savedKey = "\(pid).selectedModel"
        if let savedID = UserDefaults.standard.string(forKey: savedKey),
           selectedModel == nil {
            selectedModel = models.first { $0.id == savedID }
        }

        return models
    }

    // MARK: - ReasoningProvider

    public func testConnection() async throws -> Bool {
        guard hasAPIKey else {
            _status = .error("No API key")
            throw AIProviderError.notConfigured("API key not set")
        }

        _status = .connecting

        do {
            let models = try await fetchAvailableModels()
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

    public func complete(
        messages: [ConversationMessage],
        systemPrompt: String?,
        maxTokens: Int
    ) async throws -> AICompletionResult {
        let pid = type(of: self).providerID
        guard let apiKey = KeychainHelper.shared.getAPIKey(forProvider: pid) else {
            throw AIProviderError.notConfigured("API key not set")
        }
        guard let model = selectedModel else {
            throw AIProviderError.notConfigured("No model selected")
        }
        return try await engine.complete(
            model: model,
            messages: messages,
            systemPrompt: systemPrompt,
            maxTokens: maxTokens,
            apiKey: apiKey
        )
    }
}
