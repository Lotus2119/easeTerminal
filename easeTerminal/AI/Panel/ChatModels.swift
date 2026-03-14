//
//  ChatModels.swift
//  easeTerminal
//
//  Data models shared across Chat and Terminal Context modes.
//

import Foundation

// MARK: - Chat Message

/// A message in the chat conversation
public struct ChatMessage: Identifiable, Equatable, Codable {
    public let id: UUID
    public let role: ConversationMessage.Role
    public let content: String
    public let timestamp: Date
    public let isStreaming: Bool
    public let isFromCloud: Bool
    
    public init(
        id: UUID = UUID(),
        role: ConversationMessage.Role,
        content: String,
        timestamp: Date = Date(),
        isStreaming: Bool = false,
        isFromCloud: Bool = false
    ) {
        self.id = id
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
