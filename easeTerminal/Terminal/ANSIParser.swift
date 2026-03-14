//
//  ANSIParser.swift
//  easeTerminal
//
//  Parses ANSI escape sequences and converts them to AttributedString styling.
//  This is a minimal implementation - extend as needed for full terminal emulation.
//

import SwiftUI

/// Parses ANSI escape sequences and converts them to AttributedString styling.
/// This is a minimal implementation - extend as needed for full terminal emulation.
struct ANSIParser {
    
    // Current text attributes
    private var foregroundColor: Color = .primary
    private var backgroundColor: Color = .clear
    private var isBold = false
    private var isItalic = false
    private var isUnderline = false
    
    /// Parses a string containing ANSI escape sequences.
    mutating func parse(_ input: String) -> AttributedString {
        var result = AttributedString()
        var currentText = ""
        var index = input.startIndex
        
        while index < input.endIndex {
            let char = input[index]
            
            if char == "\u{1B}" { // ESC
                // Flush current text
                if !currentText.isEmpty {
                    result.append(styledString(currentText))
                    currentText = ""
                }
                
                // Parse escape sequence
                index = parseEscapeSequence(input, from: index)
            } else if char == "\r" {
                // Carriage return - simplified handling
                // Full implementation would move cursor to beginning of line
                index = input.index(after: index)
            } else {
                currentText.append(char)
                index = input.index(after: index)
            }
        }
        
        // Flush remaining text
        if !currentText.isEmpty {
            result.append(styledString(currentText))
        }
        
        return result
    }
    
    private func styledString(_ text: String) -> AttributedString {
        var styled = AttributedString(text)
        styled.foregroundColor = foregroundColor
        
        if isBold {
            styled.font = .system(.body).bold()
        }
        if isItalic {
            styled.font = .system(.body).italic()
        }
        if isUnderline {
            styled.underlineStyle = .single
        }
        
        return styled
    }
    
    private mutating func parseEscapeSequence(_ input: String, from start: String.Index) -> String.Index {
        var index = input.index(after: start) // Skip ESC
        
        guard index < input.endIndex else { return index }
        
        let next = input[index]
        
        if next == "[" {
            // CSI sequence
            index = input.index(after: index)
            var params = ""
            
            while index < input.endIndex {
                let c = input[index]
                if c.isLetter {
                    // End of sequence
                    if c == "m" {
                        applySGRParams(params)
                    }
                    return input.index(after: index)
                }
                params.append(c)
                index = input.index(after: index)
            }
        }
        
        return index
    }
    
    private mutating func applySGRParams(_ params: String) {
        let codes = params.split(separator: ";").compactMap { Int($0) }
        
        if codes.isEmpty {
            resetAttributes()
            return
        }
        
        var i = 0
        while i < codes.count {
            let code = codes[i]
            
            switch code {
            case 0:
                resetAttributes()
            case 1:
                isBold = true
            case 3:
                isItalic = true
            case 4:
                isUnderline = true
            case 22:
                isBold = false
            case 23:
                isItalic = false
            case 24:
                isUnderline = false
            case 30...37:
                foregroundColor = ansiColor(code - 30)
            case 38:
                // Extended foreground color
                if i + 2 < codes.count && codes[i + 1] == 5 {
                    foregroundColor = xterm256Color(codes[i + 2])
                    i += 2
                }
            case 39:
                foregroundColor = .primary
            case 40...47:
                backgroundColor = ansiColor(code - 40)
            case 49:
                backgroundColor = .clear
            case 90...97:
                foregroundColor = ansiColor(code - 90, bright: true)
            default:
                break
            }
            
            i += 1
        }
    }
    
    private mutating func resetAttributes() {
        foregroundColor = .primary
        backgroundColor = .clear
        isBold = false
        isItalic = false
        isUnderline = false
    }
    
    private func ansiColor(_ code: Int, bright: Bool = false) -> Color {
        let colors: [Color] = bright
            ? [.gray, .red, .green, .yellow, .blue, .purple, .cyan, .white]
            : [.black, .red, .green, .yellow, .blue, .purple, .cyan, .white]
        
        return code < colors.count ? colors[code] : .primary
    }
    
    private func xterm256Color(_ code: Int) -> Color {
        // Simplified - just map to basic colors for now
        // Full implementation would handle all 256 colors
        if code < 8 {
            return ansiColor(code)
        } else if code < 16 {
            return ansiColor(code - 8, bright: true)
        }
        // Grayscale and color cube would go here
        return .primary
    }
}
