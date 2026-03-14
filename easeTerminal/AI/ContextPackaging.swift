//
//  ContextPackaging.swift
//  easeTerminal
//
//  Protocol abstraction for ContextPackager, enabling dependency injection and testability.
//

import Foundation

/// Protocol that abstracts ContextPackager for dependency injection and testing.
public protocol ContextPackaging: Actor {
    func setPackagingModel(_ model: AIModel)
    func getPackagingModel() -> AIModel?
    func loadSavedModel(from availableModels: [AIModel])
    func packageContext(_ rawContext: String, maxOutputTokens: Int) async throws -> String
    func passthrough(_ rawContext: String, maxLength: Int) -> String
}

extension ContextPackager: ContextPackaging {}
