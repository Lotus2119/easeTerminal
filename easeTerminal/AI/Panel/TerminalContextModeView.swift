//
//  TerminalContextModeView.swift
//  easeTerminal
//
//  Terminal context mode UI for the core easeTerminal feature.
//  Summarize Error + Troubleshoot workflow.
//

import SwiftUI

/// Terminal context mode view - the core AI feature
struct TerminalContextModeView: View {
    @Bindable var panelState: AIPanelState
    let getTerminalBuffer: () -> String
    let fillCommand: (String) -> Void
    
    @State private var userQuery: String = ""
    @Namespace private var contextNamespace
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // Action buttons with glass effects
                actionButtonsSection
                
                // Error message if any
                if let error = panelState.errorMessage {
                    ErrorBannerView(message: error) {
                        withAnimation(.smooth) {
                            panelState.clearError()
                        }
                    }
                    .transition(.move(edge: .top).combined(with: .opacity))
                }
                
                // Context summary (collapsible)
                if panelState.contextSummary != nil {
                    contextSummarySection
                        .transition(.opacity.combined(with: .move(edge: .top)))
                }
                
                // Troubleshoot response
                if !panelState.troubleshootResponse.isEmpty {
                    troubleshootResponseSection
                        .transition(.opacity.combined(with: .move(edge: .top)))
                }
                
                // Extracted commands
                if !panelState.extractedCommands.isEmpty {
                    extractedCommandsSection
                        .transition(.opacity.combined(with: .move(edge: .top)))
                }
                
