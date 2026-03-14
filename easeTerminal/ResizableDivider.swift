//
//  ResizableDivider.swift
//  easeTerminal
//
//  Draggable divider that controls the width of an adjacent panel.
//

import SwiftUI

struct ResizableDivider: View {
    @Binding var width: CGFloat
    let minWidth: CGFloat
    let maxWidth: CGFloat
    
    @State private var isDragging = false
    
    var body: some View {
        Rectangle()
            .fill(Color.gray.opacity(isDragging ? 0.3 : 0.1))
            .frame(width: 6)
            .contentShape(Rectangle())
            .onHover { hovering in
                if hovering {
                    NSCursor.resizeLeftRight.push()
                } else {
                    NSCursor.pop()
                }
            }
            .gesture(
                DragGesture(minimumDistance: 1)
                    .onChanged { value in
                        isDragging = true
                        // Dragging left increases panel width, right decreases
                        let newWidth = width - value.translation.width
                        width = min(max(newWidth, minWidth), maxWidth)
                    }
                    .onEnded { _ in
                        isDragging = false
                    }
            )
    }
}
