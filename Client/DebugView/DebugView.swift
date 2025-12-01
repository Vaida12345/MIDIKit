//
//  DebugView.swift
//  MIDIKit
//
//  Created by Vaida on 2025-05-17.
//

import SwiftUI
import Foundation
import MIDIKit


struct DebugView: View {
    
    let container: IndexedContainer
    let bpm = 4.0
    
    let pixelsPerBeat: CGFloat = 100
    let pixelsPerNote: CGFloat = 20
    let downbeats: [Double]
    
    var body: some View {
        let width = pixelsPerBeat * container.contents.max(of: \.offset)!
        let maxNote = container.contents.max(of: \.note)! + 4
        let minNote = container.contents.min(of: \.note)! - 2
        
        VStack {
            ZStack {
                Canvas { context, size in
                    for downbeat in downbeats {
                        context.fill(
                            Path(CGRect(x: pixelsPerBeat * downbeat , y: 0, width: 1, height: size.height)),
                            with: .color(.blue)
                        )
                    }
                }
                
                Canvas { context, size in
                    var x = 0.0
                    while x < size.width {
                        context.fill(
                            Path(CGRect(x: x, y: 0, width: 1, height: size.height)),
                            with: .color(.secondary.opacity(0.5))
                        )
                        
                        x += pixelsPerBeat * 4
                    }
                }
                
                Rectangle()
                    .fill(.secondary.opacity(0.5))
                    .frame(width: width, height: 1)
                    .position(x: width / 2, y: pixelsPerNote * CGFloat(maxNote - 60))
                
                ForEach(container.contents, id: \.self) { note in
                    DebugNoteView(note: note, pixelsPerBeat: pixelsPerBeat, pixelsPerNote: pixelsPerNote, maxNote: maxNote)
                }
            }
            .frame(width: width, height: Double(maxNote - minNote) * pixelsPerNote)
            
            ZStack {
                ForEach(container.sustains, id: \.self) { sustain in
                    DebugSustainView(sustain: sustain, pixelsPerBeat: pixelsPerBeat, pixelsPerNote: pixelsPerNote)
                }
                .padding(.vertical, 5)
            }
        }
    }
    
    
    init(container: IndexedContainer) async {
        self.container = container
        self.downbeats = await container.downbeats()
    }
    
}
