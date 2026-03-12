//
//  OllamaOnboardingView.swift
//  easeTerminal
//
//  Onboarding view shown when Ollama is not installed or no models are available.
//  Provides clear instructions for getting started with local AI.
//

import SwiftUI

/// Onboarding view for Ollama setup
struct OllamaOnboardingView: View {
    @State private var checkingStatus = false
    @State private var ollamaStatus: OllamaSetupStatus = .checking
    
    private var providerManager: ProviderManager { ProviderManager.shared }
    
    enum OllamaSetupStatus {
        case checking
        case notInstalled
        case notRunning
        case noModels
        case ready
        
        var title: String {
            switch self {
            case .checking: return "Checking Ollama..."
            case .notInstalled: return "Install Ollama"
            case .notRunning: return "Start Ollama"
            case .noModels: return "Pull a Model"
            case .ready: return "Ready to Go!"
            }
        }
        
        var description: String {
            switch self {
            case .checking:
                return "Checking your local AI setup..."
            case .notInstalled:
                return "easeTerminal uses Ollama for local AI inference. Install it to get started with fully private, offline AI assistance."
            case .notRunning:
                return "Ollama is installed but not running. Start the Ollama app or run the serve command."
            case .noModels:
                return "Ollama is running but no models are installed. Pull the recommended model to get started."
            case .ready:
                return "Your local AI is ready! You can now get intelligent help with terminal commands and troubleshooting."
            }
        }
    }
    
    var body: some View {
        VStack(spacing: 32) {
            // Header
            VStack(spacing: 16) {
                Image(systemName: statusIcon)
                    .font(.system(size: 64, weight: .light))
                    .foregroundStyle(statusColor)
                    .symbolEffect(.pulse, isActive: checkingStatus)
                
                Text(ollamaStatus.title)
                    .font(.title.weight(.semibold))
                
                Text(ollamaStatus.description)
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 400)
            }
            
            // Setup instructions
            if ollamaStatus != .checking && ollamaStatus != .ready {
                setupInstructions
            }
            
            // Action buttons
            actionButtons
        }
        .padding(40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(nsColor: .windowBackgroundColor))
        .task {
            await checkOllamaStatus()
        }
    }
    
    private var statusIcon: String {
        switch ollamaStatus {
        case .checking: return "magnifyingglass"
        case .notInstalled: return "arrow.down.circle"
        case .notRunning: return "play.circle"
        case .noModels: return "square.and.arrow.down"
        case .ready: return "checkmark.circle.fill"
        }
    }
    
    private var statusColor: Color {
        switch ollamaStatus {
        case .checking: return .blue
        case .notInstalled, .notRunning, .noModels: return .orange
        case .ready: return .green
        }
    }
    
    @ViewBuilder
    private var setupInstructions: some View {
        VStack(alignment: .leading, spacing: 16) {
            switch ollamaStatus {
            case .notInstalled:
                instructionStep(
                    number: 1,
                    title: "Install Ollama via Homebrew",
                    command: "brew install ollama"
                )
                
                instructionStep(
                    number: 2,
                    title: "Pull the recommended model",
                    command: "ollama pull qwen3-coder:30b"
                )
                
                Text("Or download Ollama.app from ollama.com")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                
            case .notRunning:
                instructionStep(
                    number: 1,
                    title: "Start Ollama",
                    command: "ollama serve"
                )
                
                Text("Or launch Ollama.app from your Applications folder")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                
            case .noModels:
                instructionStep(
                    number: 1,
                    title: "Pull the recommended model",
                    command: "ollama pull qwen3-coder:30b"
                )
                
                VStack(alignment: .leading, spacing: 8) {
                    Text("Why Qwen3-Coder 30B?")
                        .font(.subheadline.weight(.medium))
                    
                    VStack(alignment: .leading, spacing: 4) {
                        bulletPoint("Purpose-built for coding and terminal tasks")
                        bulletPoint("MoE architecture: only 3.3B active params = fast inference")
                        bulletPoint("Fits in 24GB unified memory on Apple Silicon")
                        bulletPoint("No internet or API key required")
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
                .padding(.top, 8)
                
            default:
                EmptyView()
            }
        }
        .padding(24)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
    }
    
    private func instructionStep(number: Int, title: String, command: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Text("\(number)")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.white)
                    .frame(width: 20, height: 20)
                    .background(Circle().fill(.blue))
                
                Text(title)
                    .font(.subheadline.weight(.medium))
            }
            
            HStack {
                Text(command)
                    .font(.system(.body, design: .monospaced))
                    .foregroundStyle(.primary)
                
                Spacer()
                
                Button {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(command, forType: .string)
                } label: {
                    Image(systemName: "doc.on.doc")
                        .font(.caption)
                }
                .buttonStyle(.plain)
                .help("Copy to clipboard")
            }
            .padding(12)
            .background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: 8))
        }
    }
    
    private func bulletPoint(_ text: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Text("•")
            Text(text)
        }
    }
    
    @ViewBuilder
    private var actionButtons: some View {
        HStack(spacing: 16) {
            if ollamaStatus == .ready {
                Button("Get Started") {
                    // Dismiss onboarding - handled by parent
                }
                .buttonStyle(.borderedProminent)
            } else {
                Button {
                    Task {
                        await checkOllamaStatus()
                    }
                } label: {
                    HStack(spacing: 8) {
                        if checkingStatus {
                            ProgressView()
                                .controlSize(.small)
                        } else {
                            Image(systemName: "arrow.clockwise")
                        }
                        Text("Check Again")
                    }
                }
                .buttonStyle(.bordered)
                .disabled(checkingStatus)
            }
        }
    }
    
    private func checkOllamaStatus() async {
        checkingStatus = true
        ollamaStatus = .checking
        
        // Refresh provider status
        await providerManager.refreshLocalProvider()
        
        // Determine status
        switch providerManager.localStatus {
        case .notInstalled:
            ollamaStatus = .notInstalled
        case .noModels:
            ollamaStatus = .noModels
        case .ready:
            ollamaStatus = .ready
        case .disconnected, .error:
            // Could be not running
            if let provider = providerManager.localProvider {
                let isRunning = await provider.isServerRunning()
                ollamaStatus = isRunning ? .noModels : .notRunning
            } else {
                ollamaStatus = .notInstalled
            }
        case .connecting:
            ollamaStatus = .checking
        }
        
        checkingStatus = false
    }
}

#Preview {
    OllamaOnboardingView()
        .frame(width: 600, height: 500)
}
