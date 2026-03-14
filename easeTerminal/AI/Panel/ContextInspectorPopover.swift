//
//  ContextInspectorPopover.swift
//  easeTerminal
//
//  Popover showing detailed session context with source toggles.
//

import SwiftUI

/// Popover showing detailed session context with toggles
struct ContextInspectorPopover: View {
    let sessionContext: SessionContext
    let onClearAll: () -> Void
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Header
            HStack {
                Text("Session Context")
                    .font(.headline)
                Spacer()
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.tertiary)
                }
                .buttonStyle(.plain)
            }
            
            Divider()
            
            // Context sources
            VStack(alignment: .leading, spacing: 12) {
                // Terminal Buffer
                ContextSourceRow(
                    icon: "terminal.fill",
                    iconColor: .green,
                    title: "Terminal Buffer",
                    detail: "\(sessionContext.terminalLineCount) lines",
                    isIncluded: sessionContext.sourceOptions.includeTerminalBuffer,
                    onToggle: {
                        sessionContext.sourceOptions.includeTerminalBuffer.toggle()
                    }
                )
                
                // Troubleshoot History
                ContextSourceRow(
                    icon: "lightbulb.fill",
                    iconColor: .yellow,
                    title: "Troubleshoot History",
                    detail: "\(sessionContext.troubleshootSessionCount) session\(sessionContext.troubleshootSessionCount != 1 ? "s" : "")",
                    isIncluded: sessionContext.sourceOptions.includeTroubleshootHistory,
                    onToggle: {
                        sessionContext.sourceOptions.includeTroubleshootHistory.toggle()
                    }
                )
                
                // Chat History
                ContextSourceRow(
                    icon: "bubble.left.and.bubble.right.fill",
                    iconColor: .blue,
                    title: "Chat History",
                    detail: "\(sessionContext.chatMessageCount) message\(sessionContext.chatMessageCount != 1 ? "s" : "")",
                    isIncluded: sessionContext.sourceOptions.includeChatHistory,
                    onToggle: {
                        sessionContext.sourceOptions.includeChatHistory.toggle()
                    }
                )
            }
            
            Divider()
            
            // Context limits info
            VStack(alignment: .leading, spacing: 6) {
                Text("Context Limits")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
                
                HStack {
                    Text("Max terminal lines:")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                    Spacer()
                    Text("\(sessionContext.settings.maxTerminalLines)")
                        .font(.caption2.weight(.medium))
                }
                
                HStack {
                    Text("Max chat exchanges:")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                    Spacer()
                    Text("\(sessionContext.settings.maxChatExchanges)")
                        .font(.caption2.weight(.medium))
                }
            }
            
            Divider()
            
            // Clear all button
            HStack {
                Spacer()
                Button(role: .destructive) {
                    onClearAll()
                    dismiss()
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "trash")
                        Text("Clear All Context")
                    }
                    .font(.caption)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
        }
        .padding(16)
        .frame(width: 300)
    }
}
