//
//  KeychainHelper.swift
//  easeTerminal
//
//  Secure storage for API keys using the macOS Keychain.
//  Keys are never stored in UserDefaults, plists, or logged.
//

import Foundation
import Security

/// Errors that can occur during Keychain operations
public enum KeychainError: Error, LocalizedError {
    case duplicateEntry
    case itemNotFound
    case unexpectedStatus(OSStatus)
    case encodingError
    case decodingError
    
    public var errorDescription: String? {
        switch self {
        case .duplicateEntry:
            return "Item already exists in Keychain"
        case .itemNotFound:
            return "Item not found in Keychain"
        case .unexpectedStatus(let status):
            return "Keychain error: \(status)"
        case .encodingError:
            return "Failed to encode data for Keychain"
        case .decodingError:
            return "Failed to decode data from Keychain"
        }
    }
}

/// Helper class for secure Keychain operations.
/// All API keys are stored here, never in UserDefaults or files.
public final class KeychainHelper: Sendable {
    public static let shared = KeychainHelper()
    
    private let serviceName = "com.easeTerminal.ai-providers"
    
    private init() {}
    
    // MARK: - Public API
    
    /// Save an API key to the Keychain
    /// - Parameters:
    ///   - key: The API key to store
    ///   - account: Identifier for the provider (e.g., "anthropic", "openai")
    public func saveAPIKey(_ key: String, forProvider account: String) throws {
        guard let data = key.data(using: .utf8) else {
            throw KeychainError.encodingError
        }

        let lookupQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceName,
            kSecAttrAccount as String: account
        ]

        let existsStatus = SecItemCopyMatching(lookupQuery as CFDictionary, nil)

        if existsStatus == errSecSuccess {
            // Item already exists — update it in place to preserve the ACL
            // (and therefore any "Always Allow" grant the user has already given).
            let attributesToUpdate: [String: Any] = [kSecValueData as String: data]
            let updateStatus = SecItemUpdate(lookupQuery as CFDictionary, attributesToUpdate as CFDictionary)
            guard updateStatus == errSecSuccess else {
                throw KeychainError.unexpectedStatus(updateStatus)
            }
        } else {
            // No existing item — add a new one.
            let addQuery: [String: Any] = [
                kSecClass as String: kSecClassGenericPassword,
                kSecAttrService as String: serviceName,
                kSecAttrAccount as String: account,
                kSecValueData as String: data,
                kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly
            ]
            let addStatus = SecItemAdd(addQuery as CFDictionary, nil)
            guard addStatus == errSecSuccess else {
                throw KeychainError.unexpectedStatus(addStatus)
            }
        }
    }
    
    /// Retrieve an API key from the Keychain
    /// - Parameter account: Identifier for the provider
    /// - Returns: The stored API key, or nil if not found
    public func getAPIKey(forProvider account: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceName,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        
        guard status == errSecSuccess,
              let data = result as? Data,
              let key = String(data: data, encoding: .utf8) else {
            return nil
        }
        
        return key
    }
    
    /// Check if an API key exists for a provider
    /// - Parameter account: Identifier for the provider
    /// - Returns: True if a key is stored
    public func hasAPIKey(forProvider account: String) -> Bool {
        // kSecReturnAttributes (not kSecReturnData) avoids a data-access prompt.
        // kSecUseAuthenticationUISkip prevents a UI prompt entirely — the call
        // returns errSecInteractionNotAllowed when the item exists but needs auth,
        // which we treat the same as success for the purposes of "does it exist".
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceName,
            kSecAttrAccount as String: account,
            kSecReturnAttributes as String: true,
            kSecUseAuthenticationUI as String: kSecUseAuthenticationUISkip
        ]

        let status = SecItemCopyMatching(query as CFDictionary, nil)
        return status == errSecSuccess || status == errSecInteractionNotAllowed
    }
    
    /// Delete an API key from the Keychain
    /// - Parameter account: Identifier for the provider
    public func deleteAPIKey(forProvider account: String) throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceName,
            kSecAttrAccount as String: account
        ]
        
        let status = SecItemDelete(query as CFDictionary)
        
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainError.unexpectedStatus(status)
        }
    }
    
    /// List all provider accounts that have stored keys
    /// - Returns: Array of provider identifiers
    public func listStoredProviders() -> [String] {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceName,
            kSecReturnAttributes as String: true,
            kSecMatchLimit as String: kSecMatchLimitAll
        ]
        
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        
        guard status == errSecSuccess,
              let items = result as? [[String: Any]] else {
            return []
        }
        
        return items.compactMap { $0[kSecAttrAccount as String] as? String }
    }
}
