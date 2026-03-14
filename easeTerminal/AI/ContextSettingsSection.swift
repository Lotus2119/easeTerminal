//
//  ContextSettingsSection.swift
//  easeTerminal
//
//  Settings form section for tuning the AI context window size.
//

import SwiftUI

struct ContextSettingsSection: View {
    @State private var settings = ContextSettings.loadFromDefaults()

    // Double mirrors for Slider bindings — avoids Binding(get:set:) int/double conversions
    @State private var terminalLines: Double = Double(ContextSettings.default.maxTerminalLines)
    @State private var chatExchanges: Double = Double(ContextSettings.default.maxChatExchanges)
    @State private var troubleshootEntries: Double = Double(ContextSettings.default.maxFullTroubleshootEntries)
    @State private var totalContextChars: Double = Double(ContextSettings.default.maxTotalContextChars)

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
                Slider(value: $terminalLines, in: 50...500, step: 50)
                    .onChange(of: terminalLines) {
                        settings.maxTerminalLines = Int(terminalLines)
                    }
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
                Slider(value: $chatExchanges, in: 2...20, step: 1)
                    .onChange(of: chatExchanges) {
                        settings.maxChatExchanges = Int(chatExchanges)
                    }
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
                Slider(value: $troubleshootEntries, in: 1...5, step: 1)
                    .onChange(of: troubleshootEntries) {
                        settings.maxFullTroubleshootEntries = Int(troubleshootEntries)
                    }
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
                Slider(value: $totalContextChars, in: 8000...64000, step: 4000)
                    .onChange(of: totalContextChars) {
                        settings.maxTotalContextChars = Int(totalContextChars)
                    }
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
                    terminalLines = Double(settings.maxTerminalLines)
                    chatExchanges = Double(settings.maxChatExchanges)
                    troubleshootEntries = Double(settings.maxFullTroubleshootEntries)
                    totalContextChars = Double(settings.maxTotalContextChars)
                }
                .buttonStyle(.borderless)
                .foregroundStyle(.secondary)
            }
            
        } header: {
            Text("Context Window")
        } footer: {
            Text("These settings control how much context is included in AI requests. Larger context windows provide more information but may be slower and use more tokens.")
        }
        .onAppear {
            terminalLines = Double(settings.maxTerminalLines)
            chatExchanges = Double(settings.maxChatExchanges)
            troubleshootEntries = Double(settings.maxFullTroubleshootEntries)
            totalContextChars = Double(settings.maxTotalContextChars)
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
