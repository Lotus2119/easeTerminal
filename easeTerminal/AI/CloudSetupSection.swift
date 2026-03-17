//
//  CloudSetupSection.swift
//  easeTerminal
//
//  Settings form section for configuring optional cloud AI providers.
//

import SwiftUI

/// Possible states for the API-key validation that happens on save.
private enum KeyValidationState {
    case idle
    case validating
    case verified
    case invalid(String)
}

struct CloudSetupSection: View {
    @Environment(\.providerManager) private var providerManager
    @State private var apiKeyInput = ""
    // true while the user is actively editing/replacing a key
    @State private var isEditingKey = false
    @State private var keyValidation: KeyValidationState = .idle
    @State private var availableModels: [AIModel] = []
    @State private var isFetchingModels = false
    @State private var modelFetchError: String?
    @State private var selectedProviderID: String = ""
    @State private var saveKeyError: String?
    @State private var showSaveKeyError = false
    @State private var baseURLText: String = ""
    @State private var isEditingBaseURL = false

    var body: some View {
        Section {
            // Provider picker — uses @State + onChange to avoid Binding(get:set:)
            Picker("Provider", selection: $selectedProviderID) {
                Text("None").tag("")
                ForEach(providerManager.availableCloudProviders, id: \.id) { provider in
                    Text(provider.name).tag(provider.id)
                }
            }
            .onChange(of: selectedProviderID) {
                providerManager.selectedCloudProviderID = selectedProviderID.isEmpty ? nil : selectedProviderID
                resetStateForProviderChange()
            }
            .onAppear {
                selectedProviderID = providerManager.selectedCloudProviderID ?? ""
            }

            if let cloudProvider = providerManager.activeCloudProvider {
                // Show base URL field for providers with a configurable endpoint
                if let customProvider = cloudProvider as? CustomOpenAIProvider {
                    baseURLRow(for: customProvider)
                }

                apiKeyRow(for: cloudProvider)
                modelPickerRow(for: cloudProvider)

                if cloudProvider.hasAPIKey && cloudProvider.selectedModel != nil {
                    testConnectionRow(for: cloudProvider)
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
        .alert("Couldn't Save API Key", isPresented: $showSaveKeyError) {
            Button("OK", role: .cancel) { saveKeyError = nil }
        } message: {
            Text(saveKeyError ?? "")
        }
    }

    // MARK: - API Key Row
    //
    // Three states:
    //  • No key stored        → always-visible SecureField + Save button
    //  • Key stored, viewing  → masked status badge + Change / Remove buttons
    //  • Key stored, editing  → SecureField + Save / Cancel buttons

    @ViewBuilder
    private func apiKeyRow(for cloudProvider: any CloudReasoningProvider) -> some View {
        if cloudProvider.hasAPIKey && !isEditingKey {
            // Key is saved — show status + action buttons on one row
            HStack {
                Text("API Key")
                Spacer()
                keyValidationBadge(for: cloudProvider)
                Button("Change") {
                    isEditingKey = true
                    keyValidation = .idle
                }
                .buttonStyle(.borderless)
                .font(.caption)

                Button("Remove") {
                    removeAPIKey(provider: cloudProvider)
                }
                .buttonStyle(.borderless)
                .font(.caption)
                .foregroundStyle(.red)
            }
        } else {
            // No key, or user clicked Change — show the input field inline
            HStack {
                SecureField(cloudProvider.hasAPIKey ? "New API Key" : "API Key", text: $apiKeyInput)
                    .textFieldStyle(.roundedBorder)

                Button("Save") {
                    saveAndValidateAPIKey(provider: cloudProvider)
                }
                .disabled(apiKeyInput.isEmpty || isValidating)

                if cloudProvider.hasAPIKey {
                    Button("Cancel") {
                        apiKeyInput = ""
                        isEditingKey = false
                        keyValidation = .idle
                    }
                    .buttonStyle(.borderless)
                }
            }

            // Validation feedback sits beneath the field (same logical row, separate line)
            if case .validating = keyValidation {
                HStack(spacing: 6) {
                    ProgressView().controlSize(.mini)
                    Text("Verifying key…").foregroundStyle(.secondary)
                }
                .font(.caption)
            } else if case .invalid(let msg) = keyValidation {
                Label(msg, systemImage: "xmark.circle.fill")
                    .font(.caption)
                    .foregroundStyle(.red)
            }
        }
    }

    @ViewBuilder
    private func keyValidationBadge(for cloudProvider: any CloudReasoningProvider) -> some View {
        switch keyValidation {
        case .idle:
            HStack(spacing: 4) {
                Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                Text("Configured").foregroundStyle(.secondary)
            }
            .font(.caption)
        case .validating:
            HStack(spacing: 4) {
                ProgressView().controlSize(.mini)
                Text("Verifying…").foregroundStyle(.secondary)
            }
            .font(.caption)
        case .verified:
            HStack(spacing: 4) {
                Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                Text("Verified").foregroundStyle(.secondary)
            }
            .font(.caption)
        case .invalid(let message):
            HStack(spacing: 4) {
                Image(systemName: "xmark.circle.fill").foregroundStyle(.red)
                Text(message).foregroundStyle(.red)
            }
            .font(.caption)
        }
    }

    // MARK: - Model Picker Row

    @ViewBuilder
    private func modelPickerRow(for cloudProvider: any CloudReasoningProvider) -> some View {
        if cloudProvider.hasAPIKey {
            if isFetchingModels {
                HStack {
                    Text("Model")
                    Spacer()
                    ProgressView().controlSize(.small)
                    Text("Loading models…")
                        .foregroundStyle(.secondary)
                        .font(.caption)
                }
            } else if let fetchError = modelFetchError {
                HStack {
                    Text("Model")
                    Spacer()
                    Text(fetchError).foregroundStyle(.red).font(.caption)
                    Button("Retry") {
                        Task { await fetchModels(for: cloudProvider) }
                    }
                    .buttonStyle(.borderless)
                    .font(.caption)
                }
            } else if !availableModels.isEmpty {
                CloudModelPicker(
                    cloudProvider: cloudProvider,
                    providerManager: providerManager,
                    availableModels: availableModels
                )
            } else {
                HStack {
                    Text("Model")
                    Spacer()
                    Text("No models loaded").foregroundStyle(.secondary).font(.caption)
                    Button("Load") {
                        Task { await fetchModels(for: cloudProvider) }
                    }
                    .buttonStyle(.borderless)
                    .font(.caption)
                }
            }
        }
    }

    // MARK: - Test Connection Row

    @ViewBuilder
    private func testConnectionRow(for cloudProvider: any CloudReasoningProvider) -> some View {
        HStack {
            Button {
                Task { await runManualConnectionTest(provider: cloudProvider) }
            } label: {
                HStack(spacing: 8) {
                    if isValidating { ProgressView().controlSize(.small) }
                    Text("Test Connection")
                }
            }
            .disabled(isValidating)

            switch keyValidation {
            case .verified:
                Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
            case .invalid:
                Image(systemName: "xmark.circle.fill").foregroundStyle(.red)
            default:
                EmptyView()
            }
        }
    }

    // MARK: - Base URL Row

    @ViewBuilder
    private func baseURLRow(for customProvider: CustomOpenAIProvider) -> some View {
        if isEditingBaseURL {
            HStack {
                TextField("Base URL", text: $baseURLText)
                    .textFieldStyle(.roundedBorder)

                Button("Save") {
                    if let url = URL(string: baseURLText), !baseURLText.isEmpty {
                        customProvider.baseURL = url
                        isEditingBaseURL = false
                        // Clear models since the endpoint changed
                        availableModels = []
                        modelFetchError = nil
                    }
                }
                .disabled(baseURLText.isEmpty)

                Button("Cancel") {
                    baseURLText = customProvider.baseURL.absoluteString
                    isEditingBaseURL = false
                }
                .buttonStyle(.borderless)
            }
        } else {
            HStack {
                Text("Endpoint")
                Spacer()
                Text(customProvider.baseURL.absoluteString)
                    .foregroundStyle(.secondary)
                    .font(.caption)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Button("Change") {
                    baseURLText = customProvider.baseURL.absoluteString
                    isEditingBaseURL = true
                }
                .buttonStyle(.borderless)
                .font(.caption)
            }
        }
    }

    // MARK: - Helpers

    private var isValidating: Bool {
        if case .validating = keyValidation { return true }
        return false
    }

    // MARK: - Actions

    private func resetStateForProviderChange() {
        availableModels = []
        modelFetchError = nil
        keyValidation = .idle
        isEditingKey = false
        isEditingBaseURL = false
        apiKeyInput = ""

        // Restore base URL text for custom provider
        if let customProvider = providerManager.activeCloudProvider as? CustomOpenAIProvider {
            baseURLText = customProvider.baseURL.absoluteString
        }

        if let provider = providerManager.activeCloudProvider, provider.hasAPIKey {
            Task { await fetchModels(for: provider) }
        }
    }

    private func saveAndValidateAPIKey(provider: any CloudReasoningProvider) {
        guard !apiKeyInput.isEmpty else { return }

        do {
            try provider.setAPIKey(apiKeyInput)
            apiKeyInput = ""
            isEditingKey = false
        } catch {
            saveKeyError = error.localizedDescription
            showSaveKeyError = true
            return
        }

        keyValidation = .validating
        Task { await validateKey(provider: provider) }
    }

    private func removeAPIKey(provider: any CloudReasoningProvider) {
        try? provider.clearAPIKey()
        availableModels = []
        modelFetchError = nil
        keyValidation = .idle
    }

    private func validateKey(provider: any CloudReasoningProvider) async {
        do {
            let models = try await provider.fetchAvailableModels()
            availableModels = models
            modelFetchError = nil
            keyValidation = .verified
        } catch AIProviderError.authenticationFailed {
            keyValidation = .invalid("Invalid Key")
            availableModels = []
        } catch {
            keyValidation = .invalid("Connection failed")
            availableModels = []
        }
    }

    private func fetchModels(for provider: any CloudReasoningProvider) async {
        isFetchingModels = true
        modelFetchError = nil
        do {
            availableModels = try await provider.fetchAvailableModels()
        } catch AIProviderError.authenticationFailed {
            modelFetchError = "Invalid API key"
            availableModels = []
        } catch {
            modelFetchError = "Failed to load models"
            availableModels = []
        }
        isFetchingModels = false
    }

    private func runManualConnectionTest(provider: any CloudReasoningProvider) async {
        keyValidation = .validating
        do {
            _ = try await provider.testConnection()
            let models = try await provider.fetchAvailableModels()
            availableModels = models
            modelFetchError = nil
            keyValidation = .verified
        } catch {
            keyValidation = .invalid(error.localizedDescription)
        }
    }
}

// MARK: - CloudModelPicker

/// Isolated sub-view for the cloud model picker.
/// Avoids Binding(get:set:) by owning @State for the selected ID
/// and using onChange to propagate the selection back to the provider.
private struct CloudModelPicker: View {
    let cloudProvider: any CloudReasoningProvider
    let providerManager: any ProviderManaging
    let availableModels: [AIModel]

    @State private var selectedModelID: String = ""

    var body: some View {
        Picker("Model", selection: $selectedModelID) {
            Text("Select a model").tag("")
            ForEach(availableModels) { model in
                Text(model.name).tag(model.id)
            }
        }
        .onAppear {
            selectedModelID = cloudProvider.selectedModel?.id ?? ""
        }
        .onChange(of: selectedModelID) {
            providerManager.activeCloudProvider?.selectedModel = availableModels.first { $0.id == selectedModelID }
        }
    }
}
