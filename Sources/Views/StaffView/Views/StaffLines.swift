//
//  StaffLines.swift
//  MIDIKit
//
//  Created by Vaida on 9/28/24.
//

import SwiftUI


struct StaffLines: View {
    
    @Environment(StaffLayout.self) private var layout
    
    var verticalSpacing: Double {
        layout.staffLineSpacing
    }
    
    var lineWidth: Double {
        layout.lineWidth
    }
    
    var paddings: Double {
        lineWidth / 2
    }
    
    var body: some View {
        Canvas { context, size in
            // draw the horizontal lines
            for i in 0..<5 {
                var path = Path()
                path.move(to: CGPoint(x: paddings, y: verticalSpacing * Double(i) + paddings))
                path.addLine(to: CGPoint(x: size.width - paddings, y: verticalSpacing * Double(i) + paddings))
                
                context.stroke(path, with: .foreground, lineWidth: lineWidth)
            }
            
            // closing vertical lines
            for _ in 0..<1 {
                var path = Path()
                path.move(to: CGPoint(x: paddings, y: 0))
                path.addLine(to: CGPoint(x: paddings, y: paddings + 4 * verticalSpacing + 1))
                
                context.stroke(path, with: .foreground, lineWidth: lineWidth * 2)
            }
            // closing vertical lines
            for _ in 0..<1 {
                var path = Path()
                path.move(to: CGPoint(x: size.width - paddings, y: 0))
                path.addLine(to: CGPoint(x: size.width - paddings, y: paddings + 4 * verticalSpacing + 1))
                
                context.stroke(path, with: .foreground, lineWidth: lineWidth * 2)
            }
        }
        .frame(height: lineWidth + verticalSpacing * 4)
        .padding(.all, 1)
    }
    
}

#Preview {
    StaffLines()
        .environment(StaffLayout())
}
