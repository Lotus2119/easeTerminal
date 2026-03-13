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
    @Namespace private var panelNamespace
    
    var body: some View {
        VStack(spacing: 0) {
            // Header with glass toolbar
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
        .background(Color(nsColor: .windowBackgroundColor).opacity(0.5))
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
        VStack(spacing: 16) {
            // Title and toolbar
            HStack(spacing: 12) {
                // AI icon with subtle glow
                ZStack {
                    Circle()
                        .fill(Color.accentColor.opacity(0.15))
                        .frame(width: 32, height: 32)
                    
                    Image(systemName: "sparkles")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundStyle(Color.accentColor)
                }
                
                Text("AI Assistant")
                    .font(.headline)
                
                Spacer()
                
                // Toolbar buttons in glass container
                GlassEffectContainer(spacing: 8) {
                    HStack(spacing: 4) {
                        // Session config button
                        Button {
                            showSessionConfig.toggle()
                        } label: {
                            Image(systemName: "slider.horizontal.3")
                                .font(.system(size: 13))
                                .frame(width: 28, height: 28)
                        }
                        .buttonStyle(.borderless)
                        .glassEffect(.regular.interactive(), in: .circle)
                        .help("Session Settings")
                        
                        // Settings button
                        Button {
                            showSettings = true
                        } label: {
                            Image(systemName: "gearshape")
                                .font(.system(size: 13))
                                .frame(width: 28, height: 28)
                        }
                        .buttonStyle(.borderless)
                        .glassEffect(.regular.interactive(), in: .circle)
                        .help("AI Settings")
                        
                        // Clear/Reset button
                        Button {
                            withAnimation(.smooth) {
                                if panelState.currentMode == .chat {
                                    panelState.clearChat()
                                } else {
                                    panelState.resetContext()
                                }
                            }
                        } label: {
                            Image(systemName: "arrow.counterclockwise")
                                .font(.system(size: 13))
                                .frame(width: 28, height: 28)
                        }
                        .buttonStyle(.borderless)
                        .glassEffect(.regular.interactive(), in: .circle)
                        .help(panelState.currentMode == .chat ? "Clear Chat" : "Reset Context")
                    }
                }
            }
            
            // Mode picker with glass effect
            GlassEffectContainer(spacing: 4) {
                HStack(spacing: 4) {
                    ForEach(AIPanelMode.allCases, id: \.self) { mode in
                        Button {
                            withAnimation(.smooth(duration: 0.25)) {
                                panelState.currentMode = mode
                            }
                        } label: {
                            HStack(spacing: 6) {
                                Image(systemName: mode.icon)
                                    .font(.system(size: 12))
                                Text(mode.rawValue)
                                    .font(.subheadline.weight(.medium))
                            }
                            .padding(.horizontal, 14)
                            .padding(.vertical, 8)
                            .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(panelState.currentMode == mode ? .primary : .secondary)
                        .glassEffect(
                            panelState.currentMode == mode 
                                ? .regular.tint(.accentColor)
                                : .regular,
                            in: .capsule
                        )
                        .glassEffectID(mode.rawValue, in: panelNamespace)
                    }
                }
            }
        }
        .padding(16)
        .background(.thinMaterial)
    }
    
    // MARK: - Panel Footer
    
    @ViewBuilder
    private var panelFooter: some View {
        HStack(spacing: 10) {
            // Status indicator with animated glow
            ZStack {
                Circle()
                    .fill(statusColor.opacity(0.3))
                    .frame(width: 12, height: 12)
                
                Circle()
                    .fill(statusColor)
                    .frame(width: 6, height: 6)
            }
            
            // Provider info
            Text(panelState.activeProviderInfo)
                .font(.caption)
                .foregroundStyle(.secondary)
            
            Spacer()
            
            // Mode indicator badge
            HStack(spacing: 5) {
                Image(systemName: ProviderManager.shared.operatingMode == .hybrid ? "cloud.fill" : "desktopcomputer")
                    .font(.system(size: 10))
                Text(ProviderManager.shared.operatingMode == .hybrid ? "Hybrid" : "Local")
                    .font(.caption2.weight(.medium))
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(
                Capsule()
                    .fill(ProviderManager.shared.operatingMode == .hybrid ? Color.blue.opacity(0.15) : Color.green.opacity(0.15))
            )
            .foregroundStyle(ProviderManager.shared.operatingMode == .hybrid ? .blue : .green)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(.thinMaterial)
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
