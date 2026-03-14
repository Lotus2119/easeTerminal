//
//  AISettingsView.swift
//  easeTerminal
//
//  Settings UI for AI providers.
//  Two clear sections: Local Setup (required) and Cloud Setup (optional).
//

import SwiftUI

/// Main AI settings view
struct AISettingsView: View {
    @State private var providerManager = ProviderManager.shared
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationStack {
            Form {
                // Operating Mode
                Section {
                    Picker("Mode", selection: $providerManager.operatingMode) {
                        ForEach(AIOperatingMode.allCases, id: \.self) { mode in
                            VStack(alignment: .leading) {
                                Text(mode.displayName)
                                Text(mode.description)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            .tag(mode)
                        }
                    }
                    .pickerStyle(.inline)
                } header: {
                    Text("Operating Mode")
                } footer: {
                    Text("Local mode runs entirely on your Mac. Hybrid mode adds cloud reasoning while keeping context packaging local.")
                }
                
                // Local Setup Section
                LocalSetupSection()
                
                // Cloud Setup Section (Optional)
                CloudSetupSection()
                
                // Context Settings Section
                ContextSettingsSection()
            }
            .formStyle(.grouped)
            .navigationTitle("AI Settings")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
    }
}

// MARK: - Local Setup Section

struct LocalSetupSection: View {
    @State private var providerManager = ProviderManager.shared
    @State private var isRefreshing = false
    @State private var showModelPicker = false
    
