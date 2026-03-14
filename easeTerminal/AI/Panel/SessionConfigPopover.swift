//
//  SessionConfigPopover.swift
//  easeTerminal
//
//  Popover for configuring per-session AI settings.
//

import SwiftUI

struct SessionConfigPopover: View {
    @Binding var autoFillMode: AutoFillMode
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Session Settings")
                .font(.headline)
            
            VStack(alignment: .leading, spacing: 12) {
                Text("Auto-Fill Mode")
                    .font(.subheadline.weight(.medium))
                
                Picker("Auto-Fill Mode", selection: $autoFillMode) {
                    ForEach(AutoFillMode.allCases, id: \.self) { mode in
                        VStack(alignment: .leading) {
                            Text(mode.rawValue)
                            Text(mode.description)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .tag(mode)
                    }
                }
                .pickerStyle(.radioGroup)
                .labelsHidden()
            }
            
            HStack {
                Spacer()
                Button("Done") {
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
            }
        }
        .padding()
        .frame(width: 280)
    }
}
