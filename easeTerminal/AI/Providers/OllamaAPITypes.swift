//
//  OllamaAPITypes.swift
//  easeTerminal
//
//  Shared Ollama API request/response types used by both
//  OllamaProvider and ContextPackager.
//

import Foundation

// MARK: - /api/generate

struct OllamaGenerateRequest: Codable {
    let model: String
    let prompt: String
    let system: String?
    let stream: Bool
    let options: Options?

    struct Options: Codable {
        let num_predict: Int?
    }
}

struct OllamaGenerateResponse: Codable {
    let model: String
    let response: String
    let done: Bool
    let total_duration: Int64?
    let eval_count: Int?
}
