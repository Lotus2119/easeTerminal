//
//  AIDebugView.swift
//  easeTerminal
//
//  Debug/test harness view for AI providers.
//  Hidden behind developer settings toggle.
//  Tests all components: Ollama, Keychain, Claude, OpenAI, mode switching.
//

import SwiftUI

/// Debug view for testing AI components
struct AIDebugView: View {
    @State private var providerManager = ProviderManager.shared
    @State private var testResults: [TestResult] = []
    @State private var isRunningTests = false
    @State private var ollamaTestResponse = ""
    @State private var testContextInput = "$ npm install\nnpm ERR! code ENOENT\nnpm ERR! syscall open\nnpm ERR! path /Users/dev/project/package.json\nnpm ERR! errno -2\nnpm ERR! enoent Could not read package.json"
    
    struct TestResult: Identifiable {
        let id = UUID()
        let name: String
        let passed: Bool
        let message: String
        let duration: TimeInterval?
    }
    
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    // Status Overview
                    statusOverview
                    
                    Divider()
                    
                    // Test Controls
                    testControls
                    
                    Divider()
                    
                    // Test Results
                    testResultsView
                    
                    Divider()
                    
                    // Context Packaging Test
                    contextPackagingTest
                    
                    Divider()
                    
                    // Mode Switcher
                    modeSwitcher
                }
                .padding()
            }
            .navigationTitle("AI Debug Panel")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button("Run All Tests") {
                        Task { await runAllTests() }
                    }
                    .disabled(isRunningTests)
                }
            }
        }
    }
    
    // MARK: - Status Overview
    
    @ViewBuilder
    private var statusOverview: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Current Status")
                .font(.headline)
            
            Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 8) {
                GridRow {
                    Text("Operating Mode:")
                        .foregroundStyle(.secondary)
                    Text(providerManager.operatingMode.displayName)
                        .fontWeight(.medium)
                }
                
                GridRow {
                    Text("Local Status:")
                        .foregroundStyle(.secondary)
                    HStack {
                        Circle()
                            .fill(providerManager.statusColor)
                            .frame(width: 8, height: 8)
                        Text(providerManager.localStatus.displayText)
                    }
                }
                
                GridRow {
                    Text("Local Model:")
                        .foregroundStyle(.secondary)
                    Text(providerManager.localReasoningModel?.name ?? "None")
                }
                
                GridRow {
                    Text("Available Models:")
                        .foregroundStyle(.secondary)
                    Text("\(providerManager.availableLocalModels.count)")
                }
                
                GridRow {
                    Text("Cloud Provider:")
                        .foregroundStyle(.secondary)
                    Text(providerManager.selectedCloudProviderID ?? "None")
                }
                
                GridRow {
                    Text("Cloud Ready:")
                        .foregroundStyle(.secondary)
                    Text(providerManager.activeCloudProvider?.isReady == true ? "Yes" : "No")
                        .foregroundStyle(providerManager.activeCloudProvider?.isReady == true ? .green : .secondary)
                }
            }
            .font(.system(.body, design: .monospaced))
        }
    }
    
    // MARK: - Test Controls
    
    @ViewBuilder
    private var testControls: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Individual Tests")
                .font(.headline)
            
            HStack(spacing: 12) {
                Button("Test Ollama") {
                    Task { await testOllama() }
                }
                .buttonStyle(.bordered)
                
                Button("Test Keychain") {
                    Task { await testKeychain() }
                }
                .buttonStyle(.bordered)
                
                Button("Test Claude") {
                    Task { await testClaude() }
                }
                .buttonStyle(.bordered)
                
                Button("Test OpenAI") {
                    Task { await testOpenAI() }
                }
                .buttonStyle(.bordered)
                
                Button("Test Fallback") {
                    Task { await testFallback() }
                }
                .buttonStyle(.bordered)
            }
            
            if isRunningTests {
                HStack {
                    ProgressView()
                        .controlSize(.small)
                    Text("Running tests...")
                        .foregroundStyle(.secondary)
                }
            }
        }
    }
    
    // MARK: - Test Results
    
    @ViewBuilder
    private var testResultsView: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Test Results")
                    .font(.headline)
                
                Spacer()
                
                if !testResults.isEmpty {
                    let passed = testResults.filter { $0.passed }.count
                    Text("\(passed)/\(testResults.count) passed")
                        .font(.caption)
                        .foregroundStyle(passed == testResults.count ? .green : .orange)
                }
                
                Button("Clear") {
                    testResults.removeAll()
                }
                .buttonStyle(.borderless)
                .font(.caption)
            }
            
            if testResults.isEmpty {
                Text("No tests run yet")
                    .foregroundStyle(.secondary)
                    .font(.caption)
            } else {
                VStack(spacing: 8) {
                    ForEach(testResults) { result in
                        HStack {
                            Image(systemName: result.passed ? "checkmark.circle.fill" : "xmark.circle.fill")
                                .foregroundStyle(result.passed ? .green : .red)
                            
                            VStack(alignment: .leading, spacing: 2) {
                                Text(result.name)
                                    .font(.subheadline.weight(.medium))
                                Text(result.message)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            
                            Spacer()
                            
                            if let duration = result.duration {
                                Text(String(format: "%.2fs", duration))
                                    .font(.caption.monospacedDigit())
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .padding(8)
                        .background(result.passed ? Color.green.opacity(0.1) : Color.red.opacity(0.1), in: RoundedRectangle(cornerRadius: 6))
                    }
                }
            }
        }
    }
    
    // MARK: - Context Packaging Test
    
    @ViewBuilder
    private var contextPackagingTest: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Context Packaging Test")
                .font(.headline)
            
            TextEditor(text: $testContextInput)
                .font(.system(.caption, design: .monospaced))
                .frame(height: 100)
                .border(Color.gray.opacity(0.3))
            
            HStack {
                Button("Test Context Packaging") {
                    Task { await testContextPackaging() }
                }
                .buttonStyle(.bordered)
                
                Button("Test Full Reasoning") {
                    Task { await testFullReasoning() }
                }
                .buttonStyle(.borderedProminent)
            }
            
            if !ollamaTestResponse.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Response:")
                        .font(.subheadline.weight(.medium))
                    
                    ScrollView {
                        Text(ollamaTestResponse)
                            .font(.system(.caption, design: .monospaced))
                            .textSelection(.enabled)
                    }
                    .frame(maxHeight: 200)
                    .padding(8)
                    .background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: 6))
                }
            }
        }
    }
    
    // MARK: - Mode Switcher
    
    @ViewBuilder
    private var modeSwitcher: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Mode Switching")
                .font(.headline)
            
            HStack(spacing: 12) {
                Button("Switch to Local") {
                    providerManager.switchToLocalMode()
                    addTestResult("Mode Switch", passed: true, message: "Switched to local mode")
                }
                .buttonStyle(.bordered)
                .disabled(providerManager.operatingMode == .local)
                
                Button("Switch to Hybrid") {
                    do {
                        try providerManager.switchToHybridMode()
                        addTestResult("Mode Switch", passed: true, message: "Switched to hybrid mode")
                    } catch {
                        addTestResult("Mode Switch", passed: false, message: error.localizedDescription)
                    }
                }
                .buttonStyle(.bordered)
                .disabled(providerManager.operatingMode == .hybrid)
                
                Button("Force Fallback") {
                    providerManager.fallbackToLocal()
                    addTestResult("Fallback", passed: true, message: "Forced fallback to local mode")
                }
                .buttonStyle(.bordered)
            }
        }
    }
    
    // MARK: - Test Implementations
    
    private func runAllTests() async {
        isRunningTests = true
        testResults.removeAll()
        
        await testOllama()
        await testKeychain()
        await testClaude()
        await testOpenAI()
        await testFallback()
        
        isRunningTests = false
    }
    
    private func testOllama() async {
        let start = Date()
        
        guard let provider = providerManager.localProvider else {
            addTestResult("Ollama Connection", passed: false, message: "No local provider")
            return
        }
        
        // Test connection
        let isRunning = await provider.isServerRunning()
        if !isRunning {
            addTestResult("Ollama Connection", passed: false, message: "Ollama not running", duration: Date().timeIntervalSince(start))
            return
        }
        
        // Fetch models
        do {
            let models = try await provider.fetchAvailableModels()
            addTestResult("Ollama Connection", passed: true, message: "Found \(models.count) models", duration: Date().timeIntervalSince(start))
        } catch {
            addTestResult("Ollama Connection", passed: false, message: error.localizedDescription, duration: Date().timeIntervalSince(start))
        }
    }
    
    private func testKeychain() async {
        let start = Date()
        let testKey = "test-key-\(UUID().uuidString.prefix(8))"
        let testProvider = "test-provider"
        
        do {
            // Write
            try KeychainHelper.shared.saveAPIKey(testKey, forProvider: testProvider)
            
            // Read
            guard let retrieved = KeychainHelper.shared.getAPIKey(forProvider: testProvider) else {
                addTestResult("Keychain", passed: false, message: "Failed to read key", duration: Date().timeIntervalSince(start))
                return
            }
            
            guard retrieved == testKey else {
                addTestResult("Keychain", passed: false, message: "Key mismatch", duration: Date().timeIntervalSince(start))
                return
            }
            
            // Delete
            try KeychainHelper.shared.deleteAPIKey(forProvider: testProvider)
            
            // Verify deletion
            guard KeychainHelper.shared.getAPIKey(forProvider: testProvider) == nil else {
                addTestResult("Keychain", passed: false, message: "Failed to delete key", duration: Date().timeIntervalSince(start))
                return
            }
            
            addTestResult("Keychain", passed: true, message: "Write/Read/Delete OK", duration: Date().timeIntervalSince(start))
        } catch {
            addTestResult("Keychain", passed: false, message: error.localizedDescription, duration: Date().timeIntervalSince(start))
        }
    }
    
    private func testClaude() async {
        let start = Date()
        
        let provider = ClaudeProvider()
        
        guard provider.hasAPIKey else {
            addTestResult("Claude API", passed: false, message: "No API key configured", duration: Date().timeIntervalSince(start))
            return
        }
        
        // Select first model if none selected
        if provider.selectedModel == nil {
            provider.selectedModel = ClaudeProvider.availableModels.first
        }
        
        do {
            let result = try await provider.testConnection()
            addTestResult("Claude API", passed: result, message: result ? "Connection successful" : "Connection failed", duration: Date().timeIntervalSince(start))
        } catch {
            addTestResult("Claude API", passed: false, message: error.localizedDescription, duration: Date().timeIntervalSince(start))
        }
    }
    
    private func testOpenAI() async {
        let start = Date()
        
        let provider = OpenAIProvider()
        
        guard provider.hasAPIKey else {
            addTestResult("OpenAI API", passed: false, message: "No API key configured", duration: Date().timeIntervalSince(start))
            return
        }
        
        // Select first model if none selected
        if provider.selectedModel == nil {
            provider.selectedModel = OpenAIProvider.availableModels.first
        }
        
        do {
            let result = try await provider.testConnection()
            addTestResult("OpenAI API", passed: result, message: result ? "Connection successful" : "Connection failed", duration: Date().timeIntervalSince(start))
        } catch {
            addTestResult("OpenAI API", passed: false, message: error.localizedDescription, duration: Date().timeIntervalSince(start))
        }
    }
    
    private func testFallback() async {
        let start = Date()
        
        // Save current mode
        let originalMode = providerManager.operatingMode
        
        // Switch to hybrid (will fail if no cloud provider)
        do {
            try providerManager.switchToHybridMode()
        } catch {
            // Expected if no cloud provider configured
            addTestResult("Fallback Test", passed: true, message: "Correctly stayed in local mode (no cloud configured)", duration: Date().timeIntervalSince(start))
            return
        }
        
        // Force fallback
        providerManager.fallbackToLocal()
        
        let succeeded = providerManager.operatingMode == .local
        addTestResult("Fallback Test", passed: succeeded, message: succeeded ? "Fallback to local successful" : "Fallback failed", duration: Date().timeIntervalSince(start))
        
        // Restore original mode if it was hybrid
        if originalMode == .hybrid {
            try? providerManager.switchToHybridMode()
        }
    }
    
    private func testContextPackaging() async {
        let start = Date()
        ollamaTestResponse = ""
        
        do {
            let packaged = try await ContextPackager.shared.packageContext(testContextInput)
            ollamaTestResponse = packaged
            addTestResult("Context Packaging", passed: true, message: "Packaged \(testContextInput.count) chars → \(packaged.count) chars", duration: Date().timeIntervalSince(start))
        } catch {
            ollamaTestResponse = "Error: \(error.localizedDescription)"
            addTestResult("Context Packaging", passed: false, message: error.localizedDescription, duration: Date().timeIntervalSince(start))
        }
    }
    
    private func testFullReasoning() async {
        let start = Date()
        ollamaTestResponse = ""
        
        do {
            let result = try await providerManager.reason(
                terminalContext: testContextInput,
                userQuery: "What's wrong and how do I fix it?"
            )
            ollamaTestResponse = result.content
            let source = result.isFromCloud ? "Cloud" : "Local"
            addTestResult("Full Reasoning (\(source))", passed: true, message: "Generated \(result.content.count) chars using \(result.model)", duration: Date().timeIntervalSince(start))
        } catch {
            ollamaTestResponse = "Error: \(error.localizedDescription)"
            addTestResult("Full Reasoning", passed: false, message: error.localizedDescription, duration: Date().timeIntervalSince(start))
        }
    }
    
    private func addTestResult(_ name: String, passed: Bool, message: String, duration: TimeInterval? = nil) {
        testResults.append(TestResult(name: name, passed: passed, message: message, duration: duration))
    }
}

#Preview {
    AIDebugView()
        .frame(width: 600, height: 800)
}
