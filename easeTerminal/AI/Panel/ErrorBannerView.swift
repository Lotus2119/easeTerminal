//
//  ErrorBannerView.swift
//  easeTerminal
//
//  Inline banner for displaying dismissable error messages.
//

import SwiftUI

struct ErrorBannerView: View {
    let message: String
    let onDismiss: () -> Void
    
    var body: some View {
        HStack(spacing: 10) {
            ZStack {
                Circle()
                    .fill(Color.orange.opacity(0.15))
                    .frame(width: 28, height: 28)
                
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 12))
                    .foregroundStyle(.orange)
            }
            
            Text(message)
                .font(.subheadline)
                .lineLimit(2)
            
            Spacer()
            
            Button("Dismiss", systemImage: "xmark") {
                onDismiss()
            }
            .labelStyle(.iconOnly)
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(.secondary)
            .frame(width: 24, height: 24)
            .background(Circle().fill(.quaternary))
            .buttonStyle(.plain)
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(.orange.opacity(0.08))
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .strokeBorder(.orange.opacity(0.2), lineWidth: 1)
                )
        )
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
    }
}
