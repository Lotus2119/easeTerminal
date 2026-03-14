//
//  PTYProcessPTYProcess.swift
//  easeTerminal
//
//  Manages a pseudoterminal session running a real shell (zsh).
//  Uses POSIX PTY APIs (forkpty) for proper terminal emulation.
//

import Foundation
import Darwin

// MARK: - POSIX Wait Status Macros
// These macros are defined in C but not exposed to Swift, so we implement them manually.

private func wIfExited(_ status: Int32) -> Bool {
    return (status & 0x7F) == 0
}

private func wExitStatus(_ status: Int32) -> Int32 {
    return (status >> 8) & 0xFF
}

private func wIfSignaled(_ status: Int32) -> Bool {
    return ((status & 0x7F) + 1) >> 1 > 0 && !wIfExited(status)
}

private func wTermSig(_ status: Int32) -> Int32 {
    return status & 0x7F
}

/// Manages a PTY-backed shell process.
///
/// Design decisions:
/// - Uses forkpty() for proper PTY allocation (handles SIGWINCH, job control, etc.)
/// - Runs I/O on detached Tasks to avoid blocking the cooperative thread pool
/// - Streams output to the context buffer for AI consumption
/// - Clean separation: this class handles process lifecycle, not rendering
final class PTYProcess: @unchecked Sendable {
    
    // MARK: - Types
    
    enum PTYError: Error, LocalizedError {
        case forkFailed(errno: Int32)
        case shellNotFound
        case processNotRunning
        
        var errorDescription: String? {
            switch self {
            case .forkFailed(let errno):
                return "Failed to create PTY: \(String(cString: strerror(errno)))"
            case .shellNotFound:
                return "Could not find shell executable"
            case .processNotRunning:
                return "Shell process is not running"
            }
        }
    }
    
    enum ProcessState: Sendable {
        case idle
        case running
        case terminated(exitCode: Int32)
    }
    
    // MARK: - Properties
    
    /// Current process state
    private(set) var state: ProcessState = .idle
    
    /// Context buffer for AI integration
    let contextBuffer: ContextBuffer
    
    /// Callback for output data (for UI updates)
    var onOutput: (@Sendable (Data) -> Void)?
    
    /// Callback for process termination
    var onTermination: (@Sendable (Int32) -> Void)?
    
    /// File descriptor for the master side of the PTY
    private var masterFD: Int32 = -1
    
    /// Child process ID
    private var childPID: pid_t = -1
    
    /// Flag to stop read loop
    private var shouldStopReading = false
    
    /// Current terminal size
    private var terminalSize: winsize
    
    // MARK: - Initialization
    
    init(contextBuffer: ContextBuffer = ContextBuffer()) {
        self.contextBuffer = contextBuffer
        // Default terminal size (80x24 is traditional)
        self.terminalSize = winsize(ws_row: 24, ws_col: 80, ws_xpixel: 0, ws_ypixel: 0)
    }
    
    deinit {
        terminate()
    }
    
    // MARK: - Process Lifecycle
    
    /// Starts the shell process.
    /// - Parameter shell: Path to shell executable (defaults to user's shell or /bin/zsh)
    func start(shell: String? = nil) throws {
        guard case .idle = state else { return }
        
        let shellPath = try resolveShellPath(shell)
        
        // Set up environment
        var env = ProcessInfo.processInfo.environment
        env["TERM"] = "xterm-256color"
        env["COLORTERM"] = "truecolor"
        env["LANG"] = env["LANG"] ?? "en_US.UTF-8"
        
        // Convert environment to C string array
        var envStrings = env.map { "\($0.key)=\($0.value)" }
        let envPointers = UnsafeMutablePointer<UnsafeMutablePointer<CChar>?>.allocate(capacity: envStrings.count + 1)
        defer { envPointers.deallocate() }
        
        for (index, string) in envStrings.enumerated() {
            envPointers[index] = strdup(string)
        }
        envPointers[envStrings.count] = nil
        defer {
            for i in 0..<envStrings.count {
                free(envPointers[i])
            }
        }
        
        // Fork with PTY
        var masterFDValue: Int32 = -1
        var size = terminalSize
        
        let pid = forkpty(&masterFDValue, nil, nil, &size)
        
        if pid < 0 {
            throw PTYError.forkFailed(errno: errno)
        } else if pid == 0 {
            // Child process - exec the shell
            let argv: [UnsafeMutablePointer<CChar>?] = [
                strdup(shellPath),
                strdup("-l"),
                nil
            ]
            
            execve(shellPath, argv, envPointers)
            
            // If execve returns, it failed
            _exit(1)
        } else {
            // Parent process
            self.masterFD = masterFDValue
            self.childPID = pid
            self.state = .running
            self.shouldStopReading = false
            
            // Set non-blocking mode
            let flags = fcntl(masterFD, F_GETFL)
            fcntl(masterFD, F_SETFL, flags | O_NONBLOCK)
            
            // Log system event
            Task {
                await contextBuffer.append(type: .system, content: "Shell started: \(shellPath)")
            }
            
            // Start reading output
            startReadLoop()
            
            // Monitor child process
            monitorChildProcess()
        }
    }
    
