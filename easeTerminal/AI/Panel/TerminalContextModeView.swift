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
    let sessionContext: SessionContext
    let getTerminalBuffer: () -> String
    let fillCommand: (String) -> Void
    
    @State private var userQuery: String = ""
    @Namespace private var contextNamespace
    
    /// Refresh terminal buffer in session context before AI operations
    private func refreshTerminalContext() {
        let content = getTerminalBuffer()
        sessionContext.updateTerminalBuffer(content)
    }
    
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
                        .contentShape(RoundedRectangle(cornerRadius: 12))
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(panelState.isLoading ? .tertiary : .primary)
                    .glassEffect(.regular.interactive(), in: .rect(cornerRadius: 12))
                    .disabled(panelState.isLoading)
                    
                    // Troubleshoot button - prominent
                    Button {
                        Task {
                            // Refresh context first to ensure we have latest terminal output
                            refreshTerminalContext()
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
                        .contentShape(RoundedRectangle(cornerRadius: 12))
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

/// Displays AI response with structured formatting
struct ResponseTextView: View {
    let text: String
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            ForEach(Array(parseResponseSections().enumerated()), id: \.offset) { index, section in
                ResponseSectionView(section: section)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
    
    /// Parse the response text into structured sections
    private func parseResponseSections() -> [ResponseSection] {
        var sections: [ResponseSection] = []
        let lines = text.components(separatedBy: "\n")
        
        var currentSection: ResponseSection?
        var currentContent: [String] = []
        
        for line in lines {
            // Check for markdown headers (## or ###)
            if line.hasPrefix("## ") {
                // Save previous section
                if let section = currentSection {
                    var s = section
                    s.content = currentContent.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
                    if !s.content.isEmpty || !s.title.isEmpty {
                        sections.append(s)
                    }
                }
                // Start new section
                let title = String(line.dropFirst(3)).trimmingCharacters(in: .whitespaces)
                currentSection = ResponseSection(title: title, icon: iconForSection(title), color: colorForSection(title))
                currentContent = []
            } else if line.hasPrefix("### ") {
                // Subsection - treat as bold text in content
                let subtitle = String(line.dropFirst(4)).trimmingCharacters(in: .whitespaces)
                currentContent.append("**\(subtitle)**")
            } else {
                currentContent.append(line)
            }
        }
        
        // Save last section
        if let section = currentSection {
            var s = section
            s.content = currentContent.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
            if !s.content.isEmpty {
                sections.append(s)
            }
        } else if !currentContent.isEmpty {
            // No sections found, treat entire content as one section
            let content = currentContent.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
            if !content.isEmpty {
                sections.append(ResponseSection(title: "", icon: "text.alignleft", color: .secondary, content: content))
            }
        }
        
        return sections
    }
    
    private func iconForSection(_ title: String) -> String {
        let lowercased = title.lowercased()
        if lowercased.contains("issue") || lowercased.contains("error") || lowercased.contains("problem") {
            return "exclamationmark.triangle.fill"
        } else if lowercased.contains("analysis") {
            return "magnifyingglass"
        } else if lowercased.contains("solution") || lowercased.contains("fix") {
            return "checkmark.circle.fill"
        } else if lowercased.contains("note") || lowercased.contains("additional") {
            return "info.circle.fill"
        } else if lowercased.contains("enhancement") || lowercased.contains("optional") || lowercased.contains("tip") {
            return "lightbulb.fill"
        } else if lowercased.contains("command") {
            return "terminal.fill"
        } else {
            return "doc.text.fill"
        }
    }
    
    private func colorForSection(_ title: String) -> Color {
        let lowercased = title.lowercased()
        if lowercased.contains("issue") || lowercased.contains("error") || lowercased.contains("problem") {
            return .red
        } else if lowercased.contains("analysis") {
            return .purple
        } else if lowercased.contains("solution") || lowercased.contains("fix") {
            return .green
        } else if lowercased.contains("note") || lowercased.contains("additional") {
            return .blue
        } else if lowercased.contains("enhancement") || lowercased.contains("optional") || lowercased.contains("tip") {
            return .yellow
        } else {
            return .secondary
        }
    }
}

/// A parsed section from the AI response
struct ResponseSection: Identifiable {
    let id = UUID()
    var title: String
    var icon: String
    var color: Color
    var content: String = ""
}

/// View for a single response section
struct ResponseSectionView: View {
    let section: ResponseSection
    
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Section header (if has title)
            if !section.title.isEmpty {
                HStack(spacing: 8) {
                    Image(systemName: section.icon)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(section.color)
                    
                    Text(section.title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)
                }
                .padding(.bottom, 2)
            }
            
            // Section content
            FormattedContentView(content: section.content)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(section.color.opacity(0.06))
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .strokeBorder(section.color.opacity(0.15), lineWidth: 1)
                )
        )
    }
}

