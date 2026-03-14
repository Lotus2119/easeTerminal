//
//  SessionContext.swift
//  easeTerminal
//
//  Unified session context that feeds into all AI interactions.
//  Each terminal tab has its own SessionContext, ensuring context never bleeds between tabs.
//
//  Architecture:
//  - TerminalSession owns a SessionContext
//  - SessionContext holds three context sources: terminal buffer, troubleshooting history, chat history
//  - All AI operations (chat and troubleshoot) receive the full unified context
//  - Context window management prevents blowing out the model's context limit
//

import Foundation
import SwiftUI

// MARK: - Troubleshooting Entry

/// A single troubleshooting interaction with packaged context and AI response
public struct TroubleshootingEntry: Identifiable, Equatable, Codable {
    public let id: UUID
    public let timestamp: Date
    public let userQuery: String?
    public let packagedContext: String
    public let aiResponse: String
    public let extractedCommands: [String]
    public var commandsExecuted: [CommandExecution]
    public let isFromCloud: Bool
    
    public init(
        userQuery: String?,
        packagedContext: String,
        aiResponse: String,
        extractedCommands: [String] = [],
        isFromCloud: Bool = false
    ) {
        self.id = UUID()
        self.timestamp = Date()
        self.userQuery = userQuery
        self.packagedContext = packagedContext
        self.aiResponse = aiResponse
        self.extractedCommands = extractedCommands
        self.commandsExecuted = []
        self.isFromCloud = isFromCloud
    }
    
    /// Create a summarized version of older entries to save context space
    public var summarized: String {
        var summary = "**Troubleshoot at \(timestamp.formatted(date: .abbreviated, time: .shortened))**\n"
        if let query = userQuery {
            summary += "User asked: \(query)\n"
        }
        summary += "Commands suggested: \(extractedCommands.joined(separator: ", "))\n"
        if !commandsExecuted.isEmpty {
            let results = commandsExecuted.map { $0.succeeded ? "✓" : "✗" }.joined()
            summary += "Results: \(results)\n"
        }
        return summary
    }
}

// MARK: - Command Execution

/// Tracks when an extracted command was executed and its result
public struct CommandExecution: Identifiable, Equatable, Codable {
    public let id: UUID
    public let command: String
    public let timestamp: Date
    public let terminalOutput: String?
    public let succeeded: Bool
    
    public init(command: String, terminalOutput: String?, succeeded: Bool) {
        self.id = UUID()
        self.command = command
        self.timestamp = Date()
        self.terminalOutput = terminalOutput
        self.succeeded = succeeded
    }
}

// MARK: - Context Source Toggle

/// Which context sources to include in AI requests
public struct ContextSourceOptions: Equatable {
    public var includeTerminalBuffer: Bool = true
    public var includeTroubleshootHistory: Bool = true
    public var includeChatHistory: Bool = true
    
    public static let all = ContextSourceOptions()
    
    public var description: String {
        var parts: [String] = []
        if includeTerminalBuffer { parts.append("Terminal") }
        if includeTroubleshootHistory { parts.append("Troubleshoot") }
        if includeChatHistory { parts.append("Chat") }
        return parts.isEmpty ? "None" : parts.joined(separator: ", ")
    }
}

// MARK: - Context Settings

/// Configurable limits for context window management
public struct ContextSettings: Equatable, Codable {
    /// Maximum lines of terminal buffer to include (most recent)
    public var maxTerminalLines: Int = 200
    
    /// Maximum number of chat exchanges to include
    public var maxChatExchanges: Int = 10
    
    /// Maximum number of full troubleshoot entries (older ones get summarized)
    public var maxFullTroubleshootEntries: Int = 2
    
    /// Maximum total characters for the entire context
    public var maxTotalContextChars: Int = 32000
    
    public static let `default` = ContextSettings()
    
    public static func loadFromDefaults() -> ContextSettings {
        var settings = ContextSettings.default
        if let maxLines = UserDefaults.standard.object(forKey: "context.maxTerminalLines") as? Int {
            settings.maxTerminalLines = maxLines
        }
        if let maxChat = UserDefaults.standard.object(forKey: "context.maxChatExchanges") as? Int {
            settings.maxChatExchanges = maxChat
        }
        if let maxTroubleshoot = UserDefaults.standard.object(forKey: "context.maxFullTroubleshootEntries") as? Int {
            settings.maxFullTroubleshootEntries = maxTroubleshoot
        }
        return settings
    }
    
    public func saveToDefaults() {
        UserDefaults.standard.set(maxTerminalLines, forKey: "context.maxTerminalLines")
        UserDefaults.standard.set(maxChatExchanges, forKey: "context.maxChatExchanges")
        UserDefaults.standard.set(maxFullTroubleshootEntries, forKey: "context.maxFullTroubleshootEntries")
    }
}

// MARK: - Session Context

/// The unified context for a single terminal session.
/// Observable to enable reactive UI updates.
@Observable
public final class SessionContext {
    
    // MARK: - Context Sources
    
    /// The terminal buffer content (most recent lines based on settings)
    private(set) var terminalBufferContent: String = ""
    
