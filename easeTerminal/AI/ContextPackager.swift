//
//  ContextPackager.swift
//  easeTerminal
//
//  Context packaging always runs locally via Ollama.
//  This extracts the essential information from terminal output and prepares
//  it for the reasoning provider (whether local or cloud).
//
//  Design Decision:
//  Context packaging ALWAYS uses local inference regardless of operating mode.
//  This ensures:
//  - Terminal data never leaves the user's machine unless they explicitly choose cloud reasoning
//  - Consistent preprocessing regardless of reasoning backend
//  - No API costs for the packaging step
//

import Foundation

/// Packages terminal context for reasoning.
/// Always uses local Ollama inference - never sends raw terminal data to the cloud.
public actor ContextPackager {
    
    // MARK: - Singleton
    
    public static let shared = ContextPackager()
    
    // MARK: - Configuration
    
    /// The Ollama model used for context packaging
    private var packagingModel: AIModel?
    
    /// Base URL for Ollama API
    private var ollamaBaseURL = URL(string: "http://localhost:11434")!
    
    /// URLSession for API calls
    private let session: URLSession
    
    // MARK: - Initialization
    
    private init() {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 30
        config.timeoutIntervalForResource = 120
        self.session = URLSession(configuration: config)
    }
    
    // MARK: - Configuration
    
    /// Set the model to use for context packaging
    public func setPackagingModel(_ model: AIModel) {
        self.packagingModel = model
        UserDefaults.standard.set(model.id, forKey: "contextPackager.modelID")
    }
    
    /// Get the current packaging model
    public func getPackagingModel() -> AIModel? {
        return packagingModel
    }
    
    /// Load saved model selection
    public func loadSavedModel(from availableModels: [AIModel]) {
        if let savedID = UserDefaults.standard.string(forKey: "contextPackager.modelID"),
           let model = availableModels.first(where: { $0.id == savedID }) {
            self.packagingModel = model
        } else if let defaultModel = availableModels.first(where: { $0.isRecommendedDefault }) {
            // Auto-select qwen3-coder:30b if available
            self.packagingModel = defaultModel
        } else if let firstModel = availableModels.first {
            // Fall back to first available model
            self.packagingModel = firstModel
        }
    }
    
    // MARK: - Context Packaging
    
    /// Package raw terminal context into a concise summary for reasoning.
    /// This extracts key information like:
    /// - Commands that were run
    /// - Error messages and exit codes
    /// - Relevant output patterns
    /// - File paths and environment context
    ///
    /// - Parameters:
    ///   - rawContext: The raw terminal output to package
    ///   - maxOutputTokens: Maximum tokens for the packaged output
    /// - Returns: A concise, structured summary of the terminal context
    public func packageContext(_ rawContext: String, maxOutputTokens: Int = 1000) async throws -> String {
        guard let model = packagingModel else {
            // No model configured - return raw context truncated
            // This allows the system to work even before full setup
            return truncateContext(rawContext, maxLength: 4000)
        }
        
        let systemPrompt = """
        You are a context packager for a terminal AI assistant. Your job is to analyze raw terminal output and extract the essential information needed for troubleshooting.
        
        Extract and summarize:
        1. Commands that were executed (in order)
        2. Any error messages, warnings, or failures
        3. Exit codes if visible
        4. Relevant file paths mentioned
        5. Environment context (working directory, relevant env vars)
        6. The apparent goal or task the user is trying to accomplish
        
        Output a concise, structured summary. Remove noise like progress bars, repeated output, and verbose logging unless it's directly relevant to an error.
        
        Keep your response under \(maxOutputTokens) tokens. Be direct and factual.
        """
        
        let userPrompt = """
        Package this terminal context:
        
        ---
        \(rawContext)
        ---
        """
        
        return try await callOllama(
            model: model.id,
            systemPrompt: systemPrompt,
            userPrompt: userPrompt,
            maxTokens: maxOutputTokens
        )
    }
    
    /// Lightweight context pass-through for when packaging isn't needed.
    /// Just truncates and cleans up the raw context.
    public func passthrough(_ rawContext: String, maxLength: Int = 8000) -> String {
        return truncateContext(rawContext, maxLength: maxLength)
    }
    
    // MARK: - Ollama API
    
    private struct OllamaGenerateRequest: Codable {
        let model: String
        let prompt: String
        let system: String?
        let stream: Bool
        let options: OllamaOptions?
        
        struct OllamaOptions: Codable {
            let num_predict: Int?
        }
    }
    
    private struct OllamaGenerateResponse: Codable {
        let model: String
        let response: String
        let done: Bool
        let total_duration: Int64?
        let eval_count: Int?
    }
    
    private func callOllama(
        model: String,
        systemPrompt: String,
        userPrompt: String,
        maxTokens: Int
    ) async throws -> String {
        let url = ollamaBaseURL.appendingPathComponent("api/generate")
        
        let requestBody = OllamaGenerateRequest(
            model: model,
            prompt: userPrompt,
            system: systemPrompt,
            stream: false,
            options: .init(num_predict: maxTokens)
        )
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(requestBody)
        
        let (data, response) = try await session.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw AIProviderError.connectionFailed("Invalid response")
        }
        
        guard httpResponse.statusCode == 200 else {
            if httpResponse.statusCode == 404 {
                throw AIProviderError.modelNotFound(model)
            }
            throw AIProviderError.connectionFailed("HTTP \(httpResponse.statusCode)")
        }
        
        let ollamaResponse = try JSONDecoder().decode(OllamaGenerateResponse.self, from: data)
        return ollamaResponse.response.trimmingCharacters(in: .whitespacesAndNewlines)
    }
    
    // MARK: - Utilities
    
    private func truncateContext(_ context: String, maxLength: Int) -> String {
        if context.count <= maxLength {
            return context
        }
        
        // Keep the end of the context (most recent output is usually most relevant)
        let startIndex = context.index(context.endIndex, offsetBy: -maxLength)
        return "...[truncated]...\n" + String(context[startIndex...])
    }
}
