//
//  ProviderManager.swift
//  easeTerminal
//
//  Central manager for the local-first AI architecture.
//  Handles operating mode, provider selection, and the reasoning pipeline.
//
//  Design:
//  - Local mode is DEFAULT: Ollama handles both context packaging and reasoning
//  - Hybrid mode is OPTIONAL: Local context packaging + cloud reasoning
//  - Mode switching is seamless - pipeline doesn't care which backend is active
//

import Foundation
import SwiftUI

/// Central manager for AI providers and operating mode.
/// Observable for SwiftUI integration.
@Observable
public final class ProviderManager {
    
    // MARK: - Singleton
    
    public static let shared = ProviderManager()
    
    // MARK: - Operating Mode
    
    /// Current operating mode. Local is default.
    public var operatingMode: AIOperatingMode {
        didSet {
            UserDefaults.standard.set(operatingMode.rawValue, forKey: "ai.operatingMode")
            
            // If switching to local mode, ensure we can fall back
            if operatingMode == .local {
                activeCloudProvider = nil
            }
        }
    }
    
    // MARK: - Local Provider
    
    /// The local inference provider (Ollama)
    public private(set) var localProvider: (any LocalInferenceProvider)?
    
    /// Status of the local provider
    public var localStatus: ProviderStatus {
        localProvider?.status ?? .notInstalled
    }
    
    /// Available models from local provider (fetched dynamically)
    public private(set) var availableLocalModels: [AIModel] = []
    
    /// Model selected for local reasoning
    public var localReasoningModel: AIModel? {
        get { localProvider?.selectedModel }
        set { localProvider?.selectedModel = newValue }
    }
    
    /// Model selected for context packaging (can be same as reasoning model)
    public var contextPackagingModel: AIModel?
    
    // MARK: - Cloud Provider (Optional)
    
    /// The active cloud provider for hybrid mode
    public private(set) var activeCloudProvider: (any CloudReasoningProvider)?
    
    /// ID of the selected cloud provider type
    public var selectedCloudProviderID: String? {
        didSet {
            UserDefaults.standard.set(selectedCloudProviderID, forKey: "ai.cloudProviderID")
            if let id = selectedCloudProviderID {
                activeCloudProvider = ProviderRegistry.shared.createCloudProvider(id: id)
            } else {
                activeCloudProvider = nil
            }
        }
    }
    
    // MARK: - State
    
    /// Whether Ollama is installed and running
    public var isOllamaAvailable: Bool {
        if case .ready = localStatus { return true }
        if case .noModels = localStatus { return true } // Running but no models
        return false
    }
    
    /// Whether we need to show onboarding
    public var needsOnboarding: Bool {
        !isOllamaAvailable || availableLocalModels.isEmpty
    }
    
    /// Whether the system is ready for AI operations
    public var isReady: Bool {
        switch operatingMode {
        case .local:
            return localProvider?.isReady == true
        case .hybrid:
            // Need local for context packaging, cloud for reasoning
            return localProvider?.isReady == true && activeCloudProvider?.isReady == true
        }
    }
    
    /// Human-readable status for display
    public var statusText: String {
        switch operatingMode {
        case .local:
            if let model = localReasoningModel {
                return "Local: \(model.name)"
            }
            return localStatus.displayText
        case .hybrid:
            if let cloudModel = activeCloudProvider?.selectedModel {
                return "Hybrid: \(cloudModel.name)"
            }
            return "Hybrid mode (not configured)"
        }
    }
    
    // MARK: - Initialization
    
    private init() {
        // Load saved operating mode (default to local)
        if let savedMode = UserDefaults.standard.string(forKey: "ai.operatingMode"),
           let mode = AIOperatingMode(rawValue: savedMode) {
            self.operatingMode = mode
        } else {
            self.operatingMode = .local
        }
        
        // Register built-in providers
        registerBuiltInProviders()
        
        // Initialize local provider
        initializeLocalProvider()
        
        // Load cloud provider selection if in hybrid mode
        if operatingMode == .hybrid {
            loadCloudProviderSelection()
        }
    }
    
    private func registerBuiltInProviders() {
        OllamaProvider.register()
        ClaudeProvider.register()
        OpenAIProvider.register()
    }
    
    private func initializeLocalProvider() {
        // Default to Ollama
        localProvider = ProviderRegistry.shared.createLocalProvider(id: OllamaProvider.providerID)
    }
    
    private func loadCloudProviderSelection() {
        if let cloudID = UserDefaults.standard.string(forKey: "ai.cloudProviderID") {
            selectedCloudProviderID = cloudID
        }
    }
    