    var body: some View {
        Section {
            // Status row
            HStack {
                statusIndicator
                
                VStack(alignment: .leading, spacing: 2) {
                    Text("Ollama")
                        .font(.headline)
                    Text(providerManager.localStatus.displayText)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                
                Spacer()
                
                Button {
                    Task {
                        isRefreshing = true
                        await providerManager.refreshLocalProvider()
                        isRefreshing = false
                    }
                } label: {
                    if isRefreshing {
                        ProgressView()
                            .controlSize(.small)
                    } else {
                        Image(systemName: "arrow.clockwise")
                    }
                }
                .buttonStyle(.borderless)
                .disabled(isRefreshing)
            }
            
            // Reasoning model picker
            if !providerManager.availableLocalModels.isEmpty {
                Picker("Reasoning Model", selection: Binding(
                    get: { providerManager.localReasoningModel?.id ?? "" },
                    set: { id in
                        providerManager.localReasoningModel = providerManager.availableLocalModels.first { $0.id == id }
                    }
                )) {
                    ForEach(providerManager.availableLocalModels) { model in
                        HStack {
                            VStack(alignment: .leading) {
                                Text(model.name)
                                if let size = model.size {
                                    Text(size)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            if model.isRecommendedDefault {
                                Text("Recommended")
                                    .font(.caption2)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(.blue.opacity(0.2), in: Capsule())
                                    .foregroundStyle(.blue)
                            }
                        }
                        .tag(model.id)
                    }
                }
                
                // Context packaging model (defaults to same as reasoning)
                Toggle("Use separate model for context packaging", isOn: .constant(false))
                    .disabled(true) // Future feature
            }
            
        } header: {
            HStack {
                Text("Local Setup")
                Text("Required")
                    .font(.caption2)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(.green.opacity(0.2), in: Capsule())
                    .foregroundStyle(.green)
            }
        } footer: {
            if providerManager.availableLocalModels.isEmpty {
                Text("No models found. Run 'ollama pull qwen3-coder:30b' to get started.")
            } else {
                Text("Qwen3-Coder 30B is recommended for coding and terminal tasks. It uses MoE with only 3.3B active parameters for fast inference.")
            }
        }
    }
    
    @ViewBuilder
    private var statusIndicator: some View {
        Circle()
            .fill(statusColor)
            .frame(width: 10, height: 10)
    }
    
    private var statusColor: Color {
        switch providerManager.localStatus {
        case .ready: return .green
        case .connecting: return .yellow
        case .noModels: return .orange
        case .notInstalled, .disconnected: return .gray
        case .error: return .red
        }
    }
}

// MARK: - Cloud Setup Section

struct CloudSetupSection: View {
    @State private var providerManager = ProviderManager.shared
    @State private var apiKeyInput = ""
    @State private var isTestingConnection = false
    @State private var connectionTestResult: Bool?
    @State private var showAPIKeyField = false
    
    var body: some View {
        Section {
            // Provider picker
            Picker("Provider", selection: Binding(
                get: { providerManager.selectedCloudProviderID ?? "" },
                set: { id in
                    providerManager.selectedCloudProviderID = id.isEmpty ? nil : id
                    connectionTestResult = nil
                }
            )) {
                Text("None").tag("")
                ForEach(providerManager.availableCloudProviders, id: \.id) { provider in
                    Text(provider.name).tag(provider.id)
                }
            }
            
            // Show configuration if a provider is selected
            if let cloudProvider = providerManager.activeCloudProvider {
                // API Key status
                HStack {
                    Text("API Key")
                    Spacer()
                    if cloudProvider.hasAPIKey {
                        HStack(spacing: 4) {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(.green)
                            Text("Configured")
                                .foregroundStyle(.secondary)
                        }
                        .font(.caption)
                        
                        Button("Change") {
                            showAPIKeyField = true
                        }
                        .buttonStyle(.borderless)
                        .font(.caption)
                    } else {
                        Button("Add Key") {
                            showAPIKeyField = true
                        }
                        .buttonStyle(.borderless)
                    }
                }
                
                // API Key input
                if showAPIKeyField {
                    HStack {
                        SecureField("API Key", text: $apiKeyInput)
                            .textFieldStyle(.roundedBorder)
                        
                        Button("Save") {
                            saveAPIKey()
                        }
                        .disabled(apiKeyInput.isEmpty)
                        
                        Button("Cancel") {
                            apiKeyInput = ""
                            showAPIKeyField = false
                        }
                        .buttonStyle(.borderless)
                    }
                }
                
                // Model picker
                if cloudProvider.hasAPIKey {
                    Picker("Model", selection: Binding(
                        get: { cloudProvider.selectedModel?.id ?? "" },
                        set: { id in
                            if let models = (cloudProvider as? ClaudeProvider).map({ type(of: $0).availableModels }) ??
                                           (cloudProvider as? OpenAIProvider).map({ type(of: $0).availableModels }) {
                                providerManager.activeCloudProvider?.selectedModel = models.first { $0.id == id }
                            }
                        }
                    )) {
                        Text("Select a model").tag("")
                        
                        if let claude = cloudProvider as? ClaudeProvider {
                            ForEach(ClaudeProvider.availableModels) { model in
                                Text(model.name).tag(model.id)
                            }
                        } else if let openai = cloudProvider as? OpenAIProvider {
                            ForEach(OpenAIProvider.availableModels) { model in
                                Text(model.name).tag(model.id)
                            }
                        }
                    }
                }
                
                // Test connection
                if cloudProvider.hasAPIKey && cloudProvider.selectedModel != nil {
                    HStack {
                        Button {
                            testConnection()
                        } label: {
                            HStack(spacing: 8) {
                                if isTestingConnection {
                                    ProgressView()
                                        .controlSize(.small)
                                }
                                Text("Test Connection")
                            }
                        }
                        .disabled(isTestingConnection)
                        
                        if let result = connectionTestResult {
                            Image(systemName: result ? "checkmark.circle.fill" : "xmark.circle.fill")
                                .foregroundStyle(result ? .green : .red)
                        }
                    }
                }
            }
            
        } header: {
            HStack {
                Text("Cloud Setup")
                Text("Optional")
                    .font(.caption2)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(.blue.opacity(0.2), in: Capsule())
                    .foregroundStyle(.blue)
            }
        } footer: {
            VStack(alignment: .leading, spacing: 8) {
                Text("Cloud providers are optional. They offer more powerful reasoning models but require your own API key and send data to external servers.")
                
                if providerManager.operatingMode == .hybrid && providerManager.activeCloudProvider?.isReady != true {
                    Text("⚠️ Hybrid mode is selected but cloud provider is not ready. Will fall back to local reasoning.")
                        .foregroundStyle(.orange)
                }
            }
        }
    }
    
    private func saveAPIKey() {
        guard !apiKeyInput.isEmpty else { return }
        
        do {
            try providerManager.activeCloudProvider?.setAPIKey(apiKeyInput)
            apiKeyInput = ""
            showAPIKeyField = false
        } catch {
            // Handle error
        }
    }
    
    private func testConnection() {
        guard let provider = providerManager.activeCloudProvider else { return }
        
        isTestingConnection = true
        connectionTestResult = nil
        
        Task {
            do {
                let result = try await provider.testConnection()
                await MainActor.run {
                    connectionTestResult = result
                    isTestingConnection = false
                }
            } catch {
                await MainActor.run {
                    connectionTestResult = false
                    isTestingConnection = false
                }
            }
        }
    }
}

// MARK: - Context Settings Section

struct ContextSettingsSection: View {
    @State private var settings = ContextSettings.loadFromDefaults()
    
    var body: some View {
        Section {
            // Max terminal lines
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text("Terminal buffer lines")
                    Spacer()
                    Text("\(settings.maxTerminalLines)")
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
                Slider(
                    value: Binding(
                        get: { Double(settings.maxTerminalLines) },
                        set: { settings.maxTerminalLines = Int($0) }
                    ),
                    in: 50...500,
                    step: 50
                )
                Text("Lines of terminal output included in context")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            
            // Max chat exchanges
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text("Chat history exchanges")
                    Spacer()
                    Text("\(settings.maxChatExchanges)")
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
                Slider(
                    value: Binding(
                        get: { Double(settings.maxChatExchanges) },
                        set: { settings.maxChatExchanges = Int($0) }
                    ),
                    in: 2...20,
                    step: 1
                )
                Text("Recent message pairs included in context")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            
            // Max full troubleshoot entries
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text("Full troubleshoot entries")
                    Spacer()
                    Text("\(settings.maxFullTroubleshootEntries)")
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
                Slider(
                    value: Binding(
                        get: { Double(settings.maxFullTroubleshootEntries) },
                        set: { settings.maxFullTroubleshootEntries = Int($0) }
                    ),
                    in: 1...5,
                    step: 1
                )
                Text("Recent troubleshoot sessions with full context")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            
            // Max total context chars
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text("Max context size")
                    Spacer()
                    Text(formatBytes(settings.maxTotalContextChars))
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
                Slider(
                    value: Binding(
                        get: { Double(settings.maxTotalContextChars) },
                        set: { settings.maxTotalContextChars = Int($0) }
                    ),
                    in: 8000...64000,
                    step: 4000
                )
                Text("Maximum total characters sent to AI")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            
            // Reset to defaults button
            HStack {
                Spacer()
                Button("Reset to Defaults") {
                    settings = ContextSettings()
                    settings.saveToDefaults()
                }
                .buttonStyle(.borderless)
                .foregroundStyle(.secondary)
            }
            
        } header: {
            Text("Context Window")
        } footer: {
            Text("These settings control how much context is included in AI requests. Larger context windows provide more information but may be slower and use more tokens.")
        }
        .onChange(of: settings) { _, newValue in
            newValue.saveToDefaults()
        }
    }
    
    private func formatBytes(_ chars: Int) -> String {
        if chars >= 1000 {
            return "\(chars / 1000)K chars"
        }
        return "\(chars) chars"
    }
}

#Preview {
    AISettingsView()
        .frame(width: 500, height: 600)
}
