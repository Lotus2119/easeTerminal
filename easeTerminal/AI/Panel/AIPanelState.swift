//
//  AIPanelState.swift
//  easeTerminal
//
//  State management for the AI side panel.
//  Handles both Chat and Terminal Context modes with unified session context.
//
//  Architecture:
//  - AIPanelState manages UI state and user interactions
//  - SessionContext (owned by TerminalSession) is the source of truth for all context
//  - Both Chat and Terminal Context modes share the same context through SessionContext
//

import Foundation
import SwiftUI

// MARK: - Panel Mode

/// The two modes of the AI panel
public enum AIPanelMode: String, CaseIterable {
    case chat = "Chat"
    case terminalContext = "Terminal"
    
    var icon: String {
        switch self {
        case .chat: return "bubble.left.and.bubble.right"
        case .terminalContext: return "terminal"
        }
    }
}

// MARK: - Auto-Fill Configuration

/// Per-session configuration for how commands are auto-filled
public enum AutoFillMode: String, CaseIterable, Codable {
    case preview = "Preview All"
    case oneAtATime = "One at a Time"
    case autoFillAll = "Auto-Fill All"
    
    var description: String {
        switch self {
        case .preview:
            return "Show all commands for review before filling"
        case .oneAtATime:
            return "Fill commands one at a time with confirmation"
        case .autoFillAll:
            return "Automatically fill all commands into terminal"
        }
    }
}

// MARK: - Panel Loading State

public enum PanelLoadingState: Equatable {
    case idle
    case packaging   // Packaging context locally
    case reasoning   // Getting reasoning response
    case streaming   // Streaming response tokens
    
    var message: String {
        switch self {
        case .idle: return ""
        case .packaging: return "Packaging context..."
        case .reasoning: return "Thinking..."
        case .streaming: return "Responding..."
        }
    }
}

// MARK: - AI Panel State

/// Observable state for the AI side panel.
/// Works with SessionContext to provide unified context across Chat and Terminal modes.
@MainActor
@Observable
public final class AIPanelState {
    
    // MARK: - Session Context Reference
    
    /// Reference to the session context (set by TerminalSession)
    public weak var sessionContext: SessionContext?
    
    // MARK: - Panel Visibility & Mode
    
    /// Whether the panel is visible
    public var isPanelVisible: Bool = false {
        didSet {
            UserDefaults.standard.set(isPanelVisible, forKey: "aiPanel.visible")
        }
    }
    
    /// Current panel mode (chat or terminal context)
    public var currentMode: AIPanelMode = .terminalContext
    
    /// Whether to show the context inspector
    public var showContextInspector: Bool = false
    
    // MARK: - Chat State
    
    /// Chat message history (synced to sessionContext)
    public var chatMessages: [ChatMessage] = [] {
        didSet {
            // Sync to session context
            sessionContext?.syncChatHistory(chatMessages)
        }
    }
    
    /// Current input text in chat
    public var chatInput: String = ""
    
    // MARK: - Terminal Context State
    
    /// The current context summary (from Summarize Error)
    public var contextSummary: ContextSummary?
    
    /// Whether context section is expanded
    public var isContextExpanded: Bool = false
    
    /// The troubleshooting response
    public var troubleshootResponse: String = ""
    
    /// Extracted commands from the response
    public var extractedCommands: [ExtractedCommand] = []
    
    // MARK: - Loading & Error State
    
    /// Current loading state
    public var loadingState: PanelLoadingState = .idle
    
    /// Error message if any
    public var errorMessage: String?
    
    // MARK: - Per-Session Configuration
    
    /// Auto-fill mode for this session
    public var autoFillMode: AutoFillMode = .preview
    
    // MARK: - Computed Properties
    
    /// Whether we're currently loading anything
    public var isLoading: Bool {
        loadingState != .idle
    }
    
    /// Get the active provider info for display
    public var activeProviderInfo: String {
        let manager = ProviderManager.shared
        switch manager.operatingMode {
        case .local:
            if let model = manager.localReasoningModel {
                return "Local: \(model.name)"
            }
            return "Local (no model)"
        case .hybrid:
            if let cloud = manager.activeCloudProvider, let model = cloud.selectedModel {
                return "Cloud: \(model.name)"
            }
            return "Hybrid (not configured)"
        }
    }
    
    /// Whether we can perform AI operations
    public var canPerformOperations: Bool {
        ProviderManager.shared.isReady
    }
    
    /// Context summary for display in UI
    public var contextDisplaySummary: String {
        sessionContext?.contextSummary ?? "No context"
    }
    
    /// Whether there's any context loaded
    public var hasContext: Bool {
        sessionContext?.hasContext ?? false
    }
    
    // MARK: - Initialization
    
    public init() {
        // Load saved visibility state
        isPanelVisible = UserDefaults.standard.bool(forKey: "aiPanel.visible")
    }
    
