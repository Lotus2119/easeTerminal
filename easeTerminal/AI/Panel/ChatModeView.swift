//
//  ChatModeView.swift
//  easeTerminal
//
//  Chat mode UI for direct conversation with the AI.
//  Maintains conversation history for the session.
//

import SwiftUI

/// Chat mode view with message history and input
struct ChatModeView: View {
    @Bindable var panelState: AIPanelState
    @FocusState private var isInputFocused: Bool
    
    var body: some View {
        VStack(spacing: 0) {
            // Message history
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 12) {
                        if panelState.chatMessages.isEmpty {
                            emptyStateView
                        } else {
                            ForEach(panelState.chatMessages) { message in
                                ChatMessageView(message: message)
                                    .id(message.id)
                            }
                        }
                    }
                    .padding()
                }
                .onChange(of: panelState.chatMessages.count) { _, _ in
                    // Scroll to bottom on new messages
                    if let lastMessage = panelState.chatMessages.last {
                        withAnimation(.easeOut(duration: 0.2)) {
                            proxy.scrollTo(lastMessage.id, anchor: .bottom)
                        }
                    }
                }
            }
            
            Divider()
            
            // Error message if any
            if let error = panelState.errorMessage {
                ErrorBannerView(message: error) {
                    panelState.clearError()
                }
            }
            
            // Input area
            chatInputArea
        }
    }
    
    // MARK: - Empty State
    
    @ViewBuilder
    private var emptyStateView: some View {
        VStack(spacing: 16) {
            Image(systemName: "bubble.left.and.bubble.right")
                .font(.system(size: 40, weight: .light))
                .foregroundStyle(.quaternary)
            
            VStack(spacing: 8) {
                Text("Start a Conversation")
                    .font(.headline)
                    .foregroundStyle(.secondary)
                
                Text("Ask questions about coding, terminal commands, or anything else.")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .multilineTextAlignment(.center)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.vertical, 60)
    }
    
    // MARK: - Input Area
    
    @ViewBuilder
    private var chatInputArea: some View {
        HStack(alignment: .bottom, spacing: 10) {
            // Text input
            TextField("Ask a question...", text: $panelState.chatInput, axis: .vertical)
                .textFieldStyle(.plain)
                .lineLimit(1...5)
                .focused($isInputFocused)
                .onSubmit {
                    if !panelState.chatInput.isEmpty && !panelState.isLoading {
                        Task {
                            await panelState.sendChatMessage()
                        }
                    }
                }
                .disabled(panelState.isLoading)
            
            // Send button
            Button {
                Task {
                    await panelState.sendChatMessage()
                }
            } label: {
                Group {
                    if panelState.isLoading {
                        ProgressView()
                            .controlSize(.small)
                    } else {
                        Image(systemName: "arrow.up.circle.fill")
                            .font(.title2)
                    }
                }
                .frame(width: 26, height: 26)
            }
            .buttonStyle(.borderless)
            .foregroundStyle(panelState.chatInput.isEmpty ? Color.secondary : Color.accentColor)
            .disabled(panelState.chatInput.isEmpty || panelState.isLoading)
            .animation(.easeInOut(duration: 0.15), value: panelState.chatInput.isEmpty)
        }
        .padding(12)
        .background(.regularMaterial)
    }
}

// MARK: - Chat Message View

struct ChatMessageView: View {
    let message: ChatMessage
    
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            if message.role == .assistant {
                // AI avatar
                aiAvatar
                messageContent
                Spacer(minLength: 40)
            } else {
                Spacer(minLength: 40)
                messageContent
                userAvatar
            }
        }
    }
    
    @ViewBuilder
    private var aiAvatar: some View {
        ZStack {
            Circle()
                .fill(Color.accentColor.gradient)
                .frame(width: 28, height: 28)
            
            Image(systemName: "sparkle")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(.white)
        }
    }
    
    @ViewBuilder
    private var userAvatar: some View {
        ZStack {
            Circle()
                .fill(.secondary.opacity(0.3))
                .frame(width: 28, height: 28)
            
            Image(systemName: "person.fill")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(.secondary)
        }
    }
    
    @ViewBuilder
    private var messageContent: some View {
        VStack(alignment: message.role == .assistant ? .leading : .trailing, spacing: 4) {
            if message.isStreaming {
                // Streaming indicator
                HStack(spacing: 4) {
                    ForEach(0..<3) { i in
                        Circle()
                            .fill(.secondary)
                            .frame(width: 6, height: 6)
                            .opacity(0.5)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .background(messageBackground)
            } else {
                // Message text with markdown support
                Text(LocalizedStringKey(message.content))
                    .textSelection(.enabled)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .background(messageBackground)
                
                // Cloud indicator for assistant messages
                if message.role == .assistant && message.isFromCloud {
                    HStack(spacing: 4) {
                        Image(systemName: "cloud.fill")
                        Text("Cloud")
                    }
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                }
            }
        }
    }
    
    @ViewBuilder
    private var messageBackground: some View {
        if message.role == .assistant {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(.regularMaterial)
        } else {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color.accentColor.opacity(0.12))
        }
    }
}

// MARK: - Error Banner

struct ErrorBannerView: View {
    let message: String
    let onDismiss: () -> Void
    
    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
            
            Text(message)
                .font(.caption)
                .lineLimit(2)
            
            Spacer()
            
            Button {
                onDismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.caption)
            }
            .buttonStyle(.plain)
        }
        .padding(10)
        .background(.orange.opacity(0.1), in: RoundedRectangle(cornerRadius: 8))
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }
}

#Preview {
    ChatModeView(panelState: AIPanelState())
        .frame(width: 350, height: 500)
}
