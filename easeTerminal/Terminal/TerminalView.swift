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
                .font(.caption2.monospaced())
                .foregroundStyle(.secondary)
                .padding(6)
        }
    }
}


