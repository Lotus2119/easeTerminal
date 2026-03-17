//
//  OpenAIProvider.swift
//  easeTerminal
//
//  OpenAI cloud reasoning provider.
//  OPTIONAL - requires user's own API key.
//  Used in Hybrid mode for reasoning while local Ollama handles context packaging.
//

import Foundation

/// OpenAI cloud reasoning provider.
/// Thin subclass of the shared OpenAI-compatible base — all HTTP logic lives in the engine.
@MainActor
public final class OpenAIProvider: OpenAICompatibleCloudBase {

    override public class var providerID: String { "openai" }
    override public class var displayName: String { "OpenAI" }

    public init() {
        super.init(config: .openAI)
    }
}

// MARK: - Provider Registration

extension OpenAIProvider {
    /// Register this provider with the global registry
    public static func register() {
        ProviderRegistry.shared.registerCloudProvider(id: providerID, displayName: displayName) {
            OpenAIProvider()
        }
    }
}
