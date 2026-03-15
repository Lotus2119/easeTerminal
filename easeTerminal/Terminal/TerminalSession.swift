//
//  TerminalSession.swift
//  easeTerminal
//
//  Model representing a terminal session for multi-tab support.
//  Each session owns its own SessionContext, making it the single source of truth
//  for all AI context (terminal buffer, troubleshooting history, chat history).
//

import Foundation
import SwiftUI
import SwiftTerm

/// Represents a single terminal session/tab
@MainActor
@Observable
final class TerminalSession: Identifiable {
    let id: UUID
    var title: String
    var icon: String
    let createdAt: Date
    var isActive: Bool
    
    /// Whether this session is displayed in its own pop-out window
    var isPoppedOut: Bool = false
    
    /// Incremented each time the session is re-docked, used to force
    /// SwiftUI to recreate the NSViewRepresentable and call makeNSView.
    var dockGeneration: Int = 0
    
    /// The persistent terminal AppKit view — survives pop-out/dock transitions.
    /// Only the LocalProcessTerminalView is stored (it owns the PTY process).
    /// A fresh PaddedTerminalContainer is created each time for the hosting view.
    private(set) var persistentTerminalView: LocalProcessTerminalView?
    
    /// Store the terminal view so it can be reused across pop-out/dock transitions
    func setPersistentTerminalView(_ view: LocalProcessTerminalView) {
        self.persistentTerminalView = view
    }
    
    /// Context buffer for AI features (legacy, may be removed)
    let contextBuffer = ContextBuffer()
    
    /// Unified session context - the single source of truth for all AI context
    let sessionContext = SessionContext()
    
    /// AI panel state for this session (references sessionContext internally)
    let aiPanelState: AIPanelState
    
    /// Callback to get current terminal buffer content
    var getTerminalContent: (() -> String)?
    
    /// Callback to fill a command into the terminal
    var fillCommand: ((String) -> Void)?
    
    /// Task driving periodic terminal buffer updates
    private nonisolated(unsafe) var bufferUpdateTask: Task<Void, Never>?
    
    /// Track last command that was filled for execution tracking
    private var lastFilledCommand: String?
    
    init(title: String = "Terminal", icon: String = "terminal.fill") {
        self.id = UUID()
        self.title = title
        self.icon = icon
        self.createdAt = Date.now
        self.isActive = true
        
        // Initialize AI panel state
        self.aiPanelState = AIPanelState()
        
        // Bind the panel state to the session context
        self.aiPanelState.bindToSessionContext(sessionContext)
    }
    
    /// Get the current terminal buffer as a string for AI context
    func getTerminalBuffer() -> String {
        // Try the callback first
        if let content = getTerminalContent?() {
            // Also update the session context
            sessionContext.updateTerminalBuffer(content)
            return content
        }
        // Fall back to cached context
        return sessionContext.terminalBufferContent
    }
    
    /// Update terminal buffer and track it in session context
    func updateTerminalBuffer() {
        if let content = getTerminalContent?() {
            sessionContext.updateTerminalBuffer(content)
        }
    }
    
    /// Fill a command into the terminal and track it for execution monitoring
    func fillCommandAndTrack(_ command: String) {
        lastFilledCommand = command
        fillCommand?(command)
    }
    
    /// Record the result of a filled command execution
    /// Call this after the terminal has processed the command
    func recordCommandResult(output: String, succeeded: Bool) {
        if let command = lastFilledCommand {
            sessionContext.recordCommandExecution(
                command: command,
                output: output,
                succeeded: succeeded
            )
            lastFilledCommand = nil
        }
    }
    
    /// Start periodic terminal buffer updates
    func startBufferUpdates(interval: Duration = .seconds(2)) {
        bufferUpdateTask?.cancel()
        bufferUpdateTask = Task { [weak self] in
            while !Task.isCancelled {
                self?.updateTerminalBuffer()
                try? await Task.sleep(for: interval)
            }
        }
    }
    
    /// Stop periodic terminal buffer updates
    func stopBufferUpdates() {
        bufferUpdateTask?.cancel()
        bufferUpdateTask = nil
    }
    
    deinit {
        bufferUpdateTask?.cancel()
    }
}


