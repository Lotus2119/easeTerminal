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
    let refreshContext: () -> Void
    @FocusState private var isInputFocused: Bool
    @Namespace private var chatNamespace
    
    var body: some View {
        VStack(spacing: 0) {
            // Message history
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 16) {
                        if panelState.chatMessages.isEmpty {
                            emptyStateView
                        } else {
                            ForEach(panelState.chatMessages) { message in
                                ChatMessageView(message: message)
                                    .id(message.id)
                                    .transition(.asymmetric(
                                        insertion: .opacity.combined(with: .move(edge: .bottom)),
                                        removal: .opacity
                                    ))
                            }
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 20)
                }
                .scrollContentBackground(.hidden)
                .onChange(of: panelState.chatMessages.count) { _, _ in
                    // Scroll to bottom on new messages
                    if let lastMessage = panelState.chatMessages.last {
                        withAnimation(.smooth(duration: 0.3)) {
                            proxy.scrollTo(lastMessage.id, anchor: .bottom)
                        }
                    }
                }
            }
            
            // Error message if any
            if let error = panelState.errorMessage {
                ErrorBannerView(message: error) {
                    withAnimation(.smooth) {
                        panelState.clearError()
                    }
                }
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
            
            // Input area with glass effect
            chatInputArea
        }
    }
    
    // MARK: - Empty State
    
    @ViewBuilder
    private var emptyStateView: some View {
        VStack(spacing: 20) {
            // Animated sparkle icon
            ZStack {
                Circle()
                    .fill(Color.accentColor.opacity(0.1))
                    .frame(width: 80, height: 80)
                
                Image(systemName: "sparkles")
                    .font(.system(size: 36, weight: .light))
                    .foregroundStyle(Color.accentColor.opacity(0.6))
            }
            
            VStack(spacing: 10) {
                Text("Start a Conversation")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(.primary)
                
                Text("Ask questions about coding, terminal commands, debugging, or anything else.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .lineLimit(3)
            }
            .padding(.horizontal, 24)
            
            // Quick action suggestions
            VStack(spacing: 8) {
                ForEach(["Explain this error", "How do I...", "Debug my code"], id: \.self) { suggestion in
                    Button {
                        panelState.chatInput = suggestion
                        isInputFocused = true
                    } label: {
                        Text(suggestion)
                            .font(.subheadline)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 8)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                    .glassEffect(.regular.interactive(), in: .capsule)
                }
            }
            .padding(.top, 8)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.vertical, 40)
    }
    
    // MARK: - Input Area
    
    @ViewBuilder
    private var chatInputArea: some View {
        HStack(alignment: .bottom, spacing: 12) {
            // Text input with glass background
            HStack(spacing: 8) {
                TextField("Ask anything...", text: $panelState.chatInput, axis: .vertical)
                    .textFieldStyle(.plain)
                    .font(.body)
                    .lineLimit(1...6)
                    .focused($isInputFocused)
                    .onSubmit {
                        if !panelState.chatInput.isEmpty && !panelState.isLoading {
                            Task {
                                refreshContext()
                                await panelState.sendChatMessage()
                            }
                        }
                    }
                    .disabled(panelState.isLoading)
                
                // Clear input button
                if !panelState.chatInput.isEmpty && !panelState.isLoading {
                    Button {
                        withAnimation(.easeOut(duration: 0.15)) {
                            panelState.chatInput = ""
                        }
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 16))
                            .foregroundStyle(.tertiary)
                    }
                    .buttonStyle(.plain)
                    .transition(.scale.combined(with: .opacity))
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(.thinMaterial)
            )
            
            // Send button with glass effect
            Button {
                Task {
                    refreshContext()
                    await panelState.sendChatMessage()
                }
            } label: {
                ZStack {
                    if panelState.isLoading {
                        ProgressView()
                            .controlSize(.small)
                    } else {
                        Image(systemName: "arrow.up")
                            .font(.system(size: 14, weight: .semibold))
                    }
                }
                .frame(width: 36, height: 36)
            }
            .buttonStyle(.plain)
            .foregroundStyle(panelState.chatInput.isEmpty ? Color.secondary : Color.white)
            .background(
                Circle()
                    .fill(panelState.chatInput.isEmpty ? Color.secondary.opacity(0.2) : Color.accentColor)
            )
            .disabled(panelState.chatInput.isEmpty || panelState.isLoading)
            .animation(.smooth(duration: 0.2), value: panelState.chatInput.isEmpty)
            .animation(.smooth(duration: 0.2), value: panelState.isLoading)
        }
        .padding(16)
        .background(.thinMaterial)
    }
}

// MARK: - Chat Message View

struct ChatMessageView: View {
    let message: ChatMessage
    @State private var animatingDots = false
    
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            if message.role == .assistant {
                aiAvatar
                VStack(alignment: .leading, spacing: 6) {
                    messageContent
                    messageMetadata
                }
                Spacer(minLength: 20)
            } else {
                Spacer(minLength: 20)
                messageContent
                userAvatar
            }
        }
    }
    
    @ViewBuilder
    private var aiAvatar: some View {
        ZStack {
            Circle()
                .fill(
                    LinearGradient(
                        colors: [Color.accentColor, Color.accentColor.opacity(0.7)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .frame(width: 32, height: 32)
            
            Image(systemName: "sparkles")
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(.white)
        }
        .shadow(color: Color.accentColor.opacity(0.3), radius: 4, y: 2)
    }
    
    @ViewBuilder
    private var userAvatar: some View {
        ZStack {
            Circle()
                .fill(Color.secondary.opacity(0.15))
                .frame(width: 32, height: 32)
            
            Image(systemName: "person.fill")
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(.secondary)
        }
    }
    
    @ViewBuilder
    private var messageContent: some View {
        Group {
            if message.isStreaming {
                // Animated streaming indicator
                HStack(spacing: 5) {
                    ForEach(0..<3, id: \.self) { i in
                        Circle()
                            .fill(Color.accentColor.opacity(0.6))
                            .frame(width: 7, height: 7)
                            .scaleEffect(animatingDots ? 1.0 : 0.5)
                            .animation(
                                .easeInOut(duration: 0.5)
                                .repeatForever()
                                .delay(Double(i) * 0.15),
                                value: animatingDots
                            )
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 14)
                .background(messageBackground)
                .onAppear {
                    animatingDots = true
                }
            } else {
                // Message text with markdown support
                Text(LocalizedStringKey(message.content))
                    .font(.body)
                    .textSelection(.enabled)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 12)
                    .background(messageBackground)
            }
        }
    }
    
    @ViewBuilder
    private var messageMetadata: some View {
        if message.role == .assistant && !message.isStreaming {
            HStack(spacing: 6) {
                if message.isFromCloud {
                    HStack(spacing: 3) {
                        Image(systemName: "cloud.fill")
                            .font(.system(size: 9))
                        Text("Cloud")
                    }
                    .font(.caption2)
                    .foregroundStyle(.blue.opacity(0.8))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(
                        Capsule()
                            .fill(Color.blue.opacity(0.1))
                    )
                }
            }
            .padding(.leading, 4)
        }
    }
    
    @ViewBuilder
    private var messageBackground: some View {
        if message.role == .assistant {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(.thinMaterial)
                .shadow(color: .black.opacity(0.04), radius: 2, y: 1)
        } else {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [Color.accentColor.opacity(0.18), Color.accentColor.opacity(0.12)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
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
    ChatModeView(panelState: AIPanelState(), refreshContext: {})
        .frame(width: 350, height: 500)
}
