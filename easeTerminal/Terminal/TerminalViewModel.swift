//
//  TerminalViewModel.swift
//  easeTerminal
//
//  ViewModel bridging PTYProcess to SwiftUI.
//  Handles terminal state, ANSI parsing, and keyboard input.
//

import Foundation
import SwiftUI
import Observation

/// Observable view model for terminal UI.
/// Uses @Observable macro (Swift 5.9+) for modern SwiftUI integration.
@MainActor
@Observable
final class TerminalViewModel {
    
    // MARK: - Observable Properties
    
    /// Lines of terminal output for display
    private(set) var lines: [TerminalLine] = []
    
    /// Current line being composed (before newline)
    private(set) var currentLine: AttributedString = AttributedString()
    
    /// Whether the terminal process is running
    private(set) var isRunning = false
    
    /// Terminal size in characters
    var columns: Int = 80 {
        didSet { updatePTYSize() }
    }
    var rows: Int = 24 {
        didSet { updatePTYSize() }
    }
    
    // MARK: - Private Properties
    
    private var ptyProcess: PTYProcess?
    private var ansiParser: ANSIParser
    
    /// Maximum number of lines to retain in scrollback
    private let maxScrollbackLines = 10000
    
    // MARK: - Public Access for AI Layer
    
    /// Provides read access to the context buffer for AI integration.
    /// The local model layer will read from this to package context for Claude.
    var contextBuffer: ContextBuffer? {
        ptyProcess?.contextBuffer
    }
    
    // MARK: - Initialization
    
    init() {
        self.ansiParser = ANSIParser()
    }
    
    // MARK: - Terminal Lifecycle
    
    /// Starts a new shell session.
    func start() {
        guard !isRunning else { return }
        
        let process = PTYProcess()
        self.ptyProcess = process
        
        // Handle output from PTY
        process.onOutput = { [weak self] data in
            Task { @MainActor in
                self?.handleOutput(data)
            }
        }
        
        // Handle process termination
        process.onTermination = { [weak self] exitCode in
            Task { @MainActor in
                self?.handleTermination(exitCode)
            }
        }
        
        do {
            try process.start()
            isRunning = true
            process.resize(columns: UInt16(columns), rows: UInt16(rows))
        } catch {
            appendSystemMessage("Failed to start shell: \(error.localizedDescription)")
        }
    }
    
    /// Stops the current shell session.
    func stop() {
        ptyProcess?.terminate()
        ptyProcess = nil
        isRunning = false
    }
    
    /// Restarts the shell session.
    func restart() {
        stop()
        lines.removeAll()
        currentLine = AttributedString()
        start()
    }
    
    // MARK: - Input Handling
    
    /// Sends a character to the PTY.
    func sendCharacter(_ char: Character) {
        guard let data = String(char).data(using: .utf8) else { return }
        ptyProcess?.write(data)
    }
    
    /// Sends a string to the PTY.
    func sendString(_ string: String) {
        ptyProcess?.write(string)
    }
    
    /// Sends raw data to the PTY.
    func sendData(_ data: Data) {
        ptyProcess?.write(data)
    }
    
    /// Handles a key event from the UI.
    func handleKeyEvent(_ event: NSEvent) -> Bool {
        guard isRunning else { return false }
        
        // Convert key event to appropriate escape sequence
        if let data = keyEventToData(event) {
            ptyProcess?.write(data)
            return true
        }
        
        return false
    }
    
    /// Sends Ctrl+C (interrupt) signal.
    func sendInterrupt() {
        ptyProcess?.write(Data([0x03])) // ETX
    }
    
    /// Sends Ctrl+D (EOF).
    func sendEOF() {
        ptyProcess?.write(Data([0x04])) // EOT
    }
    
    /// Sends Ctrl+Z (suspend).
    func sendSuspend() {
        ptyProcess?.write(Data([0x1A])) // SUB
    }
    
    // MARK: - Private Methods
    
    private func handleOutput(_ data: Data) {
        guard let string = String(data: data, encoding: .utf8) else { return }
        
        // Split on newlines first, then parse each segment
        let segments = string.components(separatedBy: "\n")
        
        for (index, segment) in segments.enumerated() {
            // Parse ANSI sequences for this segment
            let parsed = ansiParser.parse(segment)
            
            if index == 0 {
                // Append to current line
                currentLine.append(parsed)
            } else {
                // Commit current line and start new one
                commitCurrentLine()
                currentLine = parsed
            }
        }
        
        trimScrollbackIfNeeded()
    }
    
    private func commitCurrentLine() {
        let line = TerminalLine(content: currentLine)
        lines.append(line)
        currentLine = AttributedString()
    }
    
    private func trimScrollbackIfNeeded() {
        if lines.count > maxScrollbackLines {
            lines.removeFirst(lines.count - maxScrollbackLines)
        }
    }
    
    private func handleTermination(_ exitCode: Int32) {
        isRunning = false
        appendSystemMessage("Shell exited with code \(exitCode)")
    }
    
    private func appendSystemMessage(_ message: String) {
        var styled = AttributedString(message)
        styled.foregroundColor = .secondary
        commitCurrentLine()
        currentLine = styled
        commitCurrentLine()
    }
    
    private func updatePTYSize() {
        ptyProcess?.resize(columns: UInt16(columns), rows: UInt16(rows))
    }
    
    /// Converts a key event to the appropriate byte sequence for the PTY.
    private func keyEventToData(_ event: NSEvent) -> Data? {
        let modifiers = event.modifierFlags
        
        // Handle special keys
        switch event.keyCode {
        case 36: // Return
            return Data([0x0D])
        case 48: // Tab
            return Data([0x09])
        case 51: // Delete/Backspace
            return Data([0x7F])
        case 53: // Escape
            return Data([0x1B])
        case 123: // Left arrow
            return Data([0x1B, 0x5B, 0x44])
        case 124: // Right arrow
            return Data([0x1B, 0x5B, 0x43])
        case 125: // Down arrow
            return Data([0x1B, 0x5B, 0x42])
        case 126: // Up arrow
            return Data([0x1B, 0x5B, 0x41])
        case 115: // Home
            return Data([0x1B, 0x5B, 0x48])
        case 119: // End
            return Data([0x1B, 0x5B, 0x46])
        case 116: // Page Up
            return Data([0x1B, 0x5B, 0x35, 0x7E])
        case 121: // Page Down
            return Data([0x1B, 0x5B, 0x36, 0x7E])
        default:
            break
        }
        
        // Handle Ctrl+key combinations
        if modifiers.contains(.control), let chars = event.charactersIgnoringModifiers {
            if let char = chars.first {
                let ascii = char.asciiValue ?? 0
                // Ctrl+A through Ctrl+Z map to 0x01-0x1A
                if ascii >= 97 && ascii <= 122 { // a-z
                    return Data([UInt8(ascii - 96)])
                }
            }
        }
        
        // Regular character input
        if let chars = event.characters, !chars.isEmpty {
            return chars.data(using: .utf8)
        }
        
        return nil
    }
}


