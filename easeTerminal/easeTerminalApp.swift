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
    
    var body: some Scene {
        WindowGroup {
            ContentView(sessionManager: sessionManager)
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
    }
}
