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
    
    let pixelsPerBeat: CGFloat = 100
    let pixelsPerNote: CGFloat = 20
    
    var body: some View {
        let width = pixelsPerBeat * container.contents.max(of: \.offset)!
        let maxNote = container.contents.max(of: \.note)! + 4
        let minNote = container.contents.min(of: \.note)! - 2
        
        VStack {
            ZStack {
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
    
}
