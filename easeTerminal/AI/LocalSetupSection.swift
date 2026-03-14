//
//  LocalSetupSection.swift
//  easeTerminal
//
//  Settings form section for configuring the local Ollama provider.
//

import SwiftUI

struct LocalSetupSection: View {
    @State private var providerManager = ProviderManager.shared
    @State private var isRefreshing = false
    @State private var showModelPicker = false
    @State private var selectedModelID: String = ""
    
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
