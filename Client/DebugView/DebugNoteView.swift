//
//  DebugNote.swift
//  MIDIKit
//
//  Created by Vaida on 2025-05-17.
//

import SwiftUI
import MIDIKit
import Essentials


struct DebugNoteView: View {
    
    let note: MIDINote
    
    let pixelsPerBeat: Double
    let pixelsPerNote: Double
    
    let maxNote: UInt8
    
    var body: some View {
        ZStack(alignment: .leading) {
            let velocity = linearInterpolate(Double(note.channel), in: 0...15, to: 1...127)
            
            RoundedRectangle(cornerRadius: 5)
                .fill(MIDINote.color(velocity: UInt8(velocity)))
            
//            Text(note.note.description + "|\(self.note.onset, format: .number.precision(.fractionLength(2)))")
//                .padding(.leading, 5)
            
            Text(self.note.channel.description)
                .padding(.leading, 5)
        }
        .frame(width: pixelsPerBeat * note.duration, height: pixelsPerNote)
        .position(x: pixelsPerBeat * note.onset + pixelsPerBeat * note.duration / 2, y: pixelsPerNote * CGFloat(maxNote - note.note))
    }
}
