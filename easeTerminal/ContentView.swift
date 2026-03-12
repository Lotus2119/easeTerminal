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
    
    var body: some View {
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
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                // New tab button
                Button {
                    withAnimation(.smooth) {
                        _ = sessionManager.createSession()
                    }
                } label: {
                    Image(systemName: "plus")
                }
                .help("New Terminal (Cmd+T)")
                
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
        }
    }
}

// MARK: - Sidebar Footer

struct SidebarFooterView: View {
    @Bindable var sessionManager: TerminalSessionManager
    
    var body: some View {
        VStack(spacing: 12) {
            // AI Status indicator
            HStack(spacing: 10) {
                Circle()
                    .fill(Color.orange)
                    .frame(width: 8, height: 8)
                    .overlay(
                        Circle()
                            .stroke(Color.orange.opacity(0.3), lineWidth: 2)
                            .scaleEffect(1.5)
                    )
                
                VStack(alignment: .leading, spacing: 2) {
                    Text("AI Assistant")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.primary)
                    Text("Not Connected")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                
                Spacer()
                
                Button {
                    // Future: Open AI settings
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
