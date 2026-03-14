//
//  KeychainStoring.swift
//  easeTerminal
//
//  Protocol abstraction for KeychainHelper, enabling dependency injection and testability.
//

import Foundation

/// Protocol that abstracts KeychainHelper for dependency injection and testing.
public protocol KeychainStoring: Sendable {
    func saveAPIKey(_ key: String, forProvider account: String) throws
    func getAPIKey(forProvider account: String) -> String?
    func hasAPIKey(forProvider account: String) -> Bool
    func deleteAPIKey(forProvider account: String) throws
    func listStoredProviders() -> [String]
}

extension KeychainHelper: KeychainStoring {}
