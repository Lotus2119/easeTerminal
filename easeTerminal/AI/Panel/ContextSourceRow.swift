//
//  ContextSourceRow.swift
//  easeTerminal
//
//  Row view displaying a context source with an include/exclude toggle.
//

import SwiftUI

struct ContextSourceRow: View {
    let icon: String
    let iconColor: Color
    let title: String
    let detail: String
    let isIncluded: Bool
    let onToggle: () -> Void
    
    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(iconColor.opacity(0.15))
                    .frame(width: 28, height: 28)
                
                Image(systemName: icon)
                    .font(.system(size: 12))
                    .foregroundStyle(iconColor)
            }
            
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline.weight(.medium))
                Text(detail)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            
            Spacer()
            
            Toggle("", isOn: Binding(
                get: { isIncluded },
                set: { _ in onToggle() }
            ))
            .toggleStyle(.switch)
            .controlSize(.small)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(isIncluded ? Color.accentColor.opacity(0.08) : .clear)
        )
    }
}
