//
//  DebugSustainView.swift
//  MIDIKit
//
//  Created by Vaida on 2025-05-17.
//

import SwiftUI
import MIDIKit


struct DebugSustainView: View {
    
    let sustain: MIDISustainEvent
    
    let pixelsPerBeat: Double
    let pixelsPerNote: Double
    
    var body: some View {
        ZStack(alignment: .leading) {
            Rectangle()
                .fill(.secondary)
                .frame(width: pixelsPerBeat * sustain.duration, height: pixelsPerNote)
            
            Text(sustain.duration, format: .number.precision(.fractionLength(2)))
                .padding(.leading, 5)
        }
        .position(x: pixelsPerBeat * sustain.onset + pixelsPerBeat * sustain.duration / 2)
    }
}
