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
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                // Action buttons
                actionButtonsSection
                
                // Error message if any
                if let error = panelState.errorMessage {
                    ErrorBannerView(message: error) {
                        panelState.clearError()
                    }
                }
                
                // Context summary (collapsible)
                if panelState.contextSummary != nil {
                    contextSummarySection
                }
                
                // Troubleshoot response
                if !panelState.troubleshootResponse.isEmpty {
                    troubleshootResponseSection
                }
                
                // Extracted commands
                if !panelState.extractedCommands.isEmpty {
                    extractedCommandsSection
                }
                
                Spacer(minLength: 20)
            }
            .padding()
        }
    }
    
    // MARK: - Action Buttons Section
    
    @ViewBuilder
    private var actionButtonsSection: some View {
        VStack(spacing: 12) {
            // Primary action buttons
            HStack(spacing: 10) {
                // Summarize Error button
                Button {
                    Task {
                        let buffer = getTerminalBuffer()
                        await panelState.summarizeError(terminalBuffer: buffer)
                    }
                } label: {
                    HStack(spacing: 6) {
                        if panelState.loadingState == .packaging {
                            ProgressView()
                                .controlSize(.small)
                        } else {
                            Image(systemName: "doc.text.magnifyingglass")
                        }
                        Text("Summarize")
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .controlSize(.regular)
                .disabled(panelState.isLoading)
                
                // Troubleshoot button
                Button {
                    Task {
                        let buffer = getTerminalBuffer()
                        let query = userQuery.isEmpty ? nil : userQuery
                        await panelState.troubleshoot(terminalBuffer: buffer, userQuery: query)
                    }
                } label: {
                    HStack(spacing: 6) {
                        if panelState.loadingState == .reasoning {
                            ProgressView()
                                .controlSize(.small)
                        } else {
                            Image(systemName: "wand.and.stars")
                        }
                        Text("Troubleshoot")
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.regular)
                .disabled(panelState.isLoading)
            }
            
            // Optional user query input
            HStack(spacing: 8) {
                TextField("Ask a specific question (optional)...", text: $userQuery)
                    .textFieldStyle(.plain)
                    .font(.callout)
                
                if !userQuery.isEmpty {
                    Button {
                        withAnimation(.easeOut(duration: 0.15)) {
                            userQuery = ""
                        }
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.tertiary)
                    }
                    .buttonStyle(.borderless)
                }
            }
            .padding(10)
            .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 8))
            
            // Reset button (show only when there's content)
            if panelState.contextSummary != nil || !panelState.troubleshootResponse.isEmpty {
                HStack {
                    Spacer()
                    Button {
                        withAnimation(.easeOut(duration: 0.2)) {
                            panelState.resetContext()
                            userQuery = ""
                        }
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "arrow.counterclockwise")
                            Text("Reset")
                        }
                        .font(.caption)
                    }
                    .buttonStyle(.borderless)
                    .foregroundStyle(.secondary)
                }
            }
        }
    }
    
    // MARK: - Context Summary Section
    
    @ViewBuilder
    private var contextSummarySection: some View {
        if let summary = panelState.contextSummary {
            VStack(alignment: .leading, spacing: 8) {
                // Header with collapse toggle
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        panelState.isContextExpanded.toggle()
                    }
                } label: {
                    HStack {
                        Image(systemName: panelState.isContextExpanded ? "chevron.down" : "chevron.right")
                            .font(.caption)
                            .frame(width: 16)
                        
                        Text("Packaged Context")
                            .font(.subheadline.weight(.medium))
                        
                        Spacer()
                        
                        Text("\(summary.packagedContext.count) chars")
                            .font(.caption2)
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
                        .padding(10)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 6))
                }
            }
            .padding(12)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 10))
        }
    }
    
    // MARK: - Troubleshoot Response Section
    
    @ViewBuilder
    private var troubleshootResponseSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: "lightbulb.fill")
                    .foregroundStyle(.yellow)
                Text("Analysis")
                    .font(.subheadline.weight(.medium))
                Spacer()
            }
            
            // Response with markdown-like formatting
            ResponseTextView(text: panelState.troubleshootResponse)
        }
        .padding(12)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 10))
    }
    
    // MARK: - Extracted Commands Section
    
    @ViewBuilder
    private var extractedCommandsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: "terminal.fill")
                    .foregroundStyle(.blue)
                Text("Extracted Commands")
                    .font(.subheadline.weight(.medium))
                Spacer()
                
                Text("\(panelState.extractedCommands.count)")
                    .font(.caption)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(.blue.opacity(0.2), in: Capsule())
            }
            
            VStack(spacing: 8) {
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
        .padding(12)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 10))
    }
}

// MARK: - Response Text View

/// Displays AI response with basic formatting
struct ResponseTextView: View {
    let text: String
    
    var body: some View {
        Text(LocalizedStringKey(text))
            .font(.callout)
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
    
    var body: some View {
        HStack(spacing: 8) {
            // Command text
            Text(command.command)
                .font(.system(.caption, design: .monospaced))
                .lineLimit(2)
                .frame(maxWidth: .infinity, alignment: .leading)
            
            // Status indicator
            if command.isFilled {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                    .font(.caption)
            }
            
            // Copy button
            Button {
                onCopy()
                showCopied = true
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                    showCopied = false
                }
            } label: {
                Image(systemName: showCopied ? "checkmark" : "doc.on.doc")
                    .font(.caption)
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .help("Copy to clipboard")
            
            // Fill button
            Button {
                onFill()
            } label: {
                Image(systemName: "arrow.right.circle.fill")
                    .font(.caption)
            }
            .buttonStyle(.plain)
            .foregroundStyle(.blue)
            .disabled(command.isFilled)
            .help("Fill into terminal")
        }
        .padding(10)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 8))
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
