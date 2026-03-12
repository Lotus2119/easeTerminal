//
//  AIPanelView.swift
//  easeTerminal
//
//  Main AI side panel container.
//  Switches between Chat and Terminal Context modes.
//

import SwiftUI

/// Main AI panel view
struct AIPanelView: View {
    @Bindable var panelState: AIPanelState
    let getTerminalBuffer: () -> String
    let fillCommand: (String) -> Void
    
    @State private var showSettings = false
    @State private var showSessionConfig = false
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            panelHeader
            
            // Mode content
            Group {
                switch panelState.currentMode {
                case .chat:
                    ChatModeView(panelState: panelState)
                case .terminalContext:
                    TerminalContextModeView(
                        panelState: panelState,
                        getTerminalBuffer: getTerminalBuffer,
                        fillCommand: fillCommand
                    )
                }
            }
            .frame(maxHeight: .infinity)
            
            // Footer with provider info
            panelFooter
        }
        .background(.ultraThinMaterial)
        .sheet(isPresented: $showSettings) {
            AISettingsView()
                .frame(minWidth: 500, minHeight: 400)
        }
        .popover(isPresented: $showSessionConfig) {
            SessionConfigPopover(autoFillMode: $panelState.autoFillMode)
        }
    }
    
    // MARK: - Panel Header
    
    @ViewBuilder
    private var panelHeader: some View {
        VStack(spacing: 12) {
            // Title and toolbar
            HStack {
                Text("AI Assistant")
                    .font(.headline)
                
                Spacer()
                
                // Session config button
                Button {
                    showSessionConfig.toggle()
                } label: {
                    Image(systemName: "slider.horizontal.3")
                        .font(.system(size: 12))
                }
                .buttonStyle(.borderless)
                .foregroundStyle(.secondary)
                .help("Session Settings")
                
                // Settings button
                Button {
                    showSettings = true
                } label: {
                    Image(systemName: "gearshape")
                        .font(.system(size: 12))
                }
                .buttonStyle(.borderless)
                .foregroundStyle(.secondary)
                .help("AI Settings")
                
                // Clear/Reset button
                Button {
                    if panelState.currentMode == .chat {
                        panelState.clearChat()
                    } else {
                        panelState.resetContext()
                    }
                } label: {
                    Image(systemName: "trash")
                        .font(.system(size: 12))
                }
                .buttonStyle(.borderless)
                .foregroundStyle(.secondary)
                .help(panelState.currentMode == .chat ? "Clear Chat" : "Reset Context")
            }
            
            // Mode segmented control
            Picker("Mode", selection: $panelState.currentMode.animation(.smooth(duration: 0.2))) {
                ForEach(AIPanelMode.allCases, id: \.self) { mode in
                    Label(mode.rawValue, systemImage: mode.icon)
                        .tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
        }
        .padding(12)
        .background(.regularMaterial)
    }
    
    // MARK: - Panel Footer
    
    @ViewBuilder
    private var panelFooter: some View {
        HStack(spacing: 8) {
            // Status indicator
            Circle()
                .fill(statusColor)
                .frame(width: 6, height: 6)
                .shadow(color: statusColor.opacity(0.5), radius: 2)
            
            // Provider info
            Text(panelState.activeProviderInfo)
                .font(.caption2)
                .foregroundStyle(.secondary)
            
            Spacer()
            
            // Mode indicator
            if ProviderManager.shared.operatingMode == .hybrid {
                HStack(spacing: 4) {
                    Image(systemName: "cloud.fill")
                    Text("Hybrid")
                }
                .font(.caption2)
                .foregroundStyle(.blue)
            } else {
                HStack(spacing: 4) {
                    Image(systemName: "desktopcomputer")
                    Text("Local")
                }
                .font(.caption2)
                .foregroundStyle(.green)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.regularMaterial)
    }
    
    private var statusColor: Color {
        if panelState.canPerformOperations {
            return .green
        } else if panelState.isLoading {
            return .yellow
        } else {
            return .orange
        }
    }
}

// MARK: - Session Config Popover

struct SessionConfigPopover: View {
    @Binding var autoFillMode: AutoFillMode
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Session Settings")
                .font(.headline)
            
            VStack(alignment: .leading, spacing: 12) {
                Text("Auto-Fill Mode")
                    .font(.subheadline.weight(.medium))
                
                Picker("Auto-Fill Mode", selection: $autoFillMode) {
                    ForEach(AutoFillMode.allCases, id: \.self) { mode in
                        VStack(alignment: .leading) {
                            Text(mode.rawValue)
                            Text(mode.description)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .tag(mode)
                    }
                }
                .pickerStyle(.radioGroup)
                .labelsHidden()
            }
            
            HStack {
                Spacer()
                Button("Done") {
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
            }
        }
        .padding()
        .frame(width: 280)
    }
}

// MARK: - AI Panel Toggle Button

/// Toolbar button for toggling the AI panel
struct AIPanelToggleButton: View {
    @Bindable var panelState: AIPanelState
    
    var body: some View {
        Button {
            panelState.togglePanel()
        } label: {
            Image(systemName: panelState.isPanelVisible ? "sidebar.trailing.badge.x" : "sparkle")
        }
        .help(panelState.isPanelVisible ? "Hide AI Panel (⇧⌘A)" : "Show AI Panel (⇧⌘A)")
    }
}

#Preview {
    AIPanelView(
        panelState: AIPanelState(),
        getTerminalBuffer: { "$ npm install\nnpm ERR! code ENOENT" },
        fillCommand: { _ in }
    )
    .frame(width: 350, height: 600)
}
