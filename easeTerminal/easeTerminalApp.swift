//
//  easeTerminalApp.swift
//  easeTerminal
//
//  Created by Louis Kolodzinski on 12/03/2026.
//

import SwiftUI

@main
struct easeTerminalApp: App {
    @State private var sessionManager = TerminalSessionManager()
    @State private var providerManager = ProviderManager.shared

    var body: some Scene {
        // Main window with sidebar tabs
        WindowGroup {
            ContentView(sessionManager: sessionManager)
                .environment(\.providerManager, providerManager)
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 1100, height: 700)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("New Terminal Tab") {
                    _ = sessionManager.createSession()
                }
                .keyboardShortcut("t", modifiers: .command)
            }
        }

        // Pop-out terminal windows
        WindowGroup("Terminal", id: "popout-terminal", for: UUID.self) { $sessionID in
            if let sessionID,
               let session = sessionManager.sessions.first(where: { $0.id == sessionID }) {
                PopOutTerminalView(session: session, sessionManager: sessionManager)
                    .environment(\.providerManager, providerManager)
            }
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 800, height: 600)

        Settings {
            AISettingsView(showsDoneButton: false)
        }
    }
}
