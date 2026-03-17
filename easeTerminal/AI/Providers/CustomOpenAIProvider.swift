//
//  CustomOpenAIProvider.swift
//  easeTerminal
//
//  User-configurable cloud provider for any OpenAI-compatible API.
//  The user provides both a base URL and an API key.
//  Works with Groq, Together AI, Mistral, Fireworks, OpenRouter, or any
//  self-hosted endpoint that speaks the OpenAI chat/completions format.
//

import Foundation

/// Cloud provider for any user-specified OpenAI-compatible endpoint.
/// Unlike the fixed-URL providers (OpenAI, Claude), this one lets
/// the user enter whatever base URL they want.
@MainActor
public final class CustomOpenAIProvider: OpenAICompatibleCloudBase {

    override public class var providerID: String { "custom-openai" }
    override public class var displayName: String { "Custom (OpenAI Compatible)" }

    private static let baseURLKey = "ai.cloudBaseURL.custom-openai"

    /// The user-configured base URL. Persisted to UserDefaults.
    public var baseURL: URL {
        get { engine.baseURL }
        set {
            engine.baseURL = newValue
            UserDefaults.standard.set(newValue.absoluteString, forKey: Self.baseURLKey)
            // Changing the URL invalidates any cached models
            engine.invalidateModelCache()
        }
    }

    public init() {
        super.init(config: .customOpenAI)

        // Restore saved base URL
        if let saved = UserDefaults.standard.string(forKey: Self.baseURLKey),
           let url = URL(string: saved) {
            engine.baseURL = url
        }
    }
}

// MARK: - Provider Registration

extension CustomOpenAIProvider {
    public static func register() {
        ProviderRegistry.shared.registerCloudProvider(id: providerID, displayName: displayName) {
            CustomOpenAIProvider()
        }
    }
}
