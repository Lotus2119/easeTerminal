//
//  AIPanelView.swift
//  easeTerminal
//
//  Main AI side panel container.
//  Modern, minimal design with curved elements for macOS 26.
//

import SwiftUI

/// Main AI panel view
struct AIPanelView: View {
    @Bindable var panelState: AIPanelState
    let sessionContext: SessionContext
    let getTerminalBuffer: () -> String
    let fillCommand: (String) -> Void
    
    /// Refresh terminal buffer before AI operations
    private func refreshTerminalContext() {
        let content = getTerminalBuffer()
        sessionContext.updateTerminalBuffer(content)
    }
    
    @State private var showSettings = false
    @State private var showSessionConfig = false
    @State private var showContextInspector = false
    @State private var showClearConfirmation = false
    @State private var providerManager = ProviderManager.shared
    @Namespace private var modeNamespace
    
    var body: some View {
        VStack(spacing: 0) {
            // Minimal header
            panelHeader
            
            // Content area
            ZStack {
                ChatModeView(panelState: panelState, refreshContext: refreshTerminalContext)
                    .opacity(panelState.currentMode == .chat ? 1 : 0)
                    .allowsHitTesting(panelState.currentMode == .chat)

                TerminalContextModeView(
                    panelState: panelState,
                    sessionContext: sessionContext,
                    getTerminalBuffer: getTerminalBuffer,
                    fillCommand: fillCommand
                )
                .opacity(panelState.currentMode == .terminalContext ? 1 : 0)
                .allowsHitTesting(panelState.currentMode == .terminalContext)
            }
            .frame(maxHeight: .infinity)
            
            // Minimal footer
            panelFooter
        }
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .sheet(isPresented: $showSettings) {
            AISettingsView()
                .frame(minWidth: 500, minHeight: 400)
        }
        .popover(isPresented: $showSessionConfig) {
            SessionConfigPopover(autoFillMode: $panelState.autoFillMode)
        }
        .popover(isPresented: $showContextInspector) {
            ContextInspectorPopover(
                sessionContext: sessionContext,
                onClearAll: {
                    showClearConfirmation = true
                }
            )
        }
        .alert("Clear All Context?", isPresented: $showClearConfirmation) {
            Button("Cancel", role: .cancel) { }
            Button("Clear All", role: .destructive) {
                withAnimation(.smooth) {
                    panelState.clearAllSessionContext()
                }
            }
        } message: {
            Text("This will clear the terminal buffer, troubleshooting history, and chat history for this session.")
        }
    }
    
    // MARK: - Panel Header
    
    @ViewBuilder
    private var panelHeader: some View {
        VStack(spacing: 12) {
            // Top bar with title and actions
            HStack {
                // Mode picker - pill style
                HStack(spacing: 2) {
                    ForEach(AIPanelMode.allCases, id: \.self) { mode in
                        Button {
                            withAnimation(.smooth(duration: 0.3)) {
                                panelState.currentMode = mode
                            }
                        } label: {
                            HStack(spacing: 6) {
                                Image(systemName: mode.icon)
                                    .font(.system(size: 11, weight: .medium))
                                Text(mode.rawValue)
                                    .font(.subheadline.weight(.medium))
                            }
                            .padding(.horizontal, 14)
                            .padding(.vertical, 8)
                            .background {
                                if panelState.currentMode == mode {
                                    Capsule()
                                        .fill(.white.opacity(0.15))
                                        .matchedGeometryEffect(id: "modeBackground", in: modeNamespace)
                                }
                            }
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(panelState.currentMode == mode ? .primary : .secondary)
                    }
                }
                .padding(4)
                .background(Capsule().fill(.ultraThinMaterial))
                
                Spacer()
                
                // Action buttons
                HStack(spacing: 4) {
                    Button("Session Settings", systemImage: "slider.horizontal.3") {
                        showSessionConfig.toggle()
                    }
                    .labelStyle(.iconOnly)
                    .buttonStyle(.plain)
                    .frame(width: 32, height: 32)
                    .background(Circle().fill(.ultraThinMaterial))
                    
                    Button("AI Settings", systemImage: "gearshape") {
                        showSettings = true
                    }
                    .labelStyle(.iconOnly)
                    .buttonStyle(.plain)
                    .frame(width: 32, height: 32)
                    .background(Circle().fill(.ultraThinMaterial))
                }
                .foregroundStyle(.secondary)
                .font(.system(size: 13))
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 16)
        .padding(.bottom, 12)
    }
    
    // MARK: - Panel Footer
    
    @ViewBuilder
    private var panelFooter: some View {
        HStack(spacing: 12) {
            // Status indicator
            HStack(spacing: 8) {
                Circle()
                    .fill(statusColor)
                    .frame(width: 8, height: 8)
                
                Text(providerManager.statusText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            
            Spacer()
            
            // Mode badge
            Text(providerManager.operatingMode == .hybrid ? "Cloud" : "Local")
                .font(.caption2.weight(.medium))
                .foregroundStyle(providerManager.operatingMode == .hybrid ? .blue : .green)
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(
                    Capsule()
                        .fill(providerManager.operatingMode == .hybrid ? Color.blue.opacity(0.12) : Color.green.opacity(0.12))
                )
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(.ultraThinMaterial)
    }
    
    private var statusColor: Color {
        if panelState.isLoading {
            return .yellow
        } else {
            return providerManager.statusColor
        }
    }
}

#Preview {
    AIPanelView(
        panelState: AIPanelState(),
        sessionContext: SessionContext(),
        getTerminalBuffer: { "$ npm install\nnpm ERR! code ENOENT" },
        fillCommand: { _ in }
    )
    .frame(width: 380, height: 600)
    .padding()
}
