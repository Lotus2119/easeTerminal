//
//  SwiftTerminalView.swift
//  easeTerminal
//
//  NSViewRepresentable bridging SwiftTerm's LocalProcessTerminalView into SwiftUI.
//

import SwiftUI
import SwiftTerm

/// NSViewRepresentable wrapper for SwiftTerm's LocalProcessTerminalView.
struct SwiftTerminalView: NSViewRepresentable {
    let session: TerminalSession
    var sizeChanged: ((Int, Int) -> Void)?
    var processTerminated: (() -> Void)?
    var coordinatorCreated: ((Coordinator) -> Void)?
    
    func makeCoordinator() -> Coordinator {
        let coordinator = Coordinator(session: session, sizeChanged: sizeChanged, processTerminated: processTerminated)
        Task { @MainActor in
            coordinatorCreated?(coordinator)
        }
        return coordinator
    }
    
    func makeNSView(context: Context) -> PaddedTerminalContainer {
        // Reuse existing terminal view if the session already has one
        // (e.g. after a pop-out/dock transition). This keeps the PTY alive.
        if let terminal = session.persistentTerminalView {
            // Detach from old parent so it can be re-hosted in a fresh container
            terminal.removeFromSuperview()
            
            terminal.processDelegate = context.coordinator
            context.coordinator.terminal = terminal
            
            let container = PaddedTerminalContainer(terminalView: terminal)
            
            // Force the terminal to re-render after being re-parented.
            // Without this, the view can appear blank because AppKit's
            // layer-backed rendering hasn't been invalidated.
            terminal.needsLayout = true
            terminal.needsDisplay = true
            terminal.layer?.setNeedsDisplay()
            
            Task { @MainActor in
                // After the container is in the window, force layout and first responder
                container.needsLayout = true
                container.layoutSubtreeIfNeeded()
                terminal.needsDisplay = true
                terminal.window?.makeFirstResponder(terminal)
            }
            return container
        }
        
        let terminal = LocalProcessTerminalView(frame: NSRect(x: 0, y: 0, width: 800, height: 600))
        
        // Configure appearance - dark terminal theme
        terminal.font = NSFont.monospacedSystemFont(ofSize: 14, weight: .regular)
        
        // High contrast warm white on deep charcoal
        let fgColor = NSColor(red: 0.95, green: 0.93, blue: 0.88, alpha: 1.0)
        let bgColor = NSColor(red: 0.11, green: 0.11, blue: 0.13, alpha: 1.0)
        terminal.nativeForegroundColor = fgColor
        terminal.nativeBackgroundColor = bgColor
        terminal.caretColor = NSColor(red: 0.0, green: 0.9, blue: 0.9, alpha: 1.0)
        terminal.selectedTextBackgroundColor = NSColor(red: 0.2, green: 0.4, blue: 0.6, alpha: 0.5)
        
        // Set delegate
        terminal.processDelegate = context.coordinator
        context.coordinator.terminal = terminal
        
        // Get user's shell and home directory
        let shell = getShell()
        let shellName = (shell as NSString).lastPathComponent
        let homeDir = ProcessInfo.processInfo.environment["HOME"] ?? NSHomeDirectory()
        
        // Build environment with PATH included
        let environment = buildEnvironment()
        
        // Start the shell process as a login shell (prefixed with -)
        // Start in user's home directory
        terminal.startProcess(
            executable: shell,
            environment: environment,
            execName: "-\(shellName)",
            currentDirectory: homeDir
        )
        
        // Store on session so it can be reused across pop-out/dock transitions
        session.setPersistentTerminalView(terminal)
        
        // Create padded container
        let container = PaddedTerminalContainer(terminalView: terminal)
        
        // Make it first responder
        Task { @MainActor in
            terminal.window?.makeFirstResponder(terminal)
        }
        
        return container
    }
    
