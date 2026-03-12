//
//  TerminalView.swift
//  easeTerminal
//
//  SwiftUI wrapper for SwiftTerm's LocalProcessTerminalView.
//  SwiftTerm handles all VT100/Xterm terminal emulation properly.
//

import SwiftUI
import SwiftTerm

/// SwiftUI wrapper for a single terminal instance
struct TerminalView: View {
    let session: TerminalSession
    @State private var terminalSize: String = "80x24"
    @State private var coordinator: SwiftTerminalView.Coordinator?
    
    var body: some View {
        SwiftTerminalView(
            session: session,
            sizeChanged: { cols, rows in
                terminalSize = "\(cols)x\(rows)"
            },
            processTerminated: {
                session.isActive = false
            },
            coordinatorCreated: { coord in
                self.coordinator = coord
                
                // Wire up terminal content callback
                session.getTerminalContent = { [weak coord] in
                    coord?.getTerminalContent() ?? ""
                }
                
                // Wire up command fill callback
                session.fillCommand = { [weak coord] command in
                    coord?.fillCommand(command)
                }
            }
        )
        .overlay(alignment: .bottomTrailing) {
            Text(terminalSize)
                .font(.caption2.monospaced())
                .foregroundStyle(.secondary)
                .padding(6)
        }
    }
}

/// Container view that adds padding around the terminal
class PaddedTerminalContainer: NSView {
    let terminalView: LocalProcessTerminalView
    let padding: CGFloat = 10
    
    init(terminalView: LocalProcessTerminalView) {
        self.terminalView = terminalView
        super.init(frame: .zero)
        
        addSubview(terminalView)
        wantsLayer = true
        layer?.backgroundColor = NSColor(red: 0.06, green: 0.06, blue: 0.08, alpha: 1.0).cgColor
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override func layout() {
        super.layout()
        // Inset the terminal view by the padding amount
        terminalView.frame = bounds.insetBy(dx: padding, dy: padding)
    }
    
    override var acceptsFirstResponder: Bool { true }
    
    override func becomeFirstResponder() -> Bool {
        return terminalView.becomeFirstResponder()
    }
}

/// NSViewRepresentable wrapper for SwiftTerm's LocalProcessTerminalView.
struct SwiftTerminalView: NSViewRepresentable {
    let session: TerminalSession
    var sizeChanged: ((Int, Int) -> Void)?
    var processTerminated: (() -> Void)?
    var coordinatorCreated: ((Coordinator) -> Void)?
    
    func makeCoordinator() -> Coordinator {
        let coordinator = Coordinator(session: session, sizeChanged: sizeChanged, processTerminated: processTerminated)
        DispatchQueue.main.async {
            coordinatorCreated?(coordinator)
        }
        return coordinator
    }
    
    func makeNSView(context: Context) -> PaddedTerminalContainer {
        let terminal = LocalProcessTerminalView(frame: NSRect(x: 0, y: 0, width: 800, height: 600))
        
        // Configure appearance - dark terminal theme
        terminal.font = NSFont.monospacedSystemFont(ofSize: 13, weight: .regular)
        
        // Colors
        let fgColor = NSColor(red: 0.9, green: 0.9, blue: 0.9, alpha: 1.0)
        let bgColor = NSColor(red: 0.06, green: 0.06, blue: 0.08, alpha: 1.0)
        terminal.nativeForegroundColor = fgColor
        terminal.nativeBackgroundColor = bgColor
        terminal.caretColor = NSColor.systemCyan
        
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
        
        // Create padded container
        let container = PaddedTerminalContainer(terminalView: terminal)
        
        // Make it first responder
        DispatchQueue.main.async {
            terminal.window?.makeFirstResponder(terminal)
        }
        
        return container
    }
    
    func updateNSView(_ container: PaddedTerminalContainer, context: Context) {
        // Nothing to update
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
            guard let terminal = terminal else { return "" }
            
            // Get the terminal's buffer content using the built-in method
            let terminalAccess = terminal.getTerminal()
            let data = terminalAccess.getBufferAsData()
            
            // Convert to string, limit to reasonable size for AI context
            guard let content = String(data: data, encoding: .utf8) else {
                return ""
            }
            
            // If content is very large, take the last portion (most recent output)
            let maxLength = 50_000
            if content.count > maxLength {
                let startIndex = content.index(content.endIndex, offsetBy: -maxLength)
                return "...[truncated]...\n" + String(content[startIndex...])
            }
            
            return content
        }
        
        /// Fill a command into the terminal (type it at the current prompt)
        func fillCommand(_ command: String) {
            guard let terminal = terminal else { return }
            
            // Send the command as keyboard input
            terminal.send(txt: command)
        }
    }
}
