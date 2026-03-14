//
//  AppKeyboardShortcut.swift
//  easeTerminal
//
//  Centralised keyboard shortcut definitions and the View extension for binding them.
//

import SwiftUI

enum AppKeyboardShortcut {
    case toggleAIPanel
    
    var key: KeyEquivalent {
        switch self {
        case .toggleAIPanel: return "a"
        }
    }
    
    var modifiers: EventModifiers {
        switch self {
        case .toggleAIPanel: return [.command, .shift]
        }
    }
}

extension View {
    func keyboardShortcut(for shortcut: AppKeyboardShortcut, action: @escaping () -> Void) -> some View {
        self.background(
            Button("") { action() }
                .keyboardShortcut(shortcut.key, modifiers: shortcut.modifiers)
                .opacity(0)
        )
    }
}