    func updateNSView(_ container: PaddedTerminalContainer, context: Context) {
        // Ensure the terminal view is properly sized after SwiftUI layout changes
        // (e.g. after re-docking from a pop-out window)
        let terminal = container.terminalView
        if terminal.frame.isEmpty && !container.bounds.isEmpty {
            container.needsLayout = true
            terminal.needsDisplay = true
        }
    }
    
    private func getShell() -> String {
        ProcessInfo.processInfo.environment["SHELL"] ?? "/bin/zsh"
    }
    
    /// Build environment variables for the shell, including PATH
    private func buildEnvironment() -> [String] {
        var env: [String] = []
        let processEnv = ProcessInfo.processInfo.environment
        
        // Essential terminal variables
        env.append("TERM=xterm-256color")
        env.append("COLORTERM=truecolor")
        env.append("LANG=en_US.UTF-8")
        
        // Enable colors by default
        env.append("CLICOLOR=1")
        env.append("CLICOLOR_FORCE=1")
        env.append("LSCOLORS=GxFxCxDxBxegedabagaced")
        
        // Pass through important environment variables
        let passthrough = [
            "HOME", "USER", "LOGNAME", "SHELL",
            "PATH",  // Critical for finding commands like ping
            "TMPDIR", "XPC_FLAGS", "XPC_SERVICE_NAME",
            "Apple_PubSub_Socket_Render", "SSH_AUTH_SOCK",
            "LC_ALL", "LC_CTYPE", "LC_TERMINAL"
        ]
        
        for key in passthrough {
            if let value = processEnv[key] {
                env.append("\(key)=\(value)")
            }
        }
        
        return env
    }
    
    class Coordinator: NSObject, LocalProcessTerminalViewDelegate {
        weak var terminal: LocalProcessTerminalView?
        let session: TerminalSession
        var sizeChanged: ((Int, Int) -> Void)?
        var processTerminated: (() -> Void)?
        
        init(session: TerminalSession, sizeChanged: ((Int, Int) -> Void)?, processTerminated: (() -> Void)?) {
            self.session = session
            self.sizeChanged = sizeChanged
            self.processTerminated = processTerminated
        }
        
        func sizeChanged(source: LocalProcessTerminalView, newCols: Int, newRows: Int) {
            sizeChanged?(newCols, newRows)
        }
        
        func setTerminalTitle(source: LocalProcessTerminalView, title: String) {
            session.title = title.isEmpty ? "Terminal" : title
        }
        
        func hostCurrentDirectoryUpdate(source: SwiftTerm.TerminalView, directory: String?) {
            // Could update session with current directory
        }
        
        func processTerminated(source: SwiftTerm.TerminalView, exitCode: Int32?) {
            processTerminated?()
        }
        
        // MARK: - AI Panel Support
        
        /// Get the current terminal buffer content as a string
        func getTerminalContent() -> String {
            guard let terminal = terminal else {
                return ""
            }
            
            // Get the terminal's buffer content using the built-in method
            let terminalAccess = terminal.getTerminal()
            let data = terminalAccess.getBufferAsData()
            
            // Convert to string, limit to reasonable size for AI context
            guard let content = String(data: data, encoding: .utf8) else {
                return ""
            }
            
            // Clean up the content - remove trailing empty lines
            let lines = content.components(separatedBy: .newlines)
            let cleanedLines = lines
                .reversed()
                .drop(while: { $0.trimmingCharacters(in: .whitespaces).isEmpty })
                .reversed()
            let cleanedContent = Array(cleanedLines).joined(separator: "\n")
            
            // If content is very large, take the last portion (most recent output)
            let maxLength = 50_000
            if cleanedContent.count > maxLength {
                let startIndex = cleanedContent.index(cleanedContent.endIndex, offsetBy: -maxLength)
                return "...[truncated]...\n" + String(cleanedContent[startIndex...])
            }
            
            return cleanedContent
        }
        
        /// Fill a command into the terminal (type it at the current prompt)
        func fillCommand(_ command: String) {
            guard let terminal = terminal else { return }
            
            // Send the command as keyboard input
            terminal.send(txt: command)
        }
    }
}
