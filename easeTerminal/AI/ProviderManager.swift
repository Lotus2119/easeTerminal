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
@MainActor
@Observable
public final class ProviderManager: ProviderManaging {
    
    // MARK: - Singleton
    
    public static let shared = ProviderManager()
    
    // MARK: - Operating Mode
    
    /// Current operating mode. Local is default.
    public var operatingMode: AIOperatingMode {
        didSet {
            UserDefaults.standard.set(operatingMode.rawValue, forKey: "ai.operatingMode")
            
            if operatingMode == .local {
                // Switching to local mode - don't nil out cloud provider to preserve selection
            } else if operatingMode == .hybrid {
                // Switching to hybrid mode - ensure cloud provider is loaded
                if activeCloudProvider == nil {
                    loadCloudProviderSelection()
                }
                // Refresh cloud status to update UI
                refreshCloudStatus()
            }
        }
    }
    
    // MARK: - Local Provider
    
    /// The active local inference provider
    public private(set) var localProvider: (any LocalInferenceProvider)?
    
    /// ID of the currently selected local provider type
    public private(set) var selectedLocalProviderID: String = OllamaProvider.providerID
    
    /// Cached status of the local provider - explicitly stored so @Observable tracks it
    /// Updated via refreshLocalProvider()
    public private(set) var localStatus: ProviderStatus = .notDetected
    
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
                // Check if already configured
                refreshCloudStatus()
            } else {
                activeCloudProvider = nil
                cloudConfigured = false
                cloudModelName = nil
            }
        }
    }
    
    /// Whether cloud provider is configured (has API key)
    /// Explicitly stored so @Observable tracks changes
    public private(set) var cloudConfigured: Bool = false
    
    /// Cached cloud model name - explicitly stored so @Observable tracks changes
    /// Updated via refreshCloudStatus()
    public private(set) var cloudModelName: String?
    
    // MARK: - State
    
    /// Whether the local provider is installed/reachable and running
    public var isLocalProviderAvailable: Bool {
        if case .ready = localStatus { return true }
        if case .noModels = localStatus { return true }
        return false
    }
    
    /// Whether we need to show onboarding
    public var needsOnboarding: Bool {
        !isLocalProviderAvailable || availableLocalModels.isEmpty
    }
    
    /// All registered local provider IDs paired with display names
    public var availableLocalProviders: [(id: String, name: String)] {
        ProviderRegistry.shared.availableLocalProviders.map { id in
            let name: String
            switch id {
            case OllamaProvider.providerID:          name = OllamaProvider.displayName
            case LMStudioProvider.providerID:        name = LMStudioProvider.displayName
            case FoundationModelProvider.providerID: name = FoundationModelProvider.displayName
            default:                                 name = id.capitalized
            }
            return (id: id, name: name)
        }
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
            // Use cached cloudModelName to ensure @Observable triggers updates
            if let modelName = cloudModelName {
                return "Cloud: \(modelName)"
            } else if cloudConfigured {
                // Has API key but no model selected yet
                return "Cloud: Select model"
            }
            return "Cloud: Not configured"
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
        
        // Always load cloud provider selection (API key may be saved in keychain)
        loadCloudProviderSelection()
    }
    
    private func registerBuiltInProviders() {
        OllamaProvider.register()
        LMStudioProvider.register()
        FoundationModelProvider.register()
        ClaudeProvider.register()
        OpenAIProvider.register()
    }
    
    private func initializeLocalProvider() {
        let savedID = UserDefaults.standard.string(forKey: "ai.localProviderID") ?? OllamaProvider.providerID
        setLocalProvider(id: savedID)
    }
    
    /// Switch the active local provider and persist the selection.
    /// Also restores any previously saved custom base URL for the chosen provider.
    public func setLocalProvider(id: String) {
        guard let provider = ProviderRegistry.shared.createLocalProvider(id: id) else { return }
        
        // Restore saved base URL for this provider, if any
        if let savedURLString = UserDefaults.standard.string(forKey: "ai.localBaseURL.\(id)"),
           let savedURL = URL(string: savedURLString) {
            provider.baseURL = savedURL
        }
        
        localProvider = provider
        selectedLocalProviderID = id
        UserDefaults.standard.set(id, forKey: "ai.localProviderID")
        availableLocalModels = []
        // Reset status when switching providers
        localStatus = .disconnected
    }
    
    /// Update the base URL for the current local provider and persist it.
    public func setLocalBaseURL(_ url: URL) {
        guard let provider = localProvider else { return }
        provider.baseURL = url
        UserDefaults.standard.set(url.absoluteString, forKey: "ai.localBaseURL.\(type(of: provider).providerID)")
    }
    
    private func loadCloudProviderSelection() {
        if let cloudID = UserDefaults.standard.string(forKey: "ai.cloudProviderID") {
            selectedCloudProviderID = cloudID
            // refreshCloudStatus is called in the setter
        }
        // Also refresh status in case there's an API key saved
        refreshCloudStatus()
    }
    
    /// Refresh cloud provider status - call after API key changes or model selection
    public func refreshCloudStatus() {
        guard let provider = activeCloudProvider else {
            cloudConfigured = false
            cloudModelName = nil
            return
        }
        // Consider configured if we have an API key - model can be selected later
        cloudConfigured = provider.hasAPIKey
        // Cache the model name so @Observable can track changes
        cloudModelName = provider.selectedModel?.name
    }
    
    // MARK: - Setup & Configuration
    
    /// Initialize the AI system. Call on app launch.
    public func initialize() async {
        // Test local provider connection
        await refreshLocalProvider()
        
        // If cloud provider has an API key, fetch models to restore selection
        if let cloudProvider = activeCloudProvider, cloudProvider.hasAPIKey {
            do {
                _ = try await cloudProvider.fetchAvailableModels()
                refreshCloudStatus()
            } catch {
                // Silently fail - user can manually refresh in settings
            }
        }
    }
    
    /// Refresh local provider status and available models
    public func refreshLocalProvider() async {
        guard let provider = localProvider else {
            localStatus = .notDetected
            return
        }
        
        // Set connecting status before we start
        localStatus = .connecting
        
        do {
            _ = try await provider.testConnection()
            availableLocalModels = try await provider.fetchAvailableModels()
            
            // Auto-select default model if none selected
            if localReasoningModel == nil {
                selectDefaultLocalModel()
            }
            
            // Update context packager with available models
            await ContextPackager.shared.loadSavedModel(from: availableLocalModels)
            
            // Update cached status from provider
            localStatus = provider.status
            
        } catch {
            availableLocalModels = []
            // Update cached status from provider after error
            localStatus = provider.status
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

// MARK: - Environment Key

extension EnvironmentValues {
    @Entry var providerManager: any ProviderManaging = ProviderManager.shared
}

// MARK: - Convenience Extensions

extension ProviderManager {
    /// Whether cloud features are available (API key set)
    public var isCloudAvailable: Bool {
        activeCloudProvider?.hasAPIKey == true
    }
    
    /// Status color for UI
    public var statusColor: Color {
        // In hybrid mode, check cloud configuration first
        if operatingMode == .hybrid {
            if cloudConfigured && cloudModelName != nil {
                return .blue
            } else {
                // Hybrid mode but cloud not fully configured
                return .orange
            }
        }
        
        // Local mode - use local status
        switch localStatus {
        case .ready:
            return .green
        case .connecting:
            return .yellow
        case .noModels, .notDetected:
            return .orange
        case .disconnected:
            return .gray
        case .error:
            return .red
        }
    }
}
