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
    
    private var isLocalMode: Bool { providerManager.operatingMode == .local }
    
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
                
                // Cloud Setup Section (Optional — disabled in local mode)
                CloudSetupSection()
                    .disabled(isLocalMode)
                
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

#Preview {
    AISettingsView()
        .frame(width: 500, height: 600)
}