                Spacer(minLength: 20)
            }
            .padding(16)
            .animation(.smooth(duration: 0.3), value: panelState.contextSummary != nil)
            .animation(.smooth(duration: 0.3), value: panelState.troubleshootResponse.isEmpty)
            .animation(.smooth(duration: 0.3), value: panelState.extractedCommands.isEmpty)
        }
        .scrollContentBackground(.hidden)
    }
    
    // MARK: - Action Buttons Section
    
    @ViewBuilder
    private var actionButtonsSection: some View {
        VStack(spacing: 16) {
            // Primary action buttons with Liquid Glass
            GlassEffectContainer(spacing: 12) {
                HStack(spacing: 12) {
                    // Summarize Error button
                    Button {
                        Task {
                            let buffer = getTerminalBuffer()
                            await panelState.summarizeError(terminalBuffer: buffer)
                        }
                    } label: {
                        HStack(spacing: 8) {
                            if panelState.loadingState == .packaging {
                                ProgressView()
                                    .controlSize(.small)
                            } else {
                                Image(systemName: "doc.text.magnifyingglass")
                                    .font(.system(size: 15))
                            }
                            Text("Summarize")
                                .font(.subheadline.weight(.medium))
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(panelState.isLoading ? .tertiary : .primary)
                    .glassEffect(.regular.interactive(), in: .rect(cornerRadius: 12))
                    .disabled(panelState.isLoading)
                    
                    // Troubleshoot button - prominent
                    Button {
                        Task {
                            let buffer = getTerminalBuffer()
                            let query = userQuery.isEmpty ? nil : userQuery
                            await panelState.troubleshoot(terminalBuffer: buffer, userQuery: query)
                        }
                    } label: {
                        HStack(spacing: 8) {
                            if panelState.loadingState == .reasoning {
                                ProgressView()
                                    .controlSize(.small)
                            } else {
                                Image(systemName: "wand.and.stars")
                                    .font(.system(size: 15))
                            }
                            Text("Troubleshoot")
                                .font(.subheadline.weight(.semibold))
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(panelState.isLoading ? Color.secondary : Color.white)
                    .background(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(panelState.isLoading ? Color.accentColor.opacity(0.3) : Color.accentColor)
                    )
                    .disabled(panelState.isLoading)
                }
            }
            
            // Optional user query input with glass-like appearance
            HStack(spacing: 10) {
                Image(systemName: "text.bubble")
                    .font(.system(size: 14))
                    .foregroundStyle(.tertiary)
                
                TextField("Ask a specific question (optional)...", text: $userQuery)
                    .textFieldStyle(.plain)
                    .font(.subheadline)
                
                if !userQuery.isEmpty {
                    Button {
                        withAnimation(.smooth(duration: 0.15)) {
                            userQuery = ""
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
            .padding(.vertical, 12)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(.thinMaterial)
            )
            
            // Reset button (show only when there's content)
            if panelState.contextSummary != nil || !panelState.troubleshootResponse.isEmpty {
                HStack {
                    Spacer()
                    Button {
                        withAnimation(.smooth(duration: 0.25)) {
                            panelState.resetContext()
                            userQuery = ""
                        }
                    } label: {
                        HStack(spacing: 5) {
                            Image(systemName: "arrow.counterclockwise")
                                .font(.system(size: 11))
                            Text("Reset All")
                                .font(.caption.weight(.medium))
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                    .glassEffect(.regular.interactive(), in: .capsule)
                }
            }
        }
    }
    
    // MARK: - Context Summary Section
    
    @ViewBuilder
    private var contextSummarySection: some View {
        if let summary = panelState.contextSummary {
            VStack(alignment: .leading, spacing: 12) {
                // Header with collapse toggle
                Button {
                    withAnimation(.smooth(duration: 0.25)) {
                        panelState.isContextExpanded.toggle()
                    }
                } label: {
                    HStack(spacing: 10) {
                        ZStack {
                            Circle()
                                .fill(Color.purple.opacity(0.15))
                                .frame(width: 28, height: 28)
                            
                            Image(systemName: "doc.text.fill")
                                .font(.system(size: 12))
                                .foregroundStyle(.purple)
                        }
                        
                        Text("Packaged Context")
                            .font(.subheadline.weight(.medium))
                        
                        Spacer()
                        
                        Text("\(summary.packagedContext.count) chars")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(Capsule().fill(.quaternary))
                        
                        Image(systemName: panelState.isContextExpanded ? "chevron.up" : "chevron.down")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(.tertiary)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                
                // Collapsible content
                if panelState.isContextExpanded {
                    Text(summary.packagedContext)
                        .font(.system(.caption, design: .monospaced))
                        .textSelection(.enabled)
                        .padding(12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .fill(Color(nsColor: .textBackgroundColor).opacity(0.5))
                        )
                }
            }
            .padding(14)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(.thinMaterial)
            )
        }
    }
    
    // MARK: - Troubleshoot Response Section
    
    @ViewBuilder
    private var troubleshootResponseSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header
            HStack(spacing: 10) {
                ZStack {
                    Circle()
                        .fill(Color.yellow.opacity(0.2))
                        .frame(width: 28, height: 28)
                    
                    Image(systemName: "lightbulb.fill")
                        .font(.system(size: 13))
                        .foregroundStyle(.yellow)
                }
                
                Text("Analysis")
                    .font(.subheadline.weight(.semibold))
                
                Spacer()
            }
            
            // Response with markdown-like formatting
            ResponseTextView(text: panelState.troubleshootResponse)
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(.thinMaterial)
        )
    }
    
    // MARK: - Extracted Commands Section
    
    @ViewBuilder
    private var extractedCommandsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header
            HStack(spacing: 10) {
                ZStack {
                    Circle()
                        .fill(Color.blue.opacity(0.15))
                        .frame(width: 28, height: 28)
                    
                    Image(systemName: "terminal.fill")
                        .font(.system(size: 12))
                        .foregroundStyle(.blue)
                }
                
                Text("Suggested Commands")
                    .font(.subheadline.weight(.semibold))
                
                Spacer()
                
                Text("\(panelState.extractedCommands.count)")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.blue)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(
                        Capsule()
                            .fill(Color.blue.opacity(0.12))
                    )
            }
            
            VStack(spacing: 10) {
                ForEach(panelState.extractedCommands) { command in
                    CommandBlockView(
                        command: command,
                        autoFillMode: panelState.autoFillMode,
                        onCopy: {
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString(command.command, forType: .string)
                        },
                        onFill: {
                            fillCommand(command.command)
                            panelState.markCommandFilled(command)
                        }
                    )
                }
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(.thinMaterial)
        )
    }
}

// MARK: - Response Text View

/// Displays AI response with basic formatting
struct ResponseTextView: View {
    let text: String
    
    var body: some View {
        Text(LocalizedStringKey(text))
            .font(.body)
            .lineSpacing(4)
            .textSelection(.enabled)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - Command Block View

/// Individual command block with copy and fill buttons
struct CommandBlockView: View {
    let command: ExtractedCommand
    let autoFillMode: AutoFillMode
    let onCopy: () -> Void
    let onFill: () -> Void
    
    @State private var showCopied = false
    @State private var isHovering = false
    
    var body: some View {
        HStack(spacing: 12) {
            // Terminal prompt indicator
            Text("$")
                .font(.system(.subheadline, design: .monospaced, weight: .bold))
                .foregroundStyle(.tertiary)
            
            // Command text
            Text(command.command)
                .font(.system(.subheadline, design: .monospaced))
                .lineLimit(2)
                .frame(maxWidth: .infinity, alignment: .leading)
            
            // Status indicator
            if command.isFilled {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                    .font(.system(size: 16))
                    .transition(.scale.combined(with: .opacity))
            } else {
                // Action buttons
                HStack(spacing: 6) {
                    // Copy button
                    Button {
                        onCopy()
                        withAnimation(.easeOut(duration: 0.15)) {
                            showCopied = true
                        }
                        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                            withAnimation(.easeOut(duration: 0.15)) {
                                showCopied = false
                            }
                        }
                    } label: {
                        Image(systemName: showCopied ? "checkmark" : "doc.on.doc")
                            .font(.system(size: 12))
                            .frame(width: 28, height: 28)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(showCopied ? .green : .secondary)
                    .background(
                        Circle()
                            .fill(.quaternary)
                    )
                    .help("Copy to clipboard")
                    
                    // Fill button
                    Button {
                        withAnimation(.smooth) {
                            onFill()
                        }
                    } label: {
                        Image(systemName: "arrow.right")
                            .font(.system(size: 12, weight: .semibold))
                            .frame(width: 28, height: 28)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.white)
                    .background(
                        Circle()
                            .fill(Color.accentColor)
                    )
                    .help("Fill into terminal")
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color(nsColor: .textBackgroundColor).opacity(0.6))
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(.quaternary, lineWidth: 1)
                )
        )
        .animation(.smooth(duration: 0.2), value: command.isFilled)
    }
}

#Preview {
    TerminalContextModeView(
        panelState: AIPanelState(),
        getTerminalBuffer: { "$ npm install\nnpm ERR! code ENOENT" },
        fillCommand: { _ in }
    )
    .frame(width: 350, height: 600)
}
