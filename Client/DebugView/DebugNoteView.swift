//
//  DebugNote.swift
//  MIDIKit
//
//  Created by Vaida on 2025-05-17.
//

import SwiftUI
import MIDIKit


struct DebugNoteView: View {
    
    let note: MIDINote
    
    let pixelsPerBeat: Double
    let pixelsPerNote: Double
    
    let maxNote: UInt8
    
    var body: some View {
        ZStack(alignment: .leading) {
            RoundedRectangle(cornerRadius: 5)
                .fill(note.channel == 1 ? .red : .blue)
            
            Text(note.note.description + "|\(self.note.onset, format: .number.precision(.fractionLength(2)))")
                .padding(.leading, 5)
        }
        .frame(width: pixelsPerBeat * note.duration, height: pixelsPerNote)
        .position(x: pixelsPerBeat * note.onset + pixelsPerBeat * note.duration / 2, y: pixelsPerNote * CGFloat(maxNote - note.note))
    }
}
