//
//  TerminalView.swift
//  easeTerminal
//
//  SwiftUI wrapper for SwiftTerm's LocalProcessTerminalView.
//  SwiftTerm handles all VT100/Xterm terminal emulation properly.
//

import SwiftUI
import SwiftTerm

/// SwiftUI wrapper for a single terminal instance
struct TerminalView: View {
    let session: TerminalSession
    @State private var terminalSize: String = "80x24"
    @State private var coordinator: SwiftTerminalView.Coordinator?
    
    var body: some View {
        SwiftTerminalView(
            session: session,
            sizeChanged: { cols, rows in
                terminalSize = "\(cols)x\(rows)"
            },
            processTerminated: {
                session.isActive = false
            },
            coordinatorCreated: { coord in
                self.coordinator = coord
                
                // Wire up terminal content callback
                session.getTerminalContent = { [weak coord] in
                    coord?.getTerminalContent() ?? ""
                }
                
                // Wire up command fill callback
                session.fillCommand = { [weak coord] command in
                    coord?.fillCommand(command)
                }
            }
        )
        .overlay(alignment: .bottomTrailing) {
            Text(terminalSize)
                .font(.system(size: 10, weight: .medium, design: .monospaced))
                .foregroundStyle(.white.opacity(0.35))
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background {
                    Capsule()
                        .fill(.black.opacity(0.3))
                }
                .padding(8)
        }
    }
}


