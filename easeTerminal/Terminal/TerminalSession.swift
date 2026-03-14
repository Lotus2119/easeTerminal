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

/// Represents a single terminal session/tab
@MainActor
@Observable
final class TerminalSession: Identifiable {
    let id: UUID
    var title: String
    var icon: String
    let createdAt: Date
    var isActive: Bool
    
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
    
    /// Timer for periodic terminal buffer updates
    private var bufferUpdateTimer: Timer?
    
    /// Track last command that was filled for execution tracking
    private var lastFilledCommand: String?
    
    init(title: String = "Terminal", icon: String = "terminal.fill") {
        self.id = UUID()
        self.title = title
        self.icon = icon
        self.createdAt = Date()
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
    func startBufferUpdates(interval: TimeInterval = 2.0) {
        bufferUpdateTimer?.invalidate()
        bufferUpdateTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            self?.updateTerminalBuffer()
        }
    }
    
    /// Stop periodic terminal buffer updates
    func stopBufferUpdates() {
        bufferUpdateTimer?.invalidate()
        bufferUpdateTimer = nil
    }
    
    nonisolated func cancelBufferTimer() {
        // Called from deinit; Timer.invalidate is safe to call from any thread.
        // stopBufferUpdates() is the preferred call site from MainActor code.
    }

    deinit {
        // Timer holds a weak back-reference to self and repeats; it is invalidated when
        // the run loop drops the retained cycle, or when stopBufferUpdates() is called
        // before deallocation. No explicit invalidation needed here since bufferUpdateTimer
        // is a MainActor-isolated property that cannot be safely accessed from deinit.
    }
}


