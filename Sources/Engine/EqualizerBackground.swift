//
//  EqualizerBackground.swift
//  MIDIKit
//
//  Created by Vaida on 4/25/25.
//

import SwiftUI


struct EqualizerBackground: View {
    
    var body: some View {
        Canvas { context, size in
            var centerLine = Path()
            centerLine.move(to: CGPoint(x: 0, y: size.height / 2))
            centerLine.addLine(to: CGPoint(x: size.width, y: size.height / 2))
            context.stroke(centerLine, with: .color(.secondary.opacity(0.5)), lineWidth: 1)
            
            let segment = size.height / 12
            for i in stride(from: 0.0, to: 6, by: 1) {
                var line = Path()
                line.move(to: CGPoint(x: 0, y: size.height / 2 - segment * i))
                line.addLine(to: CGPoint(x: size.width, y: size.height / 2 - segment * i))
                context.stroke(line, with: .color(.secondary.opacity(0.5)), lineWidth: 0.5)
            }
            for i in stride(from: 0.0, to: 6, by: 1) {
                var line = Path()
                line.move(to: CGPoint(x: 0, y: size.height / 2 + segment * i))
                line.addLine(to: CGPoint(x: size.width, y: size.height / 2 + segment * i))
                context.stroke(line, with: .color(.secondary.opacity(0.5)), lineWidth: 0.5)
            }
        }
    }
}


#Preview {
    EqualizerBackground()
}
