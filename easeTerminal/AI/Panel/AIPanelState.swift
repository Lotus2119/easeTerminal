//
//  AIPanelState.swift
//  easeTerminal
//
//  State management for the AI side panel.
//  Handles both Chat and Terminal Context modes.
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

// MARK: - Chat Message

/// A message in the chat conversation
public struct ChatMessage: Identifiable, Equatable {
    public let id = UUID()
    public let role: ConversationMessage.Role
    public let content: String
    public let timestamp: Date
    public let isStreaming: Bool
    public let isFromCloud: Bool
    
    public init(
        role: ConversationMessage.Role,
        content: String,
        timestamp: Date = Date(),
        isStreaming: Bool = false,
        isFromCloud: Bool = false
    ) {
        self.role = role
        self.content = content
        self.timestamp = timestamp
        self.isStreaming = isStreaming
        self.isFromCloud = isFromCloud
    }
    
    /// Convert to ConversationMessage for API calls
    func toConversationMessage() -> ConversationMessage {
        ConversationMessage(role: role, content: content)
    }
}

// MARK: - Extracted Command

/// A command extracted from AI response
public struct ExtractedCommand: Identifiable, Equatable {
    public let id = UUID()
    public let command: String
    public let explanation: String?
    public var isFilled: Bool = false
    
    public init(command: String, explanation: String? = nil) {
        self.command = command
        self.explanation = explanation
    }
}

// MARK: - Context Summary

/// Packaged context from terminal output
public struct ContextSummary: Equatable {
    public let rawContext: String
    public let packagedContext: String
    public let timestamp: Date
    
    public init(rawContext: String, packagedContext: String) {
        self.rawContext = rawContext
        self.packagedContext = packagedContext
        self.timestamp = Date()
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

/// Observable state for the AI side panel
@Observable
public final class AIPanelState {
    
    // MARK: - Panel Visibility & Mode
    
    /// Whether the panel is visible
    public var isPanelVisible: Bool = false {
        didSet {
            UserDefaults.standard.set(isPanelVisible, forKey: "aiPanel.visible")
        }
    }
    
    /// Current panel mode (chat or terminal context)
    public var currentMode: AIPanelMode = .terminalContext
    
    // MARK: - Chat State
    
    /// Chat message history
    public var chatMessages: [ChatMessage] = []
    
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
    
    // MARK: - Initialization
    
    public init() {
        // Load saved visibility state
        isPanelVisible = UserDefaults.standard.bool(forKey: "aiPanel.visible")
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
    
    /// Clear error
    public func clearError() {
        errorMessage = nil
    }
    
    // MARK: - Chat Operations
    
    /// Send a chat message
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
            // Build conversation history
            let history = chatMessages
                .dropLast() // Exclude the placeholder
                .map { $0.toConversationMessage() }
            
            let result = try await ProviderManager.shared.complete(
                messages: Array(history),
                systemPrompt: "You are a helpful AI assistant integrated into a terminal application. Help users with coding, commands, and general questions."
            )
            
            // Replace placeholder with actual response
            if let index = chatMessages.lastIndex(where: { $0.isStreaming }) {
                chatMessages[index] = ChatMessage(
                    role: .assistant,
                    content: result.content,
                    isFromCloud: result.isFromCloud
                )
            }
            
        } catch {
            // Remove placeholder and show error
            chatMessages.removeAll { $0.isStreaming }
            errorMessage = error.localizedDescription
        }
        
        loadingState = .idle
    }
    
    // MARK: - Terminal Context Operations
    
    /// Summarize the current terminal context
    @MainActor
    public func summarizeError(terminalBuffer: String) async {
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
    
    /// Get troubleshooting help for the current context
    @MainActor
    public func troubleshoot(terminalBuffer: String, userQuery: String? = nil) async {
        loadingState = .reasoning
        errorMessage = nil
        troubleshootResponse = ""
        extractedCommands.removeAll()
        
        do {
            let result = try await ProviderManager.shared.reason(
                terminalContext: terminalBuffer,
                userQuery: userQuery
            )
            
            withAnimation {
                troubleshootResponse = result.content
                extractedCommands = extractCommands(from: result.content)
            }
            
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
