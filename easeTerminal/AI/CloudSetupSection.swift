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
                Picker("Model", selection: Binding(
                    get: { cloudProvider.selectedModel?.id ?? "" },
                    set: { id in
                        providerManager.activeCloudProvider?.selectedModel = availableModels.first { $0.id == id }
                    }
                )) {
                    Text("Select a model").tag("")
                    ForEach(availableModels) { model in
                        Text(model.name).tag(model.id)
                    }
                }
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
        apiKeyInput = ""

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
