//
//  OpenAICompatibleLocalBase.swift
//  easeTerminal
//
//  Base class for local providers that use the OpenAI-compatible API format.
//  Subclasses only need to override `providerID`, `displayName`, and provide a config.
//  Everything else — server detection, model fetching, completions — is inherited.
//

import Foundation

/// Base class for local providers backed by an OpenAI-compatible API.
/// Subclass this, override `providerID` and `displayName`, call `super.init(config:)`.
@MainActor
public class OpenAICompatibleLocalBase: LocalInferenceProvider {

    // MARK: - Subclass Overrides

    /// Unique identifier. Subclasses MUST override.
    open class var providerID: String { fatalError("Subclass must override providerID") }

    /// Human-readable name. Subclasses MUST override.
    open class var displayName: String { fatalError("Subclass must override displayName") }

    public static let isCloudProvider = false

    // MARK: - Engine

    let engine: OpenAICompatibleEngine

    // MARK: - LocalInferenceProvider

    public var baseURL: URL {
        get { engine.baseURL }
        set { engine.baseURL = newValue }
    }

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
        if case .ready = _status { return true }
        return false
    }

    // MARK: - Init

    init(config: OpenAICompatibleConfig, baseURL: URL? = nil) {
        self.engine = OpenAICompatibleEngine(config: config)
        if let url = baseURL {
            self.engine.baseURL = url
        }
    }

    // MARK: - LocalInferenceProvider

    public func isServerRunning() async -> Bool {
        await engine.isServerRunning()
    }

    public func fetchAvailableModels() async throws -> [AIModel] {
        let models = try await engine.fetchModels(apiKey: nil)

        if models.isEmpty {
            _status = .noModels
            throw AIProviderError.ollamaNoModels
        }

        _status = .ready
        return models
    }

    // MARK: - ReasoningProvider

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
        return try await engine.complete(
            model: model,
            messages: messages,
            systemPrompt: systemPrompt,
            maxTokens: maxTokens,
            apiKey: nil
        )
    }

    // MARK: - Helpers

    private func loadSavedModelSelection(from models: [AIModel]) {
        if selectedModel != nil { return }
        let key = "\(type(of: self).providerID).selectedModel"
        if let savedID = UserDefaults.standard.string(forKey: key),
           let model = models.first(where: { $0.id == savedID }) {
            selectedModel = model
        } else {
            selectedModel = models.first
        }
    }
}
