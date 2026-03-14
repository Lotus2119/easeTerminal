//
//  EmptyTerminalView.swift
//  easeTerminal
//
//  Placeholder shown when no terminal sessions are open.
//

import SwiftUI

struct EmptyTerminalView: View {
    @Bindable var sessionManager: TerminalSessionManager
    
    var body: some View {
        VStack(spacing: 24) {
            ZStack {
                Circle()
                    .fill(.ultraThinMaterial)
                    .frame(width: 100, height: 100)
                
                Image(systemName: "terminal")
                    .font(.system(size: 40, weight: .light))
                    .foregroundStyle(.secondary)
            }
            
            VStack(spacing: 8) {
                Text("No Terminal Open")
                    .font(.title2.weight(.medium))
                    .foregroundStyle(.primary)
                
                Text("Create a new terminal to get started")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            
            Button {
                withAnimation(.smooth) {
                    _ = sessionManager.createSession()
                }
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "plus")
                    Text("Create Terminal")
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 10)
            }
            .buttonStyle(.glassProminent)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(nsColor: NSColor(red: 0.06, green: 0.06, blue: 0.08, alpha: 1.0)))
    }
}
