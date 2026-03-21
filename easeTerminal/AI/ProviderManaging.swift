//
//  ProviderManaging.swift
//  easeTerminal
//
//  Protocol abstraction for ProviderManager, enabling dependency injection and testability.
//

import Foundation
import SwiftUI

/// Protocol that abstracts ProviderManager for dependency injection and testing.
@MainActor
public protocol ProviderManaging: AnyObject, Observable {
    var operatingMode: AIOperatingMode { get set }
    var localProvider: (any LocalInferenceProvider)? { get }
    var selectedLocalProviderID: String { get }
    var localStatus: ProviderStatus { get }
    var availableLocalModels: [AIModel] { get }
    var localReasoningModel: AIModel? { get set }
    var contextPackagingModel: AIModel? { get set }
    var activeCloudProvider: (any CloudReasoningProvider)? { get }
    var selectedCloudProviderID: String? { get set }
    var cloudConfigured: Bool { get }
    var cloudModelName: String? { get }
    var isLocalProviderAvailable: Bool { get }
    var needsOnboarding: Bool { get }
    var isReady: Bool { get }
    var statusText: String { get }
    var isCloudAvailable: Bool { get }
    var statusColor: Color { get }
    var availableLocalProviders: [(id: String, name: String)] { get }
    var availableCloudProviders: [(id: String, name: String)] { get }

    func initialize() async
    func refreshLocalProvider() async
    func refreshCloudStatus()
    func setLocalProvider(id: String)
    func setLocalBaseURL(_ url: URL)
    func reason(
        terminalContext: String,
        userQuery: String?,
        conversationHistory: [ConversationMessage]
    ) async throws -> AICompletionResult
    func complete(
        messages: [ConversationMessage],
        systemPrompt: String?
    ) async throws -> AICompletionResult
    func switchToLocalMode()
    func switchToHybridMode() throws
    func fallbackToLocal()
}
