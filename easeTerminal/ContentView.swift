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
            // Iterate over ALL sessions to keep ForEach identity stable.
            // Popped-out sessions are hidden from the sidebar but their
            // Tab stays in the graph so SwiftUI doesn't tear down siblings.
            ForEach(sessionManager.sessions) { session in
                if !session.isPoppedOut {
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

#Preview {
    ContentView(sessionManager: TerminalSessionManager())
}
