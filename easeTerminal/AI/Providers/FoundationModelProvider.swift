//
//  FoundationModelProvider.swift
//  easeTerminal
//
//  Apple Intelligence on-device inference provider.
//  Uses the Foundation Models framework (macOS 26+) for zero-setup local AI.
//  No server, no API key, no downloads required.
//
//  Limitations:
//  - 4,096 token context window (instructions + prompts + responses combined)
//  - Device must support Apple Intelligence and have it enabled in Settings
//  - Code generation is not a primary strength of the on-device model
//

import Foundation
import FoundationModels

// MARK: - FoundationModelProvider

/// Local inference provider backed by Apple's on-device Foundation Model.
/// Conforms to LocalInferenceProvider; `baseURL` and `isServerRunning()` are
/// adapted to make sense for an on-device model with no network server.
@MainActor
public final class FoundationModelProvider: LocalInferenceProvider {

    // MARK: - Static Properties

    public static let providerID = "apple-fm"
    public static let displayName = "Apple Intelligence"
    public static let isCloudProvider = false

    // MARK: - Instance Properties

    /// Placeholder URL — Apple Intelligence has no network endpoint.
    /// The setter is intentionally a no-op; the value is never used for networking.
    public var baseURL: URL {
        get { URL(string: "on-device://apple-intelligence")! }
        set { /* no-op — on-device model has no configurable base URL */ }
    }

    public var selectedModel: AIModel? {
        didSet {
            // Only one model is available; nothing to persist.
        }
    }

    private var _status: ProviderStatus = .disconnected
    public var status: ProviderStatus { _status }

    public var isReady: Bool {
        if case .ready = _status { return true }
        return false
    }

    // MARK: - Initialization

    public init() {
        // Pre-select the single available model.
        self.selectedModel = Self.onDeviceModel
    }

    // MARK: - LocalInferenceProvider Protocol

    /// Returns true when Apple Intelligence is available on this device.
    public func isServerRunning() async -> Bool {
        if case .available = SystemLanguageModel.default.availability {
            return true
        }
        return false
    }

    /// Returns the single on-device model entry.
    public func fetchAvailableModels() async throws -> [AIModel] {
        switch SystemLanguageModel.default.availability {
        case .available:
            _status = .ready
            return [Self.onDeviceModel]
        case .unavailable(let reason):
            _status = .notDetected
            throw unavailabilityError(for: reason)
        }
    }

    // MARK: - ReasoningProvider Protocol

    public func testConnection() async throws -> Bool {
        _status = .connecting

        switch SystemLanguageModel.default.availability {
        case .available:
            _status = .ready
            selectedModel = Self.onDeviceModel
            return true
        case .unavailable(let reason):
            _status = .notDetected
            throw unavailabilityError(for: reason)
        }
    }

    /// Performs a completion by building a single-turn prompt from the message history.
    ///
    /// Because the on-device model has a 4K token context window and the app already
    /// manages conversation history externally, a **new session is created per call**
    /// to avoid accumulating tokens across turns.
    public func complete(
        messages: [ConversationMessage],
        systemPrompt: String?,
        maxTokens: Int
    ) async throws -> AICompletionResult {
        let session = LanguageModelSession(instructions: systemPrompt)

        // Concatenate user/assistant turns into a single prompt string.
        // The Foundation Models framework doesn't expose a multi-turn chat API
        // for plain string generation, so we format the history inline.
        let prompt = buildPrompt(from: messages)

        do {
            let response = try await session.respond(to: prompt)
            return AICompletionResult(
                content: response.content,
                model: "apple-intelligence",
                isFromCloud: false
            )
        } catch let error as LanguageModelSession.GenerationError {
            switch error {
            case .exceededContextWindowSize:
                throw AIProviderError.contextTooLong
            default:
                throw AIProviderError.connectionFailed(error.localizedDescription)
            }
        }
    }

    // MARK: - Helpers

    private static let onDeviceModel = AIModel(
        id: "apple-foundation-model",
        name: "Apple Intelligence",
        provider: providerID,
        parameterCount: "~3B"
    )

    /// Formats a conversation history into a single prompt string.
    /// System messages are excluded (they go to `instructions` instead).
    private func buildPrompt(from messages: [ConversationMessage]) -> String {
        let turns = messages.filter { $0.role != .system }

        guard !turns.isEmpty else { return "" }

        // For a single user message, pass the content directly.
        if turns.count == 1, turns[0].role == .user {
            return turns[0].content
        }

        // For multi-turn history, format with role labels so the model
        // understands the conversational structure.
        return turns.map { msg in
            let label = msg.role == .user ? "User" : "Assistant"
            return "\(label): \(msg.content)"
        }.joined(separator: "\n\n")
    }

    /// Maps Apple Intelligence unavailability reasons to user-facing errors.
    private func unavailabilityError(for reason: SystemLanguageModel.Availability.UnavailableReason) -> AIProviderError {
        switch reason {
        case .deviceNotEligible:
            return .notConfigured("This device does not support Apple Intelligence.")
        case .appleIntelligenceNotEnabled:
            return .notConfigured("Apple Intelligence is not enabled. Turn it on in System Settings > Apple Intelligence & Siri.")
        case .modelNotReady:
            return .notConfigured("Apple Intelligence model is not ready yet. It may still be downloading.")
        default:
            return .notConfigured("Apple Intelligence is not available on this device.")
        }
    }
}

// MARK: - Provider Registration

extension FoundationModelProvider {
    /// Register this provider with the global registry.
    public static func register() {
        ProviderRegistry.shared.registerLocalProvider(id: providerID) {
            FoundationModelProvider()
        }
    }
}
