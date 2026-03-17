//
//  OpenAICompatibleAPITypes.swift
//  easeTerminal
//
//  Shared Codable types for any API that follows the OpenAI chat/completions format.
//  Used by OpenAIProvider, LMStudioProvider, and any future OpenAI-compatible providers.
//

import Foundation

// MARK: - Chat Completion Request

struct OpenAICompatibleRequest: Codable {
    let model: String
    let messages: [OpenAICompatibleMessage]
    let max_tokens: Int?
    let temperature: Double?
    let stream: Bool?
}

struct OpenAICompatibleMessage: Codable {
    let role: String
    let content: String
}

// MARK: - Chat Completion Response

struct OpenAICompatibleResponse: Codable {
    let id: String?
    let model: String
    let choices: [OpenAICompatibleChoice]
    let usage: OpenAICompatibleUsage?
}

struct OpenAICompatibleChoice: Codable {
    let index: Int?
    let message: OpenAICompatibleMessage
    let finish_reason: String?
}

struct OpenAICompatibleUsage: Codable {
    let prompt_tokens: Int?
    let completion_tokens: Int?
    let total_tokens: Int
}

// MARK: - Error Response

struct OpenAICompatibleErrorResponse: Codable {
    let error: OpenAICompatibleErrorDetail
}

struct OpenAICompatibleErrorDetail: Codable {
    let message: String
    let type: String?
    let code: String?
}

// MARK: - Models List Response

struct OpenAICompatibleModelsResponse: Codable {
    let data: [OpenAICompatibleModelEntry]
}

struct OpenAICompatibleModelEntry: Codable {
    let id: String
    let object: String?
    let owned_by: String?
}