    // MARK: - Session Context Binding
    
    /// Bind to a session context (called by TerminalSession)
    public func bindToSessionContext(_ context: SessionContext) {
        self.sessionContext = context
    }
    
    // MARK: - Actions
    
    /// Toggle panel visibility
    public func togglePanel() {
        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
            isPanelVisible.toggle()
        }
    }
    
    /// Clear chat history
    public func clearChat() {
        withAnimation {
            chatMessages.removeAll()
            chatInput = ""
            sessionContext?.clearChatHistory()
        }
    }
    
    /// Reset terminal context state
    public func resetContext() {
        withAnimation {
            contextSummary = nil
            troubleshootResponse = ""
            extractedCommands.removeAll()
            errorMessage = nil
        }
    }
    
    /// Clear all session context (terminal buffer, troubleshoot history, chat)
    public func clearAllSessionContext() {
        withAnimation {
            chatMessages.removeAll()
            chatInput = ""
            contextSummary = nil
            troubleshootResponse = ""
            extractedCommands.removeAll()
            errorMessage = nil
            sessionContext?.clearAll()
        }
    }
    
    /// Clear error
    public func clearError() {
        errorMessage = nil
    }
    
    // MARK: - Chat Operations (Context-Aware)
    
    /// Send a chat message with full session context
    @MainActor
    public func sendChatMessage() async {
        let input = chatInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !input.isEmpty else { return }
        
        // Add user message
        let userMessage = ChatMessage(role: .user, content: input)
        chatMessages.append(userMessage)
        chatInput = ""
        
        // Add placeholder for assistant response
        let assistantPlaceholder = ChatMessage(
            role: .assistant,
            content: "",
            isStreaming: true
        )
        chatMessages.append(assistantPlaceholder)
        
        loadingState = .reasoning
        errorMessage = nil
        
        do {
            // Build unified context
            let unifiedContext = sessionContext?.buildContext() ?? UnifiedContext(
                terminalBuffer: "",
                troubleshootHistory: "",
                chatHistory: "",
                settings: .default
            )
            
            // Build system prompt with full context awareness
            let systemPrompt = unifiedContext.buildSystemPrompt(forMode: .chat)
            
            // Build conversation with context
            var messages: [ConversationMessage] = []
            
            // Add context message as a user message prefixed with context
            let contextMessage = unifiedContext.buildContextMessage()
            
            // Add chat history (excluding streaming placeholder)
            let chatHistory = chatMessages
                .filter { !$0.isStreaming }
                .map { $0.toConversationMessage() }
            
            // If there's context, prepend it to the first user message
            if !contextMessage.isEmpty && !chatHistory.isEmpty {
                // Find the first user message and prepend context to it
                for (index, msg) in chatHistory.enumerated() {
                    if msg.role == .user {
                        var modifiedHistory = chatHistory
                        let contextPrefix = """
                        [Session Context]
                        \(contextMessage)
                        
                        [User Message]
                        """
                        modifiedHistory[index] = ConversationMessage(
                            role: .user,
                            content: contextPrefix + msg.content
                        )
                        messages.append(contentsOf: modifiedHistory)
                        break
                    }
                }
                if messages.isEmpty {
                    messages.append(contentsOf: chatHistory)
                }
            } else {
                messages.append(contentsOf: chatHistory)
            }
            
            let result = try await ProviderManager.shared.complete(
                messages: messages,
                systemPrompt: systemPrompt
            )
            
            // Replace placeholder with actual response
            if let index = chatMessages.lastIndex(where: { $0.isStreaming }) {
                let responseMessage = ChatMessage(
                    role: .assistant,
                    content: result.content,
                    isFromCloud: result.isFromCloud
                )
                chatMessages[index] = responseMessage
            }
            
        } catch {
            // Remove placeholder and show error
            chatMessages.removeAll { $0.isStreaming }
            errorMessage = error.localizedDescription
        }
        
        loadingState = .idle
    }
    
    // MARK: - Terminal Context Operations (Context-Aware)
    
    /// Summarize the current terminal context
    @MainActor
    public func summarizeError(terminalBuffer: String) async {
        guard canPerformOperations else {
            errorMessage = "No AI model is configured. Open Settings to set up a provider."
            return
        }
        guard !terminalBuffer.isEmpty else {
            errorMessage = "No terminal output to summarize"
            return
        }
        
        loadingState = .packaging
        errorMessage = nil
        
        do {
            let packaged = try await ContextPackager.shared.packageContext(terminalBuffer)
            
            withAnimation {
                contextSummary = ContextSummary(
                    rawContext: terminalBuffer,
                    packagedContext: packaged
                )
                isContextExpanded = true
            }
            
        } catch {
            errorMessage = error.localizedDescription
        }
        
        loadingState = .idle
    }
    
    /// Get troubleshooting help with full session context awareness
    @MainActor
    public func troubleshoot(terminalBuffer: String, userQuery: String? = nil) async {
        guard canPerformOperations else {
            errorMessage = "No AI model is configured. Open Settings to set up a provider."
            return
        }
        loadingState = .reasoning
        errorMessage = nil
        troubleshootResponse = ""
        extractedCommands.removeAll()
        
        do {
            // Build unified context
            let unifiedContext = sessionContext?.buildContext() ?? UnifiedContext(
                terminalBuffer: terminalBuffer,
                troubleshootHistory: "",
                chatHistory: "",
                settings: .default
            )
            
            // Build system prompt for troubleshooting
            let systemPrompt = unifiedContext.buildSystemPrompt(forMode: .terminalContext)
            
            // Build messages with full context
            var messages: [ConversationMessage] = []
            
            // Add existing context
            let contextMessage = unifiedContext.buildContextMessage()
            if !contextMessage.isEmpty {
                messages.append(ConversationMessage(role: .user, content: contextMessage))
            }
            
            // Add user query
            let queryMessage: String
            if let query = userQuery, !query.isEmpty {
                queryMessage = "Based on the context above, please help me with: \(query)"
            } else {
                queryMessage = "Based on the context above, please analyze any errors or issues and suggest fixes."
            }
            messages.append(ConversationMessage(role: .user, content: queryMessage))
            
            let result = try await ProviderManager.shared.complete(
                messages: messages,
                systemPrompt: systemPrompt
            )
            
            let commands = extractCommands(from: result.content)
            
            withAnimation {
                troubleshootResponse = result.content
                extractedCommands = commands
            }
            
            // Add to troubleshooting history
            let entry = TroubleshootingEntry(
                userQuery: userQuery,
                packagedContext: contextSummary?.packagedContext ?? terminalBuffer,
                aiResponse: result.content,
                extractedCommands: commands.map { $0.command },
                isFromCloud: result.isFromCloud
            )
            sessionContext?.addTroubleshootEntry(entry)
            
        } catch {
            errorMessage = error.localizedDescription
        }
        
        loadingState = .idle
    }
    
    // MARK: - Command Extraction
    
    /// Extract commands from AI response
    private func extractCommands(from response: String) -> [ExtractedCommand] {
        var commands: [ExtractedCommand] = []
        
        // Match code blocks with optional language specifier
        let codeBlockPattern = #"```(?:bash|sh|zsh|shell)?\n?([\s\S]*?)```"#
        
        if let regex = try? NSRegularExpression(pattern: codeBlockPattern, options: []) {
            let range = NSRange(response.startIndex..., in: response)
            let matches = regex.matches(in: response, options: [], range: range)
            
            for match in matches {
                if let codeRange = Range(match.range(at: 1), in: response) {
                    let code = String(response[codeRange]).trimmingCharacters(in: .whitespacesAndNewlines)
                    
                    // Split by newlines if multiple commands
                    let lines = code.components(separatedBy: .newlines)
                        .map { $0.trimmingCharacters(in: .whitespaces) }
                        .filter { !$0.isEmpty && !$0.hasPrefix("#") }
                    
                    for line in lines {
                        commands.append(ExtractedCommand(command: line))
                    }
                }
            }
        }
        
        // Also match inline code that looks like commands
        let inlinePattern = #"`([^`]+)`"#
        if let regex = try? NSRegularExpression(pattern: inlinePattern, options: []) {
            let range = NSRange(response.startIndex..., in: response)
            let matches = regex.matches(in: response, options: [], range: range)
            
            for match in matches {
                if let codeRange = Range(match.range(at: 1), in: response) {
                    let code = String(response[codeRange]).trimmingCharacters(in: .whitespaces)
                    
                    // Only include if it looks like a command (starts with common commands)
                    let commandPrefixes = ["cd ", "ls", "mkdir", "rm ", "cp ", "mv ", "cat ", "echo ", 
                                          "npm ", "yarn ", "pnpm ", "npx ", "node ", "python", "pip ",
                                          "git ", "brew ", "cargo ", "rustc", "go ", "make", "cmake",
                                          "docker ", "kubectl ", "terraform ", "aws ", "gcloud ",
                                          "sudo ", "chmod ", "chown ", "curl ", "wget "]
                    
                    if commandPrefixes.contains(where: { code.lowercased().hasPrefix($0) }) {
                        // Avoid duplicates from code blocks
                        if !commands.contains(where: { $0.command == code }) {
                            commands.append(ExtractedCommand(command: code))
                        }
                    }
                }
            }
        }
        
        return commands
    }
    
    /// Mark a command as filled
    public func markCommandFilled(_ command: ExtractedCommand) {
        if let index = extractedCommands.firstIndex(where: { $0.id == command.id }) {
            extractedCommands[index].isFilled = true
        }
    }
}
