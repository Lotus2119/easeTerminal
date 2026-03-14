//
//  ContextSettingsSection.swift
//  easeTerminal
//
//  Settings form section for tuning the AI context window size.
//

import SwiftUI

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
