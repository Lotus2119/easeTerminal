//
//  SidebarFooterView.swift
//  easeTerminal
//
//  Footer bar shown at the bottom of the sidebar with AI status and new terminal button.
//

import SwiftUI

struct SidebarFooterView: View {
    @Bindable var sessionManager: TerminalSessionManager
    @State private var showingSettings = false
    
    private var providerManager: ProviderManager { ProviderManager.shared }
    
    // Use the provider manager's computed status color
    private var statusColor: Color {
        providerManager.statusColor
    }
    
    // Use the provider manager's computed status text
    private var statusText: String {
        providerManager.statusText
    }
    
    var body: some View {
        VStack(spacing: 12) {
            // AI Status indicator
            HStack(spacing: 10) {
                Circle()
                    .fill(statusColor)
                    .frame(width: 8, height: 8)
                    .overlay(
                        Circle()
                            .stroke(statusColor.opacity(0.3), lineWidth: 2)
                            .scaleEffect(1.5)
                    )
                
                VStack(alignment: .leading, spacing: 2) {
                    Text("AI Assistant")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.primary)
                    Text(statusText)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                
                Spacer()
                
                Button {
                    showingSettings = true
                } label: {
                    Image(systemName: "gearshape")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 10))
            
            // New terminal button
            Button {
                withAnimation(.smooth) {
                    _ = sessionManager.createSession()
                }
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "plus")
                        .font(.system(size: 12, weight: .semibold))
                    Text("New Terminal")
                        .font(.subheadline.weight(.medium))
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
            }
            .buttonStyle(.glass)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 12)
        .sheet(isPresented: $showingSettings) {
            AISettingsView()
                .frame(minWidth: 500, minHeight: 400)
        }
    }
}
