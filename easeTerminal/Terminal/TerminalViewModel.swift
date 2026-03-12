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

/// Represents a line of terminal output with optional styling.
struct TerminalLine: Identifiable {
    let id = UUID()
    var content: AttributedString
}

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

// MARK: - ANSI Parser

/// Parses ANSI escape sequences and converts them to AttributedString styling.
/// This is a minimal implementation - extend as needed for full terminal emulation.
struct ANSIParser {
    
    // Current text attributes
    private var foregroundColor: Color = .primary
    private var backgroundColor: Color = .clear
    private var isBold = false
    private var isItalic = false
    private var isUnderline = false
    
    /// Parses a string containing ANSI escape sequences.
    mutating func parse(_ input: String) -> AttributedString {
        var result = AttributedString()
        var currentText = ""
        var index = input.startIndex
        
        while index < input.endIndex {
            let char = input[index]
            
            if char == "\u{1B}" { // ESC
                // Flush current text
                if !currentText.isEmpty {
                    result.append(styledString(currentText))
                    currentText = ""
                }
                
                // Parse escape sequence
                index = parseEscapeSequence(input, from: index)
            } else if char == "\r" {
                // Carriage return - simplified handling
                // Full implementation would move cursor to beginning of line
                index = input.index(after: index)
            } else {
                currentText.append(char)
                index = input.index(after: index)
            }
        }
        
        // Flush remaining text
        if !currentText.isEmpty {
            result.append(styledString(currentText))
        }
        
        return result
    }
    
    private func styledString(_ text: String) -> AttributedString {
        var styled = AttributedString(text)
        styled.foregroundColor = foregroundColor
        
        if isBold {
            styled.font = .system(.body).bold()
        }
        if isItalic {
            styled.font = .system(.body).italic()
        }
        if isUnderline {
            styled.underlineStyle = .single
        }
        
        return styled
    }
    
    private mutating func parseEscapeSequence(_ input: String, from start: String.Index) -> String.Index {
        var index = input.index(after: start) // Skip ESC
        
        guard index < input.endIndex else { return index }
        
        let next = input[index]
        
        if next == "[" {
            // CSI sequence
            index = input.index(after: index)
            var params = ""
            
            while index < input.endIndex {
                let c = input[index]
                if c.isLetter {
                    // End of sequence
                    if c == "m" {
                        applySGRParams(params)
                    }
                    return input.index(after: index)
                }
                params.append(c)
                index = input.index(after: index)
            }
        }
        
        return index
    }
    
    private mutating func applySGRParams(_ params: String) {
        let codes = params.split(separator: ";").compactMap { Int($0) }
        
        if codes.isEmpty {
            resetAttributes()
            return
        }
        
        var i = 0
        while i < codes.count {
            let code = codes[i]
            
            switch code {
            case 0:
                resetAttributes()
            case 1:
                isBold = true
            case 3:
                isItalic = true
            case 4:
                isUnderline = true
            case 22:
                isBold = false
            case 23:
                isItalic = false
            case 24:
                isUnderline = false
            case 30...37:
                foregroundColor = ansiColor(code - 30)
            case 38:
                // Extended foreground color
                if i + 2 < codes.count && codes[i + 1] == 5 {
                    foregroundColor = xterm256Color(codes[i + 2])
                    i += 2
                }
            case 39:
                foregroundColor = .primary
            case 40...47:
                backgroundColor = ansiColor(code - 40)
            case 49:
                backgroundColor = .clear
            case 90...97:
                foregroundColor = ansiColor(code - 90, bright: true)
            default:
                break
            }
            
            i += 1
        }
    }
    
    private mutating func resetAttributes() {
        foregroundColor = .primary
        backgroundColor = .clear
        isBold = false
        isItalic = false
        isUnderline = false
    }
    
    private func ansiColor(_ code: Int, bright: Bool = false) -> Color {
        let colors: [Color] = bright
            ? [.gray, .red, .green, .yellow, .blue, .purple, .cyan, .white]
            : [.black, .red, .green, .yellow, .blue, .purple, .cyan, .white]
        
        return code < colors.count ? colors[code] : .primary
    }
    
    private func xterm256Color(_ code: Int) -> Color {
        // Simplified - just map to basic colors for now
        // Full implementation would handle all 256 colors
        if code < 8 {
            return ansiColor(code)
        } else if code < 16 {
            return ansiColor(code - 8, bright: true)
        }
        // Grayscale and color cube would go here
        return .primary
    }
}