    /// Writes data to the PTY (stdin).
    func write(_ data: Data) {
        guard case .running = state, masterFD >= 0 else { return }
        
        Task.detached(priority: .userInitiated) { [weak self] in
            guard let self else { return }
            
            data.withUnsafeBytes { buffer in
                guard let ptr = buffer.baseAddress else { return }
                var remaining = data.count
                var offset = 0
                
                while remaining > 0 {
                    let written = Darwin.write(self.masterFD, ptr.advanced(by: offset), remaining)
                    if written < 0 {
                        if errno == EAGAIN || errno == EWOULDBLOCK {
                            // Brief pause and retry — blocking call acceptable in detached task
                            usleep(1000)
                            continue
                        }
                        break
                    }
                    offset += written
                    remaining -= written
                }
            }
            
            // Log stdin to context buffer
            if let string = String(data: data, encoding: .utf8) {
                await self.contextBuffer.append(type: .stdin, content: string)
            }
        }
    }
    
    /// Writes a string to the PTY.
    func write(_ string: String) {
        guard let data = string.data(using: .utf8) else { return }
        write(data)
    }
    
    /// Sends a signal to the child process.
    func sendSignal(_ signal: Int32) {
        guard case .running = state, childPID > 0 else { return }
        kill(childPID, signal)
    }
    
    /// Resizes the PTY window.
    func resize(columns: UInt16, rows: UInt16) {
        terminalSize.ws_col = columns
        terminalSize.ws_row = rows
        
        guard case .running = state, masterFD >= 0 else { return }
        
        var size = terminalSize
        _ = ioctl(masterFD, TIOCSWINSZ, &size)
    }
    
    /// Terminates the shell process.
    func terminate() {
        shouldStopReading = true
        
        if case .running = state, childPID > 0 {
            kill(childPID, SIGTERM)
            
            // Give it a moment to exit gracefully, then force-kill
            let pid = childPID
            Task { [weak self] in
                try? await Task.sleep(for: .milliseconds(500))
                guard let self else { return }
                if case .running = self.state {
                    kill(pid, SIGKILL)
                }
            }
        }
        
        if masterFD >= 0 {
            close(masterFD)
            masterFD = -1
        }
    }
    
    // MARK: - Private Methods
    
    private func resolveShellPath(_ provided: String?) throws -> String {
        if let provided {
            return provided
        }
        
        // Try user's default shell from environment
        if let shell = ProcessInfo.processInfo.environment["SHELL"] {
            return shell
        }
        
        // Fall back to zsh
        let defaultShells = ["/bin/zsh", "/usr/bin/zsh", "/bin/bash"]
        for shell in defaultShells {
            if FileManager.default.isExecutableFile(atPath: shell) {
                return shell
            }
        }
        
        throw PTYError.shellNotFound
    }
    
    private func startReadLoop() {
        Task.detached(priority: .userInitiated) { [weak self] in
            guard let self else { return }
            
            let bufferSize = 8192
            let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: bufferSize)
            defer { buffer.deallocate() }
            
            while !self.shouldStopReading {
                guard case .running = self.state else { break }
                
                let bytesRead = read(self.masterFD, buffer, bufferSize)
                
                if bytesRead > 0 {
                    let data = Data(bytes: buffer, count: bytesRead)
                    
                    // Notify UI
                    self.onOutput?(data)
                    
                    // Log to context buffer
                    if let string = String(data: data, encoding: .utf8) {
                        await self.contextBuffer.append(type: .stdout, content: string)
                    }
                } else if bytesRead == 0 {
                    // EOF - child process closed
                    break
                } else {
                    // Error or would block
                    if errno == EAGAIN || errno == EWOULDBLOCK {
                        // 10ms pause before retry — blocking call acceptable in detached task
                        try? await Task.sleep(for: .milliseconds(10))
                        continue
                    }
                    break
                }
            }
        }
    }
    
    private func monitorChildProcess() {
        Task.detached(priority: .utility) { [weak self] in
            guard let self else { return }
            
            var status: Int32 = 0
            let result = waitpid(self.childPID, &status, 0)
            
            if result == self.childPID {
                let exitCode: Int32
                if wIfExited(status) {
                    exitCode = wExitStatus(status)
                } else if wIfSignaled(status) {
                    exitCode = wTermSig(status) + 128
                } else {
                    exitCode = -1
                }
                
                await MainActor.run {
                    self.state = .terminated(exitCode: exitCode)
                    self.shouldStopReading = true
                    self.onTermination?(exitCode)
                    
                    if self.masterFD >= 0 {
                        close(self.masterFD)
                        self.masterFD = -1
                    }
                }
                
                await self.contextBuffer.append(
                    type: .system,
                    content: "Shell terminated with exit code: \(exitCode)"
                )
            }
        }
    }
}
