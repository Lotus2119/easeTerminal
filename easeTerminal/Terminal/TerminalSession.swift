//
//  TerminalSession.swift
//  easeTerminal
//
//  Model representing a terminal session for multi-tab support.
//

import Foundation
import SwiftUI

/// Represents a single terminal session/tab
@Observable
final class TerminalSession: Identifiable {
    let id: UUID
    var title: String
    var icon: String
    let createdAt: Date
    var isActive: Bool
    
    init(title: String = "Terminal", icon: String = "terminal.fill") {
        self.id = UUID()
        self.title = title
        self.icon = icon
        self.createdAt = Date()
        self.isActive = true
    }
}

/// Manages all terminal sessions
@Observable
final class TerminalSessionManager {
    var sessions: [TerminalSession] = []
    var selectedSessionID: UUID?
    
    var selectedSession: TerminalSession? {
        sessions.first { $0.id == selectedSessionID }
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
        
        // Select another session if we closed the selected one
        if selectedSessionID == session.id {
            selectedSessionID = sessions.first?.id
        }
    }
    
    func closeSession(id: UUID) {
        if let session = sessions.first(where: { $0.id == id }) {
            closeSession(session)
        }
    }
}