    /// Troubleshooting history for this session
    private(set) var troubleshootingHistory: [TroubleshootingEntry] = []
    
    /// Chat messages for this session (stored separately from AIPanelState for context purposes)
    private(set) var chatHistory: [ChatMessage] = []
    
    // MARK: - Settings
    
    /// Context window settings
    var settings: ContextSettings = .loadFromDefaults()
    
    /// Which sources to include in AI requests
    var sourceOptions: ContextSourceOptions = .all
    
    // MARK: - Computed Properties
    
    /// Number of lines in the current terminal buffer
    var terminalLineCount: Int {
        terminalBufferContent.isEmpty ? 0 : terminalBufferContent.components(separatedBy: .newlines).count
    }
    
    /// Number of troubleshoot sessions
    var troubleshootSessionCount: Int {
        troubleshootingHistory.count
    }
    
    /// Number of chat messages
    var chatMessageCount: Int {
        chatHistory.count
    }
    
    /// Whether there's any context loaded
    var hasContext: Bool {
        !terminalBufferContent.isEmpty || !troubleshootingHistory.isEmpty || !chatHistory.isEmpty
    }
    
    /// Summary string for UI display
    var contextSummary: String {
        var parts: [String] = []
        if terminalLineCount > 0 {
            parts.append("\(terminalLineCount) lines")
        }
        if troubleshootSessionCount > 0 {
            parts.append("\(troubleshootSessionCount) troubleshoot\(troubleshootSessionCount > 1 ? "s" : "")")
        }
        if chatMessageCount > 0 {
            parts.append("\(chatMessageCount) message\(chatMessageCount > 1 ? "s" : "")")
        }
        return parts.isEmpty ? "No context" : parts.joined(separator: " · ")
    }
    
    // MARK: - Terminal Buffer Management
    
    /// Update the terminal buffer content from the terminal view
    func updateTerminalBuffer(_ content: String) {
        // Apply line limit
        let lines = content.components(separatedBy: .newlines)
        if lines.count > settings.maxTerminalLines {
            let startIndex = lines.count - settings.maxTerminalLines
            terminalBufferContent = lines[startIndex...].joined(separator: "\n")
        } else {
            terminalBufferContent = content
        }
    }
    
    // MARK: - Troubleshooting History Management
    
    /// Add a new troubleshooting entry
    func addTroubleshootEntry(_ entry: TroubleshootingEntry) {
        troubleshootingHistory.append(entry)
    }
    
    /// Record that a command was executed
    func recordCommandExecution(command: String, output: String?, succeeded: Bool) {
        // Find the most recent troubleshoot entry that contains this command
        if let index = troubleshootingHistory.lastIndex(where: { $0.extractedCommands.contains(command) }) {
            let execution = CommandExecution(command: command, terminalOutput: output, succeeded: succeeded)
            troubleshootingHistory[index].commandsExecuted.append(execution)
        }
    }
    
    // MARK: - Chat History Management
    
    /// Sync chat history from AIPanelState
    func syncChatHistory(_ messages: [ChatMessage]) {
        chatHistory = messages
    }
    
    /// Add a chat message
    func addChatMessage(_ message: ChatMessage) {
        chatHistory.append(message)
    }
    
    // MARK: - Context Building
    
    /// Build the unified context for AI requests based on current settings and source options
    func buildContext() -> UnifiedContext {
        var terminalSection = ""
        var troubleshootSection = ""
        var chatSection = ""
        
        // Terminal buffer
        if sourceOptions.includeTerminalBuffer && !terminalBufferContent.isEmpty {
            terminalSection = terminalBufferContent
        }
        
        // Troubleshooting history (full recent, summarized older)
        if sourceOptions.includeTroubleshootHistory && !troubleshootingHistory.isEmpty {
            var parts: [String] = []
            let count = troubleshootingHistory.count
            
            for (index, entry) in troubleshootingHistory.enumerated() {
                let isRecent = index >= count - settings.maxFullTroubleshootEntries
                if isRecent {
                    // Include full entry for recent troubleshoots
                    var entryText = "### Troubleshoot Session \(index + 1) (at \(entry.timestamp.formatted(date: .abbreviated, time: .shortened)))\n"
                    if let query = entry.userQuery {
                        entryText += "**User Query:** \(query)\n"
                    }
                    entryText += "**Context Sent:**\n\(entry.packagedContext)\n"
                    entryText += "**AI Response:**\n\(entry.aiResponse)\n"
                    if !entry.commandsExecuted.isEmpty {
                        entryText += "**Command Results:**\n"
                        for exec in entry.commandsExecuted {
                            entryText += "- `\(exec.command)`: \(exec.succeeded ? "succeeded" : "failed")\n"
                            if let output = exec.terminalOutput, !output.isEmpty {
                                entryText += "  Output: \(output.prefix(200))...\n"
                            }
                        }
                    }
                    parts.append(entryText)
                } else {
                    // Summarize older entries
                    parts.append(entry.summarized)
                }
            }
            
            troubleshootSection = parts.joined(separator: "\n---\n")
        }
        
        // Chat history (most recent exchanges)
        if sourceOptions.includeChatHistory && !chatHistory.isEmpty {
            let maxMessages = settings.maxChatExchanges * 2 // Each exchange is 2 messages
            let recentMessages = chatHistory.suffix(maxMessages)
            
            var parts: [String] = []
            for message in recentMessages {
                let role = message.role == .user ? "User" : "Assistant"
                parts.append("**\(role):** \(message.content)")
            }
            
            chatSection = parts.joined(separator: "\n\n")
        }
        
        return UnifiedContext(
            terminalBuffer: terminalSection,
            troubleshootHistory: troubleshootSection,
            chatHistory: chatSection,
            settings: settings
        )
    }
    
