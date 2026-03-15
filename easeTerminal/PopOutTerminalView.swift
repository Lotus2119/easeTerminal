//
//  PopOutTerminalView.swift
//  easeTerminal
//
//  Standalone view for a terminal session popped out into its own window.
//  Shows the terminal and AI panel but no sidebar or session list.
//

import SwiftUI

struct PopOutTerminalView: View {
    let session: TerminalSession
    @Bindable var sessionManager: TerminalSessionManager
    @Environment(\.dismissWindow) private var dismissWindow
    
    @State private var panelWidth: CGFloat = 350
    @State private var showCloseConfirmation = false
    @State private var explicitToolbarAction = false
    private let minPanelWidth: CGFloat = 280
    private let maxPanelWidth: CGFloat = 500
    
    var body: some View {
        HStack(spacing: 0) {
            // Terminal area
            terminalArea
            
            // AI Panel (when visible)
            if session.aiPanelState.isPanelVisible {
                ResizableDivider(width: $panelWidth, minWidth: minPanelWidth, maxWidth: maxPanelWidth)
                
                AIPanelView(
                    panelState: session.aiPanelState,
                    sessionContext: session.sessionContext,
                    getTerminalBuffer: { session.getTerminalBuffer() },
                    fillCommand: { command in
                        session.fillCommandAndTrack(command)
                    }
                )
                .frame(width: panelWidth)
                .transition(.move(edge: .trailing).combined(with: .opacity))
            }
        }
        .animation(.spring(response: 0.3, dampingFraction: 0.8), value: session.aiPanelState.isPanelVisible)
        .onAppear {
            explicitToolbarAction = false
        }
        .onDisappear {
            // Auto-dock if the window was closed implicitly (red button / Cmd+W)
            if session.isPoppedOut && !explicitToolbarAction {
                Task { @MainActor in
                    sessionManager.dockSession(session)
                }
            }
        }
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                // AI Panel toggle
                AIPanelToggleButton(panelState: session.aiPanelState)
                
                // Dock back into main window
                Button("Dock", systemImage: "rectangle.grid.1x2") {
                    explicitToolbarAction = true
                    dismissWindow(id: "popout-terminal", value: session.id)
                    Task { @MainActor in
                        sessionManager.dockSession(session)
                    }
                }
                .help("Dock back into main window")
                
                // Close terminal
                Button("Close", systemImage: "xmark") {
                    if session.isActive {
                        showCloseConfirmation = true
                    } else {
                        explicitToolbarAction = true
                        dismissWindow(id: "popout-terminal", value: session.id)
                        withAnimation(.smooth) {
                            sessionManager.closeSession(session)
                        }
                    }
                }
                .help("Close Terminal")
            }
        }
        .keyboardShortcut(for: .toggleAIPanel) {
            session.aiPanelState.togglePanel()
        }
        .confirmationDialog(
            "Close this terminal?",
            isPresented: $showCloseConfirmation,
            titleVisibility: .visible
        ) {
            Button("Close", role: .destructive) {
                explicitToolbarAction = true
                dismissWindow(id: "popout-terminal", value: session.id)
                withAnimation(.smooth) {
                    sessionManager.closeSession(session)
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Any running processes in this terminal will be terminated.")
        }
    }
    
    private var terminalArea: some View {
        ZStack {
            Color(nsColor: NSColor(red: 0.10, green: 0.10, blue: 0.12, alpha: 1.0))
                .ignoresSafeArea()
            
            TerminalView(session: session)
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .padding(12)
                .background {
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color(nsColor: NSColor(red: 0.06, green: 0.06, blue: 0.08, alpha: 1.0)))
                        .padding(12)
                }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
