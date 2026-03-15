//
//  TerminalSessionManager.swift
//  easeTerminal
//
//  Manages all open terminal sessions for multi-tab support.
//

import Foundation

/// Manages all terminal sessions
@MainActor
@Observable
final class TerminalSessionManager {
    var sessions: [TerminalSession] = []
    var selectedSessionID: UUID?
    
    var selectedSession: TerminalSession? {
        sessions.first { $0.id == selectedSessionID }
    }
    
    /// Sessions shown in the main window's sidebar (not popped out)
    var dockedSessions: [TerminalSession] {
        sessions.filter { !$0.isPoppedOut }
    }
    
    init() {
        // Create initial session
        let initial = TerminalSession(title: "Terminal 1")
        sessions.append(initial)
        selectedSessionID = initial.id
    }
    
    func createSession() -> TerminalSession {
        let number = sessions.count + 1
        let session = TerminalSession(title: "Terminal \(number)")
        sessions.append(session)
        selectedSessionID = session.id
        return session
    }
    
    func closeSession(_ session: TerminalSession) {
        sessions.removeAll { $0.id == session.id }
        
        // Select another docked session if we closed the selected one
        if selectedSessionID == session.id {
            selectedSessionID = dockedSessions.first?.id
        }
    }
    
    func closeSession(id: UUID) {
        if let session = sessions.first(where: { $0.id == id }) {
            closeSession(session)
        }
    }
    
    /// Pop a session out into its own window
    func popOutSession(_ session: TerminalSession) {
        session.isPoppedOut = true
        // Select the next docked session in the main window
        if selectedSessionID == session.id {
            selectedSessionID = dockedSessions.first?.id
        }
    }
    
    /// Dock a popped-out session back into the main window
    func dockSession(_ session: TerminalSession) {
        session.dockGeneration += 1
        session.isPoppedOut = false
        selectedSessionID = session.id
    }
}
