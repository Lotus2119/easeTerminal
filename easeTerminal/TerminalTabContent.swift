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
    @Environment(\.openWindow) private var openWindow
    
    // Panel width for resizable split
    @State private var panelWidth: CGFloat = 350
    @State private var showCloseConfirmation = false
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
                
                // Pop out into own window
                Button("Pop Out", systemImage: "macwindow.on.rectangle.rtl") {
                    popOutTerminal()
                }
                .help("Pop out into own window (⇧⌘P)")
                
                // New tab button
                Button("New Terminal", systemImage: "plus") {
                    withAnimation(.smooth) {
                        _ = sessionManager.createSession()
                    }
                }
                .help("New Terminal (⌘T)")
                
                // Close tab button
                Button("Close Terminal", systemImage: "xmark") {
                    if session.isActive {
                        showCloseConfirmation = true
                    } else {
                        withAnimation(.smooth) {
                            sessionManager.closeSession(session)
                        }
                    }
                }
                .help("Close Terminal")
                .disabled(sessionManager.sessions.count <= 1)
            }
        }
        .contextMenu {
            Button("Close Tab", role: .destructive) {
                if session.isActive {
                    showCloseConfirmation = true
                } else {
                    withAnimation(.smooth) {
                        sessionManager.closeSession(session)
                    }
                }
            }
            .disabled(sessionManager.sessions.count <= 1)
            
            Divider()
            
            Button("Duplicate Tab") {
                withAnimation(.smooth) {
                    _ = sessionManager.createSession()
                }
            }
            
            Button("Pop Out Window") {
                popOutTerminal()
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
        // Keyboard shortcut for pop-out
        .keyboardShortcut(for: .popOutTerminal) {
            popOutTerminal()
        }
        .confirmationDialog(
            "Close this terminal?",
            isPresented: $showCloseConfirmation,
            titleVisibility: .visible
        ) {
            Button("Close", role: .destructive) {
                withAnimation(.smooth) {
                    sessionManager.closeSession(session)
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Any running processes in this terminal will be terminated.")
        }
    }
    
    private func popOutTerminal() {
        openWindow(id: "popout-terminal", value: session.id)
        Task { @MainActor in
            sessionManager.popOutSession(session)
        }
    }
    
    @ViewBuilder
    private var terminalArea: some View {
        ZStack {
            // Outer background
            Color(nsColor: NSColor(red: 0.10, green: 0.10, blue: 0.12, alpha: 1.0))
                .ignoresSafeArea()
            
            // Terminal with padding and rounded corners.
            // .id(dockGeneration) forces SwiftUI to recreate the NSViewRepresentable
            // after a dock transition so makeNSView re-hosts the persistent terminal view.
            TerminalView(session: session)
                .id(session.dockGeneration)
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

