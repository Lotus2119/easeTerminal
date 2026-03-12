//
//  ContextBuffer.swift
//  easeTerminal
//
//  Rolling buffer that captures terminal I/O for AI context packaging.
//  Designed for thread-safe access by the local model layer.
//

import Foundation

/// Represents a single entry in the terminal context buffer.
/// Each entry captures either input (commands) or output (responses) with metadata.
struct ContextEntry: Identifiable, Sendable {
    let id: UUID
    let timestamp: Date
    let type: EntryType
    let content: String
    
    enum EntryType: String, Sendable {
        case stdin      // User input/commands
        case stdout     // Standard output
        case stderr     // Error output
        case system     // System events (shell start, exit, etc.)
    }
    
    init(type: EntryType, content: String) {
        self.id = UUID()
        self.timestamp = Date()
        self.type = type
        self.content = content
    }
}

/// Thread-safe rolling buffer for terminal context.
/// The local AI model reads from this buffer to package context for Claude.
///
/// Design decisions:
/// - Uses actor for thread safety (terminal I/O happens on background threads)
/// - Rolling buffer with configurable max entries to bound memory usage
/// - Entries are immutable and timestamped for context reconstruction
/// - Provides structured access for AI context packaging
actor ContextBuffer {
    private var entries: [ContextEntry] = []
    private let maxEntries: Int
    private let maxTotalCharacters: Int
    
    /// Creates a new context buffer.
    /// - Parameters:
    ///   - maxEntries: Maximum number of entries to retain (default 1000)
    ///   - maxTotalCharacters: Soft limit on total character count (default 100KB)
    init(maxEntries: Int = 1000, maxTotalCharacters: Int = 100_000) {
        self.maxEntries = maxEntries
        self.maxTotalCharacters = maxTotalCharacters
    }
    
    /// Appends a new entry to the buffer, evicting old entries if needed.
    func append(_ entry: ContextEntry) {
        entries.append(entry)
        trimIfNeeded()
    }
    
    /// Convenience method to append content with a specific type.
    func append(type: ContextEntry.EntryType, content: String) {
        guard !content.isEmpty else { return }
        append(ContextEntry(type: type, content: content))
    }
    
    /// Returns all entries in chronological order.
    func allEntries() -> [ContextEntry] {
        entries
    }
    
    /// Returns the most recent N entries.
    func recentEntries(count: Int) -> [ContextEntry] {
        Array(entries.suffix(count))
    }
    
    /// Returns entries since a specific timestamp.
    func entries(since timestamp: Date) -> [ContextEntry] {
        entries.filter { $0.timestamp >= timestamp }
    }
    
    /// Returns entries of specific types (useful for filtering stdin only, etc.)
    func entries(ofTypes types: Set<ContextEntry.EntryType>) -> [ContextEntry] {
        entries.filter { types.contains($0.type) }
    }
    
    /// Formats buffer contents for AI context packaging.
    /// Returns a structured string representation suitable for LLM consumption.
    func formattedContext(maxCharacters: Int = 50_000) -> String {
        var result = ""
        var totalChars = 0
        
        // Work backwards from most recent to include latest context
        for entry in entries.reversed() {
            let prefix: String
            switch entry.type {
            case .stdin:
                prefix = "$ "
            case .stdout:
                prefix = ""
            case .stderr:
                prefix = "[stderr] "
            case .system:
                prefix = "[system] "
            }
            
            let line = "\(prefix)\(entry.content)"
            let lineLength = line.count + 1 // +1 for newline
            
            if totalChars + lineLength > maxCharacters {
                break
            }
            
            result = line + "\n" + result
            totalChars += lineLength
        }
        
        return result
    }
    
    /// Clears all entries from the buffer.
    func clear() {
        entries.removeAll()
    }
    
    /// Current entry count.
    var count: Int {
        entries.count
    }
    
    /// Trims buffer to stay within limits.
    private func trimIfNeeded() {
        // Trim by entry count
        if entries.count > maxEntries {
            entries.removeFirst(entries.count - maxEntries)
        }
        
        // Trim by total character count (soft limit)
        var totalChars = entries.reduce(0) { $0 + $1.content.count }
        while totalChars > maxTotalCharacters && entries.count > 1 {
            totalChars -= entries.removeFirst().content.count
        }
    }
}

/// Protocol for components that need to observe terminal context.
/// The AI provider layer will implement this to receive context updates.
protocol ContextBufferObserver: AnyObject, Sendable {
    func contextBuffer(_ buffer: ContextBuffer, didAppend entry: ContextEntry) async
}
