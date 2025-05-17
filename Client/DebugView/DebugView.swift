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
        let downbeats = container.downbeats()
        
        VStack {
            ZStack {
                ForEach(container.contents, id: \.self) { note in
                    DebugNoteView(note: note, pixelsPerBeat: pixelsPerBeat, pixelsPerNote: pixelsPerNote)
                }
            }
            .frame(width: width, height: 88 * pixelsPerNote)
            
            ZStack {
                ForEach(container.sustains, id: \.self) { sustain in
                    DebugSustainView(sustain: sustain, pixelsPerBeat: pixelsPerBeat, pixelsPerNote: pixelsPerNote)
                }
                .padding(.vertical, 5)
            }
        }
        .background {
            ZStack {
                ForEach(downbeats, id: \.self) { downbeat in
                    Rectangle()
                        .fill(.secondary.opacity(0.5))
                        .frame(width: 2)
                        .overlay(alignment: .topTrailing) {
                            Text(downbeat.onset, format: .number.precision(.fractionLength(2)))
                                .frame(width: 40)
                                .offset(x: 40)
                                .foregroundStyle(.secondary.opacity(0.5))
                        }
                        .position(x: pixelsPerBeat * downbeat.onset, y: 45 * pixelsPerNote)
                }
                .padding(.vertical, 5)
            }
        }
    }
    
}
