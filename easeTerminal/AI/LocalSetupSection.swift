//
//  LocalSetupSection.swift
//  easeTerminal
//
//  Settings form section for configuring the local inference provider.
//  Supports Ollama, LM Studio, and any other registered LocalInferenceProvider.
//

import SwiftUI

struct LocalSetupSection: View {
    @Environment(\.providerManager) private var providerManager
    @State private var isRefreshing = false
    @State private var selectedModelID: String = ""
    @State private var baseURLText: String = ""
    @State private var showBaseURLField = false

    var body: some View {
        Section {
            // Provider picker
            Picker("Provider", selection: Binding(
                get: { providerManager.selectedLocalProviderID },
                set: { newID in
                    providerManager.setLocalProvider(id: newID)
                    // Reset base URL display to the new provider's default
                    baseURLText = providerManager.localProvider?.baseURL.absoluteString ?? ""
                    Task {
                        isRefreshing = true
                        await providerManager.refreshLocalProvider()
                        selectedModelID = providerManager.localReasoningModel?.id ?? ""
                        isRefreshing = false
                    }
                }
            )) {
                ForEach(providerManager.availableLocalProviders, id: \.id) { entry in
                    Text(entry.name).tag(entry.id)
                }
            }
            .onChange(of: providerManager.selectedLocalProviderID) {
                baseURLText = providerManager.localProvider?.baseURL.absoluteString ?? ""
            }

            // Status row
            HStack {
                statusIndicator

                VStack(alignment: .leading, spacing: 2) {
                    Text(providerManager.selectedLocalProviderID == LMStudioProvider.providerID ? "LM Studio" : "Ollama")
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
                        selectedModelID = providerManager.localReasoningModel?.id ?? ""
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
                .accessibilityLabel("Refresh connection")
            }

            // Base URL (configurable)
            HStack {
                if showBaseURLField {
                    TextField("Base URL", text: $baseURLText)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(.body, design: .monospaced))
                        .onSubmit { saveBaseURL() }

                    Button("Save") { saveBaseURL() }
                        .buttonStyle(.bordered)
                        .controlSize(.small)

                    Button("Cancel") {
                        baseURLText = providerManager.localProvider?.baseURL.absoluteString ?? ""
                        showBaseURLField = false
                    }
                    .buttonStyle(.borderless)
                    .controlSize(.small)
                } else {
                    Text(providerManager.localProvider?.baseURL.absoluteString ?? "")
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)

                    Spacer()

                    Button("Change") { showBaseURLField = true }
                        .buttonStyle(.borderless)
                        .controlSize(.small)
                }
            }

            // Reasoning model picker
            if !providerManager.availableLocalModels.isEmpty {
                Picker("Reasoning Model", selection: $selectedModelID) {
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
                .onAppear {
                    selectedModelID = providerManager.localReasoningModel?.id ?? ""
                    baseURLText = providerManager.localProvider?.baseURL.absoluteString ?? ""
                }
                .onChange(of: selectedModelID) {
                    providerManager.localReasoningModel = providerManager.availableLocalModels.first { $0.id == selectedModelID }
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
                Text(footerEmptyText)
            } else {
                Text(footerReadyText)
            }
        }
        .onAppear {
            baseURLText = providerManager.localProvider?.baseURL.absoluteString ?? ""
        }
    }

    // MARK: - Helpers

    @ViewBuilder
    private var statusIndicator: some View {
        Circle()
            .fill(statusColor)
            .frame(width: 10, height: 10)
    }

    private var statusColor: Color {
        switch providerManager.localStatus {
        case .ready:       .green
        case .connecting:  .yellow
        case .noModels:    .orange
        case .notDetected, .disconnected: .gray
        case .error:       .red
        }
    }

    private var footerEmptyText: String {
        if providerManager.selectedLocalProviderID == LMStudioProvider.providerID {
            return "No models found. Open LM Studio, load a model, then tap Refresh."
        }
        return "No models found. Run 'ollama pull qwen3-coder:30b' to get started."
    }

    private var footerReadyText: String {
        if providerManager.selectedLocalProviderID == LMStudioProvider.providerID {
            return "Select a model loaded in LM Studio. All inference runs locally on your Mac."
        }
        return "Qwen3-Coder 30B is recommended for coding and terminal tasks. It uses MoE with only 3.3B active parameters for fast inference."
    }

    private func saveBaseURL() {
        guard let url = URL(string: baseURLText), url.scheme != nil else { return }
        providerManager.setLocalBaseURL(url)
        showBaseURLField = false
    }
}
