//
//  CloudSetupSection.swift
//  easeTerminal
//
//  Settings form section for configuring optional cloud AI providers.
//

import SwiftUI

struct CloudSetupSection: View {
    @State private var providerManager = ProviderManager.shared
    @State private var apiKeyInput = ""
    @State private var isTestingConnection = false
    @State private var connectionTestResult: Bool?
    @State private var showAPIKeyField = false
    @State private var saveKeyError: String?
    
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
        .alert("Couldn't Save API Key", isPresented: Binding(
            get: { saveKeyError != nil },
            set: { if !$0 { saveKeyError = nil } }
        )) {
            Button("OK", role: .cancel) { saveKeyError = nil }
        } message: {
            if let message = saveKeyError {
                Text(message)
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
            saveKeyError = error.localizedDescription
        }
    }
    
    private func testConnection() {
        guard let provider = providerManager.activeCloudProvider else { return }
        
        isTestingConnection = true
        connectionTestResult = nil
        
        Task {
            do {
                connectionTestResult = try await provider.testConnection()
            } catch {
                connectionTestResult = false
            }
            isTestingConnection = false
        }
    }
}
