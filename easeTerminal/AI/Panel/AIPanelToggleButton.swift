//
//  AIPanelToggleButton.swift
//  easeTerminal
//
//  Toolbar button for showing and hiding the AI side panel.
//

import SwiftUI

/// Toolbar button for toggling the AI panel
struct AIPanelToggleButton: View {
    @Bindable var panelState: AIPanelState
    
    var body: some View {
        Button {
            panelState.togglePanel()
        } label: {
            Image(systemName: "sparkle")
        }
        .help(panelState.isPanelVisible ? "Hide AI Panel (⇧⌘A)" : "Show AI Panel (⇧⌘A)")
        .tint(panelState.isPanelVisible ? .accentColor : .none)
        .glassEffect(.regular.tint(panelState.isPanelVisible ? .accentColor : .none).interactive())
    }
}
