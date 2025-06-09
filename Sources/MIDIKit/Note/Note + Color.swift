//
//  Note + Color.swift
//  MIDIKit
//
//  Created by Vaida on 2025-06-10.
//

import SwiftUI

extension MIDINote {
    
    /// The MIDI Note color based on the velocity of a note.
    public static func color(velocity: UInt8) -> Color {
        let _velocity = 1 - Double(velocity) / 127
        let velocity = (sin(.pi * _velocity - .pi / 2) + 1) / 2
        
        var red: Double {
            if velocity < 1/4 {
                linearInterpolate(velocity, 0, 1/4, min: 180, max: 190)
            } else if velocity < 3/4 {
                linearInterpolate(velocity, 1/4, 3/4, min: 190, max: 80)
            } else {
                linearInterpolate(velocity, 3/4, 1, min: 80, max: 100)
            }
        }
        
        var green: Double {
            if velocity < 1/4 {
                linearInterpolate(velocity, 0, 1/4, min: 40, max: 200)
            } else if velocity < 1/2 {
                linearInterpolate(velocity, 1/4, 2/4, min: 200, max: 180)
            } else if velocity < 3/4 {
                linearInterpolate(velocity, 2/4, 3/4, min: 180, max: 200)
            } else {
                linearInterpolate(velocity, 3/4, 1, min: 200, max: 150)
            }
        }
        
        var blue: Double {
            linearInterpolate(velocity, 0, 1, min: 30, max: 200)
        }
        
        return Color(red: red, green: green, blue: blue)
    }
    
    private static func linearInterpolate( _ t: Double, _ a: Double, _ b: Double, min: Double, max: Double) -> Double {
        min / 255 + Double(t - a) / Double(b - a) * (max - min) / 255
    }
    
}

#Preview {
    HStack(spacing: 0) {
        ForEach(0..<127) { i in
            Rectangle()
                .fill(MIDINote.color(velocity: UInt8(i)))
                .frame(width: 2, height: 100)
        }
    }
}
