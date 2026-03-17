//
//  LMStudioProvider.swift
//  easeTerminal
//
//  LM Studio local inference provider.
//  Uses the OpenAI-compatible API served by LM Studio at localhost:1234/v1.
//  No API key required — runs entirely on the user's machine.
//

import Foundation

/// LM Studio local inference provider.
/// Thin subclass of the shared OpenAI-compatible base — all HTTP logic lives in the engine.
@MainActor
public final class LMStudioProvider: OpenAICompatibleLocalBase {

    override public class var providerID: String { "lmstudio" }
    override public class var displayName: String { "LM Studio (Local)" }

    public init(baseURL: URL = URL(string: "http://localhost:1234/v1")!) {
        super.init(config: .lmStudio, baseURL: baseURL)
    }
}

// MARK: - Provider Registration

extension LMStudioProvider {
    public static func register() {
        ProviderRegistry.shared.registerLocalProvider(id: providerID, displayName: displayName) {
            LMStudioProvider()
        }
    }
}
