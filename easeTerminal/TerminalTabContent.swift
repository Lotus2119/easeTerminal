//
//  TerminalTabContent.swift
//  easeTerminal
//
//  Per-tab layout combining the terminal and the AI side panel.
//

import SwiftUI

struct TerminalTabContent: View {
    let session: TerminalSession
    @Bindable var sessionManager: TerminalSessionManager
    
    // Panel width for resizable split
    @State private var panelWidth: CGFloat = 350
    private let minPanelWidth: CGFloat = 280
    private let maxPanelWidth: CGFloat = 500
    
    var body: some View {
        HStack(spacing: 0) {
            // Terminal area
            terminalArea
            
            // AI Panel (when visible)
            if session.aiPanelState.isPanelVisible {
                // Resizable divider
                ResizableDivider(width: $panelWidth, minWidth: minPanelWidth, maxWidth: maxPanelWidth)
                
                // AI Panel with unified session context
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
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                // AI Panel toggle button
                AIPanelToggleButton(panelState: session.aiPanelState)
                
               // Divider()
                
                // New tab button
                Button {
                    withAnimation(.smooth) {
                        _ = sessionManager.createSession()
                    }
                } label: {
                    Image(systemName: "plus")
                }
                .help("New Terminal (⌘T)")
                
                // Close tab button
                Button {
                    withAnimation(.smooth) {
                        sessionManager.closeSession(session)
                    }
                } label: {
                    Image(systemName: "xmark")
                }
                .help("Close Terminal")
                .disabled(sessionManager.sessions.count <= 1)
            }
        }
        .contextMenu {
            Button("Close Tab", role: .destructive) {
                withAnimation(.smooth) {
                    sessionManager.closeSession(session)
                }
            }
            .disabled(sessionManager.sessions.count <= 1)
            
            Divider()
            
            Button("Duplicate Tab") {
                withAnimation(.smooth) {
                    _ = sessionManager.createSession()
                }
            }
            
            Divider()
            
            Button(session.aiPanelState.isPanelVisible ? "Hide AI Panel" : "Show AI Panel") {
                session.aiPanelState.togglePanel()
            }
            .keyboardShortcut("a", modifiers: [.command, .shift])
        }
        // Keyboard shortcut for AI panel toggle
        .keyboardShortcut(for: .toggleAIPanel) {
            session.aiPanelState.togglePanel()
        }
    }
    
    @ViewBuilder
    private var terminalArea: some View {
        ZStack {
            // Outer background
            Color(nsColor: NSColor(red: 0.10, green: 0.10, blue: 0.12, alpha: 1.0))
                .ignoresSafeArea()
            
            // Terminal with padding and rounded corners
            TerminalView(session: session)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .padding(12)
                .background {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(Color(nsColor: NSColor(red: 0.06, green: 0.06, blue: 0.08, alpha: 1.0)))
                        .padding(12)
                }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
