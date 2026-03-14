//
//  ContentView.swift
//  easeTerminal
//
//  Created by Louis Kolodzinski on 12/03/2026.
//

import SwiftUI

struct ContentView: View {
    @Bindable var sessionManager: TerminalSessionManager
    
    var body: some View {
        TabView(selection: $sessionManager.selectedSessionID) {
            // Dynamic tabs for each terminal session
            ForEach(sessionManager.sessions) { session in
                Tab(value: session.id) {
                    TerminalTabContent(session: session, sessionManager: sessionManager)
                } label: {
                    Label {
                        Text(session.title)
                    } icon: {
                        HStack(spacing: 6) {
                            Circle()
                                .fill(session.isActive ? Color.green : Color.gray.opacity(0.4))
                                .frame(width: 8, height: 8)
                            Image(systemName: session.icon)
                        }
                    }
                }
            }
        }
        .tabViewStyle(.sidebarAdaptable)
        .tabViewSidebarHeader {
            // App branding header
            HStack(spacing: 8) {
                Image(systemName: "terminal.fill")
                    .font(.title3)
                    .foregroundStyle(.primary)
                Text("easeTerminal")
                    .font(.headline)
            }
            .padding(.vertical, 8)
        }
        .tabViewSidebarBottomBar {
            SidebarFooterView(sessionManager: sessionManager)
        }
    }
}

// MARK: - Terminal Tab Content (keeps terminal alive per tab)

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

// MARK: - Resizable Divider

struct ResizableDivider: View {
    @Binding var width: CGFloat
    let minWidth: CGFloat
    let maxWidth: CGFloat
    
    @State private var isDragging = false
    
    var body: some View {
        Rectangle()
            .fill(Color.gray.opacity(isDragging ? 0.3 : 0.1))
            .frame(width: 6)
            .contentShape(Rectangle())
            .onHover { hovering in
                if hovering {
                    NSCursor.resizeLeftRight.push()
                } else {
                    NSCursor.pop()
                }
            }
            .gesture(
                DragGesture(minimumDistance: 1)
                    .onChanged { value in
                        isDragging = true
                        // Dragging left increases panel width, right decreases
                        let newWidth = width - value.translation.width
                        width = min(max(newWidth, minWidth), maxWidth)
                    }
                    .onEnded { _ in
                        isDragging = false
                    }
            )
    }
}

// MARK: - Keyboard Shortcut Extension

enum AppKeyboardShortcut {
    case toggleAIPanel
    
    var key: KeyEquivalent {
        switch self {
        case .toggleAIPanel: return "a"
        }
    }
    
    var modifiers: EventModifiers {
        switch self {
        case .toggleAIPanel: return [.command, .shift]
        }
    }
}

extension View {
    func keyboardShortcut(for shortcut: AppKeyboardShortcut, action: @escaping () -> Void) -> some View {
        self.background(
            Button("") { action() }
                .keyboardShortcut(shortcut.key, modifiers: shortcut.modifiers)
                .opacity(0)
        )
    }
}

// MARK: - Sidebar Footer

struct SidebarFooterView: View {
    @Bindable var sessionManager: TerminalSessionManager
    @State private var showingSettings = false
    
    private var providerManager: ProviderManager { ProviderManager.shared }
    
    // Use the provider manager's computed status color
    private var statusColor: Color {
        providerManager.statusColor
    }
    
    // Use the provider manager's computed status text
    private var statusText: String {
        providerManager.statusText
    }
    
    var body: some View {
        VStack(spacing: 12) {
            // AI Status indicator
            HStack(spacing: 10) {
                Circle()
                    .fill(statusColor)
                    .frame(width: 8, height: 8)
                    .overlay(
                        Circle()
                            .stroke(statusColor.opacity(0.3), lineWidth: 2)
                            .scaleEffect(1.5)
                    )
                
                VStack(alignment: .leading, spacing: 2) {
                    Text("AI Assistant")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.primary)
                    Text(statusText)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                
                Spacer()
                
                Button {
                    showingSettings = true
                } label: {
                    Image(systemName: "gearshape")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 10))
            
            // New terminal button
            Button {
                withAnimation(.smooth) {
                    _ = sessionManager.createSession()
                }
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "plus")
                        .font(.system(size: 12, weight: .semibold))
                    Text("New Terminal")
                        .font(.subheadline.weight(.medium))
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
            }
            .buttonStyle(.glass)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 12)
        .sheet(isPresented: $showingSettings) {
            AISettingsView()
                .frame(minWidth: 500, minHeight: 400)
        }
    }
}

// MARK: - Empty State

struct EmptyTerminalView: View {
    @Bindable var sessionManager: TerminalSessionManager
    
    var body: some View {
        VStack(spacing: 24) {
            ZStack {
                Circle()
                    .fill(.ultraThinMaterial)
                    .frame(width: 100, height: 100)
                
                Image(systemName: "terminal")
                    .font(.system(size: 40, weight: .light))
                    .foregroundStyle(.secondary)
            }
            
            VStack(spacing: 8) {
                Text("No Terminal Open")
                    .font(.title2.weight(.medium))
                    .foregroundStyle(.primary)
                
                Text("Create a new terminal to get started")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            
            Button {
                withAnimation(.smooth) {
                    _ = sessionManager.createSession()
                }
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "plus")
                    Text("Create Terminal")
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 10)
            }
            .buttonStyle(.glassProminent)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(nsColor: NSColor(red: 0.06, green: 0.06, blue: 0.08, alpha: 1.0)))
    }
}

#Preview {
    ContentView(sessionManager: TerminalSessionManager())
}
