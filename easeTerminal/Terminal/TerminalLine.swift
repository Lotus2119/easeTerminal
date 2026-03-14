//
//  TerminalLine.swift
//  easeTerminal
//
//  A single line of terminal output with optional styled content.
//

import Foundation
import SwiftUI

/// Represents a line of terminal output with optional styling.
struct TerminalLine: Identifiable {
    let id = UUID()
    var content: AttributedString
}
