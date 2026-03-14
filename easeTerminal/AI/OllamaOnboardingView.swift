//
//  OllamaOnboardingView.swift
//  easeTerminal
//
//  Onboarding view shown when the local inference provider is not set up.
//  Adapts its instructions to whichever local provider is currently selected.
//

import SwiftUI

/// Onboarding view for local provider setup.
/// Adapts to the active provider (Ollama, LM Studio, etc.)
struct LocalProviderOnboardingView: View {
    @Environment(\.providerManager) private var providerManager
    @State private var checkingStatus = false
    @State private var setupStatus: LocalSetupStatus = .checking

    enum LocalSetupStatus: Equatable {
        case checking
        case notDetected
        case notRunning
        case noModels
        case ready

        var title: String {
            switch self {
            case .checking:      "Checking..."
            case .notDetected:   "Not Detected"
            case .notRunning:    "Start the Server"
            case .noModels:      "Load a Model"
            case .ready:         "Ready to Go!"
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

                Text(setupStatus.title)
                    .font(.title.weight(.semibold))

                Text(statusDescription)
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 400)
            }

            // Setup instructions
            if setupStatus != .checking && setupStatus != .ready {
                setupInstructions
            }

            // Action buttons
            actionButtons
        }
        .padding(40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(nsColor: .windowBackgroundColor))
        .task {
            await checkStatus()
        }
    }

    // MARK: - Computed

    private var isOllama: Bool {
        providerManager.selectedLocalProviderID == OllamaProvider.providerID
    }

    private var providerName: String {
        isOllama ? "Ollama" : "LM Studio"
    }

    private var statusDescription: String {
        switch setupStatus {
        case .checking:
            return "Checking your local AI setup..."
        case .notDetected:
            if isOllama {
                return "easeTerminal uses Ollama for local AI inference. Install it to get started with fully private, offline AI assistance."
            }
            return "easeTerminal can use LM Studio for local AI inference. Install LM Studio and enable its local server to get started."
        case .notRunning:
            if isOllama {
                return "Ollama is installed but not running. Start the Ollama app or run the serve command."
            }
            return "LM Studio is installed but its local server is not running. Open LM Studio and start the server in the Local Server tab."
        case .noModels:
            if isOllama {
                return "Ollama is running but no models are installed. Pull the recommended model to get started."
            }
            return "LM Studio is running but no model is loaded. Open LM Studio and load a model in the Local Server tab."
        case .ready:
            return "Your local AI is ready! You can now get intelligent help with terminal commands and troubleshooting."
        }
    }

    private var statusIcon: String {
        switch setupStatus {
        case .checking:     "magnifyingglass"
        case .notDetected: "arrow.down.circle"
        case .notRunning:   "play.circle"
        case .noModels:     "square.and.arrow.down"
        case .ready:        "checkmark.circle.fill"
        }
    }

    private var statusColor: Color {
        switch setupStatus {
        case .checking:                          .blue
        case .notDetected, .notRunning, .noModels: .orange
        case .ready:                             .green
        }
    }

    // MARK: - Setup Instructions

    @ViewBuilder
    private var setupInstructions: some View {
        VStack(alignment: .leading, spacing: 16) {
            if isOllama {
                ollamaInstructions
            } else {
                lmStudioInstructions
            }
        }
        .padding(24)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
    }

    @ViewBuilder
    private var ollamaInstructions: some View {
        switch setupStatus {
        case .notDetected:
            instructionStep(number: 1, title: "Install Ollama via Homebrew", command: "brew install ollama")
            instructionStep(number: 2, title: "Pull the recommended model", command: "ollama pull qwen3-coder:30b")
            Text("Or download Ollama.app from ollama.com")
                .font(.caption)
                .foregroundStyle(.secondary)

        case .notRunning:
            instructionStep(number: 1, title: "Start Ollama", command: "ollama serve")
            Text("Or launch Ollama.app from your Applications folder")
                .font(.caption)
                .foregroundStyle(.secondary)

        case .noModels:
            instructionStep(number: 1, title: "Pull the recommended model", command: "ollama pull qwen3-coder:30b")
            modelRecommendationNote

        default:
            EmptyView()
        }
    }

    @ViewBuilder
    private var lmStudioInstructions: some View {
        switch setupStatus {
        case .notDetected:
            VStack(alignment: .leading, spacing: 4) {
                Text("1. Download LM Studio from lmstudio.ai")
                    .font(.subheadline.weight(.medium))
                Text("2. Open LM Studio and download a model from the Discover tab")
                    .font(.subheadline.weight(.medium))
                Text("3. Go to Local Server and click Start Server")
                    .font(.subheadline.weight(.medium))
            }

        case .notRunning:
            VStack(alignment: .leading, spacing: 4) {
                Text("1. Open LM Studio")
                    .font(.subheadline.weight(.medium))
                Text("2. Click the Local Server tab (↔ icon)")
                    .font(.subheadline.weight(.medium))
                Text("3. Click Start Server")
                    .font(.subheadline.weight(.medium))
            }

        case .noModels:
            VStack(alignment: .leading, spacing: 4) {
                Text("1. In LM Studio, go to Local Server")
                    .font(.subheadline.weight(.medium))
                Text("2. Select a model from the dropdown")
                    .font(.subheadline.weight(.medium))
                Text("3. The server will serve that model automatically")
                    .font(.subheadline.weight(.medium))
            }

        default:
            EmptyView()
        }
    }

    @ViewBuilder
    private var modelRecommendationNote: some View {
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
    }

    // MARK: - Action Buttons

    @ViewBuilder
    private var actionButtons: some View {
        HStack(spacing: 16) {
            if setupStatus == .ready {
                Button("Get Started") {
                    // Dismiss onboarding — handled by parent
                }
                .buttonStyle(.borderedProminent)
            } else {
                Button {
                    Task { await checkStatus() }
                } label: {
                    HStack(spacing: 8) {
                        if checkingStatus {
                            ProgressView().controlSize(.small)
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

    // MARK: - Status Check

    private func checkStatus() async {
        checkingStatus = true
        setupStatus = .checking

        await providerManager.refreshLocalProvider()

        switch providerManager.localStatus {
        case .notDetected:
            setupStatus = .notDetected
        case .noModels:
            setupStatus = .noModels
        case .ready:
            setupStatus = .ready
        case .disconnected, .error:
            if let provider = providerManager.localProvider {
                let isRunning = await provider.isServerRunning()
                setupStatus = isRunning ? .noModels : .notRunning
            } else {
                setupStatus = .notDetected
            }
        case .connecting:
            setupStatus = .checking
        }

        checkingStatus = false
    }

    // MARK: - Shared Subviews

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
}

// MARK: - Backward Compatibility Typealias

/// Keep old name working for any existing call sites during transition.
typealias OllamaOnboardingView = LocalProviderOnboardingView

#Preview {
    LocalProviderOnboardingView()
        .frame(width: 600, height: 500)
}