    // MARK: - Clear Operations
    
    /// Clear all context sources
    func clearAll() {
        terminalBufferContent = ""
        troubleshootingHistory.removeAll()
        chatHistory.removeAll()
    }
    
    /// Clear just the troubleshooting history
    func clearTroubleshootHistory() {
        troubleshootingHistory.removeAll()
    }
    
    /// Clear just the chat history
    func clearChatHistory() {
        chatHistory.removeAll()
    }
}

// MARK: - Unified Context

/// The assembled context ready to be sent to AI providers
public struct UnifiedContext {
    public let terminalBuffer: String
    public let troubleshootHistory: String
    public let chatHistory: String
    public let settings: ContextSettings
    
    /// Build a system prompt that clearly explains the context structure
    public func buildSystemPrompt(forMode mode: AIPanelMode) -> String {
        var prompt = """
        You are an AI assistant integrated into a terminal application called easeTerminal.
        You help users with coding, debugging, terminal commands, and troubleshooting.
        
        """
        
        // Add context awareness explanation
        if !terminalBuffer.isEmpty || !troubleshootHistory.isEmpty {
            prompt += """
            
            ## Session Context
            You have access to the user's current session context, which includes:
            
            """
            
            if !terminalBuffer.isEmpty {
                prompt += "- **Terminal Output:** The recent output from their terminal session\n"
            }
            
            if !troubleshootHistory.isEmpty {
                prompt += "- **Troubleshooting History:** Previous troubleshooting sessions and what was suggested\n"
            }
            
            if !chatHistory.isEmpty {
                prompt += "- **Chat History:** The ongoing conversation in this session\n"
            }
            
            prompt += """
            
            Use this context to provide relevant, informed assistance. Reference previous suggestions when appropriate.
            Avoid suggesting the same fix twice if it was already tried. If a command was executed and failed, consider alternative approaches.
            
            """
        }
        
        // Mode-specific instructions
        switch mode {
        case .chat:
            prompt += """
            
            ## Your Role
            You are in chat mode. Respond conversationally to the user's questions.
            You can reference the terminal output and any troubleshooting that was done.
            If the user asks about a previous command or suggestion, you have full context to answer.
            """
            
        case .terminalContext:
            prompt += """
            
            ## Your Role
            You are in troubleshooting mode. Analyze the terminal context and provide actionable solutions.
            
            """
            
            // Add explicit instructions about previous troubleshooting
            if !troubleshootHistory.isEmpty {
                prompt += """
                **IMPORTANT - Previous Troubleshooting Context:**
                The user has already received troubleshooting help in this session. Review the "Previous Troubleshooting" section in the context carefully.
                
                - DO NOT repeat suggestions or fixes that were already provided
                - DO NOT re-analyze issues that were already addressed
                - Focus ONLY on NEW issues visible in the current terminal output
                - If the user seems to be dealing with the same issue, suggest DIFFERENT approaches
                - If previous commands failed, acknowledge this and try alternative solutions
                - If an issue appears resolved (no longer showing errors), don't mention it
                
                """
            }
            
            prompt += """
            When suggesting commands:
            - Wrap them in ```bash code blocks
            - Explain what each command does
            - If there are multiple steps, number them
            
            Structure your response with clear sections:
            - ## Issue Identified (only for NEW issues not previously addressed)
            - ## Problem Analysis
            - ## Solution
            - ## Additional Notes (if needed)
            """
        }
        
        return prompt
    }
    
    /// Build the user message content with full context
    public func buildContextMessage() -> String {
        var sections: [String] = []
        
        if !terminalBuffer.isEmpty {
            sections.append("""
            ## Current Terminal Output
            ```
            \(terminalBuffer)
            ```
            """)
        }
        
        if !troubleshootHistory.isEmpty {
            sections.append("""
            ## Previous Troubleshooting
            \(troubleshootHistory)
            """)
        }
        
        if !chatHistory.isEmpty {
            sections.append("""
            ## Conversation History
            \(chatHistory)
            """)
        }
        
        return sections.joined(separator: "\n\n---\n\n")
    }
    
    /// Total character count for context window management
    public var totalCharCount: Int {
        terminalBuffer.count + troubleshootHistory.count + chatHistory.count
    }
    
    /// Whether the context exceeds recommended limits
    public var isOverLimit: Bool {
        totalCharCount > settings.maxTotalContextChars
    }
}
