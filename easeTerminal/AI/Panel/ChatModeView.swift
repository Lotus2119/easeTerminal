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

#Preview {
    ChatModeView(panelState: AIPanelState(), refreshContext: {})
        .frame(width: 350, height: 500)
}