    // MARK: - Setup & Configuration
    
    /// Initialize the AI system. Call on app launch.
    public func initialize() async {
        // Test local provider connection
        await refreshLocalProvider()
    }
    
    /// Refresh local provider status and available models
    public func refreshLocalProvider() async {
        guard let provider = localProvider else { return }
        
        do {
            _ = try await provider.testConnection()
            availableLocalModels = try await provider.fetchAvailableModels()
            
            // Auto-select default model if none selected
            if localReasoningModel == nil {
                selectDefaultLocalModel()
            }
            
            // Update context packager with available models
            await ContextPackager.shared.loadSavedModel(from: availableLocalModels)
            
        } catch {
            availableLocalModels = []
        }
    }
    
    /// Select the default local model (qwen3-coder:30b if available)
    private func selectDefaultLocalModel() {
        if let recommended = availableLocalModels.first(where: { $0.isRecommendedDefault }) {
            localReasoningModel = recommended
        } else if let first = availableLocalModels.first {
            localReasoningModel = first
        }
    }
    
    /// Get available cloud providers
    public var availableCloudProviders: [(id: String, name: String)] {
        ProviderRegistry.shared.availableCloudProviders.map { id in
            let name: String
            switch id {
            case ClaudeProvider.providerID:
                name = ClaudeProvider.displayName
            case OpenAIProvider.providerID:
                name = OpenAIProvider.displayName
            default:
                name = id.capitalized
            }
            return (id: id, name: name)
        }
    }
    
    // MARK: - AI Operations Pipeline
    
    /// Perform reasoning on terminal context.
    /// Automatically uses the correct provider based on operating mode.
    public func reason(
        terminalContext: String,
        userQuery: String? = nil,
        conversationHistory: [ConversationMessage] = []
    ) async throws -> AICompletionResult {
        
        // Step 1: Package context locally (always local)
        let packagedContext = try await ContextPackager.shared.packageContext(terminalContext)
        
        // Step 2: Perform reasoning (local or cloud based on mode)
        let reasoningProvider = getActiveReasoningProvider()
        
        guard let provider = reasoningProvider else {
            throw AIProviderError.notConfigured("No reasoning provider available")
        }
        
        return try await provider.reason(
            context: packagedContext,
            userQuery: userQuery,
            conversationHistory: conversationHistory,
            maxTokens: 4000
        )
    }
    
    /// Get the active reasoning provider based on operating mode
    private func getActiveReasoningProvider() -> (any ReasoningProvider)? {
        switch operatingMode {
        case .local:
            return localProvider
        case .hybrid:
            // Fall back to local if cloud isn't ready
            if activeCloudProvider?.isReady == true {
                return activeCloudProvider
            }
            return localProvider
        }
    }
    
    /// Direct chat completion (for chat interface)
    public func complete(
        messages: [ConversationMessage],
        systemPrompt: String? = nil
    ) async throws -> AICompletionResult {
        let provider = getActiveReasoningProvider()
        
        guard let provider = provider else {
            throw AIProviderError.notConfigured("No reasoning provider available")
        }
        
        return try await provider.complete(
            messages: messages,
            systemPrompt: systemPrompt,
            maxTokens: 4000
        )
    }
    
    // MARK: - Mode Switching
    
    /// Switch to local mode
    public func switchToLocalMode() {
        operatingMode = .local
    }
    
    /// Switch to hybrid mode (requires cloud provider to be configured)
    public func switchToHybridMode() throws {
        guard activeCloudProvider != nil else {
            throw AIProviderError.notConfigured("No cloud provider selected")
        }
        guard activeCloudProvider?.hasAPIKey == true else {
            throw AIProviderError.notConfigured("Cloud provider API key not set")
        }
        operatingMode = .hybrid
    }
    
    /// Graceful fallback to local mode if cloud fails
    public func fallbackToLocal() {
        operatingMode = .local
    }
}

// MARK: - Convenience Extensions

extension ProviderManager {
    /// Whether cloud features are available (API key set)
    public var isCloudAvailable: Bool {
        activeCloudProvider?.hasAPIKey == true
    }
    
    /// Status color for UI
    public var statusColor: Color {
        switch localStatus {
        case .ready:
            return operatingMode == .hybrid && activeCloudProvider?.isReady == true ? .blue : .green
        case .connecting:
            return .yellow
        case .noModels, .notInstalled:
            return .orange
        case .disconnected:
            return .gray
        case .error:
            return .red
        }
    }
}