/// View for formatted content within a section
struct FormattedContentView: View {
    let content: String
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(Array(parseContent().enumerated()), id: \.offset) { _, element in
                switch element {
                case .text(let text):
                    Text(LocalizedStringKey(text))
                        .font(.callout)
                        .lineSpacing(3)
                        .textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)
                    
                case .bulletPoint(let text):
                    HStack(alignment: .top, spacing: 8) {
                        Text("•")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                        Text(LocalizedStringKey(text))
                            .font(.callout)
                            .lineSpacing(3)
                            .textSelection(.enabled)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    
                case .codeBlock(let code):
                    Text(code)
                        .font(.system(.caption, design: .monospaced))
                        .padding(10)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .fill(Color(nsColor: .textBackgroundColor).opacity(0.8))
                        )
                        .textSelection(.enabled)
                }
            }
        }
    }
    
    enum ContentElement {
        case text(String)
        case bulletPoint(String)
        case codeBlock(String)
    }
    
    private func parseContent() -> [ContentElement] {
        var elements: [ContentElement] = []
        let lines = content.components(separatedBy: "\n")
        
        var inCodeBlock = false
        var codeLines: [String] = []
        var textBuffer: [String] = []
        
        for line in lines {
            if line.hasPrefix("```") {
                // Toggle code block
                if inCodeBlock {
                    // End code block
                    elements.append(.codeBlock(codeLines.joined(separator: "\n")))
                    codeLines = []
                    inCodeBlock = false
                } else {
                    // Start code block, flush text buffer first
                    if !textBuffer.isEmpty {
                        let text = textBuffer.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
                        if !text.isEmpty {
                            elements.append(.text(text))
                        }
                        textBuffer = []
                    }
                    inCodeBlock = true
                }
            } else if inCodeBlock {
                codeLines.append(line)
            } else if line.trimmingCharacters(in: .whitespaces).hasPrefix("- ") {
                // Bullet point - flush text buffer first
                if !textBuffer.isEmpty {
                    let text = textBuffer.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
                    if !text.isEmpty {
                        elements.append(.text(text))
                    }
                    textBuffer = []
                }
                let bulletText = String(line.trimmingCharacters(in: .whitespaces).dropFirst(2))
                elements.append(.bulletPoint(bulletText))
            } else {
                textBuffer.append(line)
            }
        }
        
        // Flush remaining
        if inCodeBlock && !codeLines.isEmpty {
            elements.append(.codeBlock(codeLines.joined(separator: "\n")))
        } else if !textBuffer.isEmpty {
            let text = textBuffer.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
            if !text.isEmpty {
                elements.append(.text(text))
            }
        }
        
        return elements
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
                        Task {
                            try? await Task.sleep(for: .seconds(1.5))
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
        sessionContext: SessionContext(),
        getTerminalBuffer: { "$ npm install\nnpm ERR! code ENOENT" },
        fillCommand: { _ in }
    )
    .frame(width: 350, height: 600)
}
