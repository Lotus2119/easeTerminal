//
//  ChatMessageView.swift
//  easeTerminal
//
//  Renders a single chat message bubble with avatar and metadata.
//

import SwiftUI

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
