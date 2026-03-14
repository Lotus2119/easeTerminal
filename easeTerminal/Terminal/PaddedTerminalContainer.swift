//
//  PaddedTerminalContainer.swift
//  easeTerminal
//
//  NSView container that adds uniform padding around the terminal view.
//

import SwiftUI
import SwiftTerm

/// Container view that adds padding around the terminal
class PaddedTerminalContainer: NSView {
    let terminalView: LocalProcessTerminalView
    let padding: CGFloat = 10
    
    init(terminalView: LocalProcessTerminalView) {
        self.terminalView = terminalView
        super.init(frame: .zero)
        
        addSubview(terminalView)
        wantsLayer = true
        layer?.backgroundColor = NSColor(red: 0.06, green: 0.06, blue: 0.08, alpha: 1.0).cgColor
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override func layout() {
        super.layout()
        // Inset the terminal view by the padding amount
        terminalView.frame = bounds.insetBy(dx: padding, dy: padding)
    }
    
    override var acceptsFirstResponder: Bool { true }
    
    override func becomeFirstResponder() -> Bool {
        return terminalView.becomeFirstResponder()
    }
}
